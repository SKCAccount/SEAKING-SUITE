#!/usr/bin/env bash
#
# restore-supabase.sh - load a snapshot made by backup-supabase.sh into an EMPTY Supabase project.
#
#   Usage:    ./restore-supabase.sh <snapshot-folder>
#             ./restore-supabase.sh --storage-only <snapshot-folder>    (re-upload the files only)
#
# Run it in Git Bash. Needs Docker Desktop (running) and Node.js 18+. Read README.md first.
#
# It asks for (your typing stays hidden) the TARGET project's database connection string
# (Session pooler URI with password) and, to restore Storage files, the target project URL and
# its service_role / secret key. Nothing you type is shown, saved, or put on a command line.
#
# What it does, in order:
#   1. checks every checksum in manifest.json (refuses a damaged or unfinished snapshot);
#   2. refuses a target that already has tables in 'public', sign-in users, or Storage buckets;
#   3. asks you to type RESTORE;
#   4. in ONE transaction (all or nothing): roles.sql, schema.sql, the migration-history table,
#      platform_customizations.sql, then data.sql and the migration history rows (they run with
#      session_replication_role = replica, so triggers and foreign-key checks do not block the
#      load), then re-creates the pg_cron jobs and refreshes materialized views;
#   5. re-uploads every Storage file, then downloads each one again to compare its SHA-256;
#   6. compares every table's row count with manifest.json and lists what is left to do by hand.

set -Eeuo pipefail
umask 077

STEP="checking the setup"
WORK=""
DONE=0
DB_RESTORED=0

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
step() { STEP="$*"; printf '\n==> %s\n' "$*"; }

cleanup() {
  local rc=$?
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf -- "$WORK"; fi
  if [ "$DONE" != 1 ]; then
    if [ "$DB_RESTORED" = 1 ]; then
      printf '\nRESTORE NOT FINISHED (stopped while: %s).\nThe DATABASE part was restored and committed. Fix the problem above, then finish with:\n  ./restore-supabase.sh --storage-only "<snapshot-folder>"\n' "$STEP" >&2
    else
      printf '\nRESTORE FAILED while: %s\nNothing was written to the target database.\n' "$STEP" >&2
    fi
    [ "$rc" -ne 0 ] || rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

to_unix()  { if command -v cygpath >/dev/null 2>&1; then cygpath -u -- "$1"; else printf '%s' "$1"; fi; }
to_win()   { if command -v cygpath >/dev/null 2>&1; then cygpath -w -- "$1"; else printf '%s' "$1"; fi; }
to_mixed() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -- "$1"; else printf '%s' "$1"; fi; }

ask_secret() {
  local __answer=""
  if ! IFS= read -r -s -p "$1" __answer; then printf '\n' >&2; die "No answer was typed (input ended)."; fi
  printf '\n' >&2
  __answer="${__answer//$'\r'/}"
  __answer="${__answer#"${__answer%%[![:space:]]*}"}"
  __answer="${__answer%"${__answer##*[![:space:]]}"}"
  printf -v "$2" '%s' "$__answer"
}

pct_decode() {
  local s="$1" out="" ch
  while [ -n "$s" ]; do
    if [ "${s:0:1}" = "%" ] && [[ "${s:1:2}" =~ ^[0-9A-Fa-f]{2}$ ]]; then
      printf -v ch "\\x${s:1:2}"; out+="$ch"; s="${s:3}"
    else
      out+="${s:0:1}"; s="${s:1}"
    fi
  done
  REPLY="$out"
}

parse_conn() {
  local u="$1" rest userinfo hostpart hp dbpath
  case "$u" in
    postgresql://*|postgres://*) ;;
    *) die "That does not look like a database connection string (it must start with postgresql://). In the dashboard: Connect > Session pooler > URI." ;;
  esac
  DB_SCHEME="${u%%://*}"
  rest="${u#*://}"
  case "$rest" in *@*) ;; *) die "The connection string has no user name and password part (no '@'). Copy the whole Session pooler URI." ;; esac
  userinfo="${rest%@*}"
  hostpart="${rest##*@}"
  DB_USER="${userinfo%%:*}"
  if [ "$DB_USER" = "$userinfo" ]; then DB_PASS=""; else DB_PASS="${userinfo#*:}"; fi
  case "$DB_PASS" in
    ''|*YOUR-PASSWORD*|*YOUR_PASSWORD*)
      say "   The connection string has no real password in it."
      ask_secret "   Type the target database password (hidden): " DB_PASS
      [ -n "$DB_PASS" ] || die "No password was typed." ;;
    *) pct_decode "$DB_PASS"; DB_PASS="$REPLY" ;;
  esac
  hp="${hostpart%%[/?]*}"
  DB_HOST="${hp%:*}"
  if [ "$DB_HOST" = "$hp" ]; then DB_PORT=5432; else DB_PORT="${hp##*:}"; fi
  dbpath="${hostpart#"$hp"}"; dbpath="${dbpath#/}"; DB_NAME="${dbpath%%\?*}"; DB_NAME="${DB_NAME:-postgres}"
  [[ "$DB_PORT" =~ ^[0-9]+$ ]] || die "Could not read the port number in the connection string."
  [ -n "$DB_HOST" ] || die "Could not read the host name in the connection string."
  if [ "$DB_PORT" = 6543 ]; then
    die "That is the Transaction pooler (port 6543), which cannot be used for this. Use the Session pooler string (port 5432): Dashboard > Connect > Session pooler."
  fi
  DB_URL_NOPASS="${DB_SCHEME}://${DB_USER}@${hostpart}"
  DB_REF=""
  case "$DB_USER" in postgres.?*) DB_REF="${DB_USER#postgres.}" ;; esac
  case "$DB_HOST" in
    db.*.supabase.co)
      if [ -z "$DB_REF" ]; then DB_REF="${DB_HOST#db.}"; DB_REF="${DB_REF%.supabase.co}"; fi
      warn "This is the 'Direct connection' string. It only works on networks with IPv6. If it cannot connect, use the 'Session pooler' string instead." ;;
    *.pooler.supabase.com)
      [ -n "$DB_REF" ] || die "For the Session pooler the user name must look like postgres.<project-ref>. Copy the whole URI from the dashboard." ;;
  esac
}

pick_psql_image() {
  PSQL_IMAGE="$(docker image ls --format '{{.Repository}}:{{.Tag}}' 'public.ecr.aws/supabase/postgres' 2>/dev/null | grep -v '<none>' | sort -V | tail -n 1 || true)"
  if [ -z "$PSQL_IMAGE" ]; then PSQL_IMAGE="postgres:17-alpine"; say "(Docker will download the standard PostgreSQL client image once, about 100 MB.)"; fi
}
psql_tgt() {
  PGPASSWORD="$DB_PASS" MSYS_NO_PATHCONV=1 docker run --rm -i --network host -e PGPASSWORD "$PSQL_IMAGE" \
    psql "$DB_URL_NOPASS" -X -q -v ON_ERROR_STOP=1 "$@"
}

# Drop COPY blocks that carry no rows. They change nothing, and some newer Supabase tables
# (storage.buckets_vectors, storage.vector_indexes) refuse even an empty COPY from the postgres user.
without_empty_copies() {
  LC_ALL=C awk '
    inb { print; if ($0 == "\\.") inb = 0; next }
    /^COPY .* FROM stdin;$/ {
      hdr = $0
      if ((getline nxt) <= 0) { print hdr; exit }
      if (nxt == "\\.") next
      print hdr; print nxt; inb = 1; next
    }
    { print }
  ' "$1"
}

# Snapshot checks, Storage upload and row-count comparison (Node.js). Keys only via SB_URL / SB_KEY.
node_helper() {
  node - "$@" <<'__NODE_EOF__'
'use strict';
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const [mode, SNAP, EXTRA] = process.argv.slice(2);
const BASE = (process.env.SB_URL || '').replace(/\/+$/, '');
const KEY = process.env.SB_KEY || '';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sha256 = (b) => crypto.createHash('sha256').update(b).digest('hex');
const encPath = (n) => n.split('/').map(encodeURIComponent).join('/');
const human = (n) => (n < 1024 ? n + ' B' : n < 1048576 ? (n / 1024).toFixed(1) + ' KB' : n < 1073741824 ? (n / 1048576).toFixed(1) + ' MB' : (n / 1073741824).toFixed(2) + ' GB');
const sqlLit = (s) => "'" + String(s).replace(/'/g, "''") + "'";
function headers(extra) {
  const h = Object.assign({ apikey: KEY }, extra || {});
  if (!KEY.startsWith('sb_')) h.Authorization = 'Bearer ' + KEY;
  return h;
}
class HttpError extends Error { constructor(status, body) { super('HTTP ' + status + ': ' + String(body).slice(0, 300)); this.status = status; this.body = String(body); } }
async function call(method, p, opts = {}) {
  let last;
  for (let attempt = 1; attempt <= 4; attempt++) {
    let res;
    try { res = await fetch(BASE + p, { method, headers: headers(opts.extra), body: opts.body }); }
    catch (e) { last = new Error('network error: ' + ((e.cause && (e.cause.code || e.cause.message)) || e.message)); await sleep(1500 * attempt); continue; }
    if (res.ok) return opts.raw ? Buffer.from(await res.arrayBuffer()) : res.json();
    last = new HttpError(res.status, await res.text().catch(() => ''));
    if (res.status !== 429 && res.status < 500) throw last;
    await sleep(1500 * attempt);
  }
  throw last;
}
function sha256File(p) {
  const h = crypto.createHash('sha256'); const fd = fs.openSync(p, 'r'); const buf = Buffer.alloc(1 << 20); let n;
  try { while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n)); } finally { fs.closeSync(fd); }
  return h.digest('hex');
}
function loadManifest() {
  const p = path.join(SNAP, 'manifest.json');
  if (!fs.existsSync(p)) throw new Error('manifest.json is missing: this folder is not a complete snapshot.');
  const m = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (m.format !== 'seaking-supabase-backup/1' || m.complete !== true) throw new Error('manifest.json is not from a finished backup-supabase.sh run.');
  return m;
}
function explainHttp(e) {
  if (e instanceof HttpError && (e.status === 401 || e.status === 403 || /Unauthorized|Invalid Compact JWS|invalid signature|Invalid API key/i.test(e.message))) return 'The key was refused (' + e.message.slice(0, 80) + '). Use the service_role key or a secret key (sb_secret_...), not the anon/publishable key.';
  return e.message;
}

async function main() {
  if (mode === 'verify') {
    const m = loadManifest(); const bad = [];
    for (const f of m.files) {
      const p = path.join(SNAP, f.name);
      if (!fs.existsSync(p)) { bad.push(f.name + ': missing'); continue; }
      if (fs.statSync(p).size !== f.bytes || sha256File(p) !== f.sha256) bad.push(f.name + ': checksum does not match');
    }
    for (const o of m.storage.objects) {
      const p = path.join(SNAP, ...o.file.split('/'));
      if (!fs.existsSync(p)) { bad.push(o.file + ': missing'); continue; }
      if (fs.statSync(p).size !== o.bytes || sha256File(p) !== o.sha256) bad.push(o.file + ': checksum does not match');
    }
    for (const need of ['roles.sql', 'schema.sql', 'data.sql']) if (!m.files.some((f) => f.name === need)) bad.push(need + ': not listed in manifest.json');
    if (bad.length) { console.error('The snapshot is damaged or was changed:\n  ' + bad.slice(0, 30).join('\n  ') + (bad.length > 30 ? '\n  ...and ' + (bad.length - 30) + ' more' : '')); process.exit(1); }
    console.log('  All ' + m.files.length + ' database files and ' + m.storage.objects.length + ' Storage files match their SHA-256 checksums.');
    return;
  }
  if (mode === 'describe') {
    const m = loadManifest(), d = m.database, s = m.storage;
    console.log('  Taken:     ' + m.created_utc + ' (UTC) from ' + (m.source.project_ref ? 'project ' + m.source.project_ref : m.source.host + ':' + m.source.port));
    console.log('  Database:  ' + d.tables_count + ' tables, ' + d.rows_total + ' rows; ' + d.cron_jobs + ' scheduled job(s); ' + d.platform_policies + ' auth/storage policies, ' + d.platform_triggers + ' auth/storage trigger(s)');
    console.log('  Storage:   ' + (s.included ? s.buckets.length + ' bucket(s), ' + s.objects_count + ' file(s), ' + human(s.bytes_total) : 'not included in this snapshot'));
    return;
  }
  if (mode === 'get') { // print one number from the manifest for the shell script
    const m = loadManifest();
    const v = { objects: m.storage.objects_count, storage_included: m.storage.included ? 1 : 0, cron_jobs: m.database.cron_jobs, policies: m.database.platform_policies, triggers: m.database.platform_triggers, tables: m.database.tables_count, rows: m.database.rows_total }[EXTRA];
    if (v === undefined) throw new Error('unknown field ' + EXTRA);
    process.stdout.write(String(v));
    return;
  }
  // Every table of your own schemas is counted; Supabase-managed tables only when they held rows
  // (some of those are not readable by the postgres user, and an empty one carries nothing).
  const MANAGED = new Set(['auth', 'storage', 'realtime', 'supabase_functions', 'cron', 'net', 'vault', 'pgsodium', 'graphql', 'extensions']);
  const checkedTables = (m) => m.database.tables.filter((t) => t.rows > 0 || !MANAGED.has(t.table.split('.')[0]));
  if (mode === 'count-sql') {
    const m = loadManifest();
    const parts = checkedTables(m).map((t) => 'SELECT ' + sqlLit(t.table) + ' AS tbl, ' + Number(t.rows) + '::bigint AS expected, (SELECT count(*) FROM ' + t.sql_name + ') AS actual');
    if (!parts.length) parts.push("SELECT 'none' AS tbl, 0::bigint AS expected, 0::bigint AS actual");
    console.log("SELECT tbl || '|' || expected || '|' || actual FROM (\n" + parts.join('\nUNION ALL\n') + '\n) AS x ORDER BY tbl;');
    return;
  }
  if (mode === 'compare-counts') {
    const m = loadManifest(); const want = checkedTables(m);
    const lines = fs.readFileSync(EXTRA, 'utf8').split(/\r?\n/).filter(Boolean).filter((l) => !l.startsWith('none|'));
    let ok = 0; const bad = [];
    for (const l of lines) { const [t, e, a] = l.split('|'); if (e === a) ok++; else bad.push(t + ': snapshot has ' + e + ' row(s), target has ' + a); }
    if (lines.length !== want.length) bad.push('checked ' + lines.length + ' tables but expected to check ' + want.length);
    const skipped = m.database.tables.length - want.length;
    console.log('  Row counts: ' + ok + ' of ' + want.length + ' tables match the snapshot exactly (' + m.database.rows_total + ' rows in the snapshot; '
      + skipped + ' empty Supabase-managed table(s) not counted).');
    if (bad.length) { console.log('  MISMATCHES:\n    ' + bad.join('\n    ')); process.exit(2); }
    return;
  }
  if (mode === 'check') {
    const b = await call('GET', '/storage/v1/bucket');
    console.log('  Storage reachable: ' + b.length + ' bucket(s) there now.');
    return;
  }
  if (mode === 'upload') {
    const m = loadManifest(); const objs = m.storage.objects; const failed = [];
    let done = 0, bytes = 0;
    const created = new Set();
    async function put(o, buf) {
      const extra = { 'x-upsert': 'true', 'Content-Type': o.mimetype || 'application/octet-stream' };
      if (o.cacheControl) extra['cache-control'] = o.cacheControl;
      return call('POST', '/storage/v1/object/' + encodeURIComponent(o.bucket) + '/' + encPath(o.name), { extra, body: buf });
    }
    for (const o of objs) {
      try {
        const buf = fs.readFileSync(path.join(SNAP, ...o.file.split('/')));
        if (sha256(buf) !== o.sha256) throw new Error('the local copy does not match its checksum');
        try { await put(o, buf); }
        catch (e) {
          // The database restore normally re-creates every bucket; this is a fallback.
          if (!(e instanceof HttpError) || !/bucket not found/i.test(e.body) || created.has(o.bucket)) throw e;
          const b = m.storage.buckets.find((x) => x.id === o.bucket) || { id: o.bucket, name: o.bucket, public: false };
          await call('POST', '/storage/v1/bucket', { extra: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: b.id, name: b.name, public: b.public, file_size_limit: b.file_size_limit, allowed_mime_types: b.allowed_mime_types }) });
          created.add(o.bucket);
          await put(o, buf);
        }
        const back = await call('GET', '/storage/v1/object/' + encodeURIComponent(o.bucket) + '/' + encPath(o.name), { raw: true });
        if (sha256(back) !== o.sha256) throw new Error('uploaded, but the copy read back is different');
        done++; bytes += buf.length;
        if (done % 25 === 0) console.log('  ...' + done + ' of ' + objs.length + ' files uploaded and checked');
      } catch (e) { failed.push(o.bucket + '/' + o.name + ': ' + explainHttp(e)); }
    }
    console.log('  Storage: ' + done + ' of ' + objs.length + ' files uploaded and read back with identical SHA-256 (' + human(bytes) + ').');
    if (failed.length) { console.log('  FAILED:\n    ' + failed.slice(0, 50).join('\n    ')); process.exit(2); }
    return;
  }
  throw new Error('unknown mode ' + mode);
}
main().catch((e) => { console.error('ERROR: ' + explainHttp(e)); process.exit(1); });
__NODE_EOF__
}

# ------------------------------------------------------------------------------------------------
# 1. Arguments, tools, and the snapshot itself
# ------------------------------------------------------------------------------------------------
STORAGE_ONLY=0
if [ "${1:-}" = "--storage-only" ]; then STORAGE_ONLY=1; shift; fi
case "${1:-}" in -h|--help) sed -n '2,23p' "$0"; exit 0 ;; esac
if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  printf 'Usage: %s [--storage-only] <snapshot-folder>\n' "$(basename "$0")" >&2
  exit 2
fi
SNAP="$(to_unix "$1")"
case "$SNAP" in /*) ;; *) SNAP="$PWD/$SNAP" ;; esac
SNAP="${SNAP%/}"
[ -d "$SNAP" ] || die "Folder not found: $1"
case "$SNAP" in *-INCOMPLETE) die "This snapshot is marked INCOMPLETE: the backup did not finish. Use another snapshot." ;; esac
[ -f "$SNAP/manifest.json" ] || die "There is no manifest.json in that folder, so it is not a complete snapshot. (Point at the folder named supabase-backup-..., not at the folder above it.)"
SNAP_M="$(to_mixed "$SNAP")"

command -v docker >/dev/null 2>&1 || die "Docker was not found. Install Docker Desktop and start it."
command -v node   >/dev/null 2>&1 || die "Node.js was not found. Install the LTS version from nodejs.org, then reopen Git Bash."
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' || die "Node.js 18 or newer is needed."
docker info >/dev/null 2>&1 || die "Docker Desktop is not running. Start it, wait until it shows 'Engine running', then try again."
WORK="$(mktemp -d)"

step "Checking the snapshot"
node_helper verify "$SNAP_M" || die "The snapshot failed its checksum test (see above). Do not restore from it; use another snapshot."
node_helper describe "$SNAP_M"
OBJECTS="$(node_helper get "$SNAP_M" objects)"
STORAGE_INCLUDED="$(node_helper get "$SNAP_M" storage_included)"
EXPECT_CRON="$(node_helper get "$SNAP_M" cron_jobs)"
EXPECT_POLICIES="$(node_helper get "$SNAP_M" policies)"
EXPECT_TRIGGERS="$(node_helper get "$SNAP_M" triggers)"
[ "$STORAGE_ONLY" = 1 ] && [ "$OBJECTS" = 0 ] && die "This snapshot has no Storage files to upload."

# ------------------------------------------------------------------------------------------------
# 2. Questions (hidden)
# ------------------------------------------------------------------------------------------------
STEP="reading your answers"
say ""
say "What you type or paste below is hidden - that is normal. Paste with a right-click or Shift+Insert."
say "Use the NEW (target) project's details, not the project the backup came from."
say ""
ask_secret "1) TARGET database connection string (Session pooler URI, with password): " DB_CONN
[ -n "$DB_CONN" ] || die "No connection string was given."
say "   received (${#DB_CONN} characters)."
parse_conn "$DB_CONN"
unset DB_CONN

SB_URL=""; SB_KEY=""
if [ "$OBJECTS" -gt 0 ] || [ "$STORAGE_ONLY" = 1 ]; then
  ask_secret "2) TARGET project URL, to upload the $OBJECTS Storage file(s) (press Enter to skip): " SB_URL
else
  say "2) (This snapshot has no Storage files, so no project URL is needed.)"
fi
if [ -n "$SB_URL" ]; then
  SB_URL="${SB_URL%/}"
  case "$SB_URL" in
    https://*|http://127.0.0.1:*|http://localhost:*) ;;
    *) die "The project URL must start with https:// (Dashboard > Project Settings > Data API > Project URL)." ;;
  esac
  if [ -n "$DB_REF" ]; then
    case "$SB_URL" in
      "https://$DB_REF.supabase.co") ;;
      https://*.supabase.co) die "The project URL belongs to a different project than the connection string (expected https://$DB_REF.supabase.co)." ;;
    esac
  fi
  say "   received."
  ask_secret "3) TARGET service_role key or secret key (sb_secret_...): " SB_KEY
  [ -n "$SB_KEY" ] || die "A key is needed to upload Storage files."
  case "$SB_KEY" in sb_publishable_*) die "That is the publishable key. Uploading needs the secret key (sb_secret_...) or the legacy service_role key." ;; esac
  say "   received (${#SB_KEY} characters)."
  step "Checking the Storage key"
  SB_URL="$SB_URL" SB_KEY="$SB_KEY" node_helper check "$SNAP_M" || die "Could not use the target project URL and key (see above)."
elif [ "$STORAGE_ONLY" = 1 ]; then
  die "--storage-only needs the target project URL and key."
elif [ "$OBJECTS" -gt 0 ]; then
  warn "Storage files will NOT be uploaded now. You can do it later with: ./restore-supabase.sh --storage-only \"<snapshot-folder>\""
fi
[ "$STORAGE_INCLUDED" = 1 ] || warn "This snapshot was taken without Storage files: the file LIST (storage.objects) is restored, but the files themselves are not in the backup."

# ------------------------------------------------------------------------------------------------
# 3. The target must be empty
# ------------------------------------------------------------------------------------------------
step "Checking the target database"
pick_psql_image
INFO="$(psql_tgt -At -c "select current_setting('server_version_num') || '|' || (select count(*) from pg_catalog.pg_tables where schemaname = 'public') || '|' || (select count(*) from auth.users) || '|' || (select count(*) from storage.buckets)" </dev/null | tr -d '\r')" \
  || die "Could not connect to the target database. Check the connection string and password (Dashboard > Database > Settings lets you reset the password)."
IFS='|' read -r TGT_VERSION TGT_TABLES TGT_USERS TGT_BUCKETS <<< "$INFO"
[[ "$TGT_VERSION" =~ ^[0-9]+$ ]] || die "Unexpected answer from the target database: $INFO"
say "  Target: PostgreSQL $TGT_VERSION at $DB_HOST:$DB_PORT - $TGT_TABLES table(s) in public, $TGT_USERS user(s), $TGT_BUCKETS bucket(s)."
if [ "$STORAGE_ONLY" != 1 ]; then
  [ "$TGT_TABLES" = 0 ] || die "The target already has $TGT_TABLES table(s) in 'public'. This script only restores into an EMPTY project and never overwrites anything. Create a new project and use its connection string."
  [ "$TGT_USERS" = 0 ] || die "The target already has $TGT_USERS sign-in user(s). This script only restores into an EMPTY project. Create a new project."
  [ "$TGT_BUCKETS" = 0 ] || die "The target already has $TGT_BUCKETS Storage bucket(s). This script only restores into an EMPTY project. Create a new project."
fi

say ""
if [ "$STORAGE_ONLY" = 1 ]; then
  say "About to upload $OBJECTS Storage file(s) into $SB_URL (existing files with the same name are replaced)."
else
  say "About to restore the snapshot above into the EMPTY database at $DB_HOST:$DB_PORT (user $DB_USER)."
fi
ans=""; IFS= read -r -p "Type RESTORE (in capitals) to continue, anything else to stop: " ans || true
[ "${ans//$'\r'/}" = "RESTORE" ] || die "Stopped at your request. Nothing was changed."

# ------------------------------------------------------------------------------------------------
# 4. Database: one transaction, all or nothing
# ------------------------------------------------------------------------------------------------
if [ "$STORAGE_ONLY" != 1 ]; then
  step "Restoring the database (one transaction: if anything fails, nothing is kept)"
  restore_stream() {
    local f
    printf '%s\n' "\\echo '  [1/6] roles'"
    cat "$SNAP/roles.sql"; printf '\n'
    printf '%s\n' "\\echo '  [2/6] structure: schemas, tables, views, functions, policies'"
    # A new Supabase project auto-grants anon/authenticated/service_role on everything the postgres
    # user creates in 'public' (default privileges). schema.sql's GRANT/REVOKE lines assume plain
    # PostgreSQL defaults, so a "REVOKE ... FROM anon" in the source would silently come back.
    # Clearing those defaults first makes every grant exactly what the source had; schema.sql
    # re-creates the source's own default privileges at its end.
    cat <<'__SQL_EOF__'
DO $restore$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT n.nspname, d.defaclobjtype::text AS objtype, a.grantee
      FROM pg_catalog.pg_default_acl d
      JOIN pg_catalog.pg_namespace n ON n.oid = d.defaclnamespace
      CROSS JOIN LATERAL pg_catalog.aclexplode(d.defaclacl) a
     WHERE d.defaclrole = current_user::text::regrole AND n.nspname = 'public'
       AND d.defaclobjtype IN ('r', 'S', 'f', 'T')
  LOOP
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I REVOKE ALL ON %s FROM %s',
      current_user, r.nspname,
      CASE r.objtype WHEN 'r' THEN 'TABLES' WHEN 'S' THEN 'SEQUENCES' WHEN 'f' THEN 'FUNCTIONS' ELSE 'TYPES' END,
      CASE WHEN r.grantee = 0 THEN 'PUBLIC' ELSE r.grantee::regrole::text END);
  END LOOP;
END
$restore$;
__SQL_EOF__
    cat "$SNAP/schema.sql"; printf '\n'
    for f in migration_history_schema.sql; do [ -f "$SNAP/$f" ] && { cat "$SNAP/$f"; printf '\n'; }; done
    printf '%s\n' "\\echo '  [3/6] policies and triggers on auth/storage tables'" "SET client_min_messages = warning;"
    [ -f "$SNAP/platform_customizations.sql" ] && { cat "$SNAP/platform_customizations.sql"; printf '\n'; }
    printf '%s\n' "\\echo '  [4/6] table data (triggers and foreign-key checks paused while loading)'"
    printf '%s\n' "SET session_replication_role = replica;"
    without_empty_copies "$SNAP/data.sql"; printf '\n'
    [ -f "$SNAP/migration_history_data.sql" ] && { without_empty_copies "$SNAP/migration_history_data.sql"; printf '\n'; }
    printf '%s\n' "SET session_replication_role = origin;" "SET client_min_messages = warning;"
    printf '%s\n' "\\echo '  [5/6] scheduled jobs'"
    [ -f "$SNAP/cron_jobs.sql" ] && { cat "$SNAP/cron_jobs.sql"; printf '\n'; }
    printf '%s\n' "\\echo '  [6/6] refreshing materialized views'"
    cat <<'__SQL_EOF__'
DO $restore$
DECLARE
  r record;
  left_over int;
  progressed boolean;
BEGIN
  LOOP
    progressed := false;
    FOR r IN SELECT schemaname, matviewname FROM pg_catalog.pg_matviews WHERE NOT ispopulated ORDER BY 1, 2 LOOP
      BEGIN
        EXECUTE format('REFRESH MATERIALIZED VIEW %I.%I', r.schemaname, r.matviewname);
        progressed := true;
      EXCEPTION WHEN object_not_in_prerequisite_state THEN
        NULL; -- it reads another materialized view that is not refreshed yet: next round
      END;
    END LOOP;
    SELECT count(*) INTO left_over FROM pg_catalog.pg_matviews WHERE NOT ispopulated;
    EXIT WHEN left_over = 0;
    IF NOT progressed THEN
      RAISE EXCEPTION 'could not refresh % materialized view(s)', left_over;
    END IF;
  END LOOP;
END
$restore$;
__SQL_EOF__
  }
  if [ "$TGT_VERSION" -lt 170000 ]; then
    # pg_dump 17 writes "SET transaction_timeout", which older servers do not know.
    restore_stream | sed -E 's/^SET transaction_timeout = 0;$/-- &/' | psql_tgt --single-transaction -o /dev/null -f - \
      || die "The database restore failed and was rolled back: the target is unchanged. The first ERROR line above says why."
  else
    restore_stream | psql_tgt --single-transaction -o /dev/null -f - \
      || die "The database restore failed and was rolled back: the target is unchanged. The first ERROR line above says why."
  fi
  DB_RESTORED=1
  say "  Database restored and committed."
fi

# ------------------------------------------------------------------------------------------------
# 5. Storage files
# ------------------------------------------------------------------------------------------------
if [ -n "$SB_URL" ] && [ "$OBJECTS" -gt 0 ]; then
  step "Uploading $OBJECTS Storage file(s) and reading each one back"
  SB_URL="$SB_URL" SB_KEY="$SB_KEY" node_helper upload "$SNAP_M" \
    || die "Some Storage files did not upload (listed above). Run: ./restore-supabase.sh --storage-only \"<snapshot-folder>\" to retry; files already there are simply replaced."
fi

# ------------------------------------------------------------------------------------------------
# 6. Compare with the manifest
# ------------------------------------------------------------------------------------------------
CHECK_FAILED=0
if [ "$STORAGE_ONLY" != 1 ]; then
  step "Comparing the restored database with the snapshot"
  node_helper count-sql "$SNAP_M" > "$WORK/count.sql"
  psql_tgt -At -f - < "$WORK/count.sql" > "$WORK/count.out" || die "Could not count the rows in the target."
  node_helper compare-counts "$SNAP_M" "$(to_mixed "$WORK/count.out")" || CHECK_FAILED=1
  CHECKS="$(psql_tgt -At -c "select (select count(*) from pg_catalog.pg_matviews where not ispopulated) || '|' || (select count(*) from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid = p.polrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace where n.nspname in ('auth','storage','realtime')) || '|' || (select count(*) from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace join pg_catalog.pg_proc p on p.oid = t.tgfoid join pg_catalog.pg_namespace pn on pn.oid = p.pronamespace where not t.tgisinternal and t.tgconstraint = 0 and n.nspname in ('auth','storage','realtime') and pn.nspname not in ('auth','storage','realtime')) || '|' || (select count(*) from pg_catalog.pg_extension where extname = 'pg_cron')" </dev/null | tr -d '\r')" \
    || die "Could not run the final checks."
  IFS='|' read -r UNPOPULATED GOT_POLICIES GOT_TRIGGERS HAS_CRON <<< "$CHECKS"
  GOT_CRON=0
  if [ "$HAS_CRON" = 1 ]; then GOT_CRON="$(psql_tgt -At -c "select count(*) from cron.job" </dev/null | tr -d '\r')" || GOT_CRON="?"; fi
  say "  Scheduled jobs: $GOT_CRON (snapshot: $EXPECT_CRON).  Auth/storage policies: $GOT_POLICIES (snapshot: $EXPECT_POLICIES).  Auth/storage triggers: $GOT_TRIGGERS (snapshot: $EXPECT_TRIGGERS).  Unrefreshed materialized views: $UNPOPULATED."
  [ "$GOT_CRON" = "$EXPECT_CRON" ] || { warn "The number of scheduled jobs differs from the snapshot."; CHECK_FAILED=1; }
  [ "$GOT_POLICIES" = "$EXPECT_POLICIES" ] || { warn "The number of auth/storage policies differs from the snapshot."; CHECK_FAILED=1; }
  [ "$GOT_TRIGGERS" = "$EXPECT_TRIGGERS" ] || { warn "The number of auth/storage triggers differs from the snapshot."; CHECK_FAILED=1; }
  [ "$UNPOPULATED" = 0 ] || { warn "$UNPOPULATED materialized view(s) are not populated."; CHECK_FAILED=1; }
fi

STORAGE_SKIPPED=0
if [ "$OBJECTS" -gt 0 ] && [ -z "$SB_URL" ]; then STORAGE_SKIPPED=1; fi

DONE=1
unset DB_PASS SB_KEY
say ""
if [ "$CHECK_FAILED" = 1 ]; then
  say "RESTORE FINISHED, BUT SOME CHECKS DID NOT MATCH (see the lines marked MISMATCHES / WARNING above)."
elif [ "$STORAGE_SKIPPED" = 1 ]; then
  say "DATABASE RESTORED - but the $OBJECTS Storage file(s) were NOT uploaded (no project URL was given)."
  say "Finish with:  ./restore-supabase.sh --storage-only \"$(to_win "$SNAP")\""
else
  say "RESTORE COMPLETE - every check matched the snapshot."
fi
if [ "$STORAGE_ONLY" != 1 ]; then
  say ""
  say "STILL TO DO BY HAND (a backup cannot carry these - README.md explains each one):"
  say "  1. Vault secrets: create each of these again in the new project (SQL Editor), with the real value:"
  VAULT_NAMES="$(grep -v '^#' "$SNAP/vault-secret-names.txt" 2>/dev/null | cut -f1 | grep -v '^$' || true)"
  if [ -n "$VAULT_NAMES" ]; then
    while IFS= read -r n; do say "       select vault.create_secret('<value>', '$n');"; done <<< "$VAULT_NAMES"
  else
    say "       (none were listed in the snapshot)"
  fi
  say "  2. Authentication settings: Site URL, redirect URLs, SMTP, email templates, sign-in providers, MFA."
  say "  3. The new project has new API keys and a new URL: update them wherever the apps use them"
  say "     (Netlify environment variables, Edge Function secrets, and any Vault secret that holds them)."
  say "  4. Edge Functions: deploy them to the new project and set their secrets again."
  say "  5. Everyone signs in again (old sessions do not carry over). Passwords still work."
fi
[ "$CHECK_FAILED" = 0 ] && [ "$STORAGE_SKIPPED" = 0 ] || exit 2
