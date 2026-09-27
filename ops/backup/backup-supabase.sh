#!/usr/bin/env bash
#
# backup-supabase.sh - save a complete, checkable copy of one Supabase project.
#
#   Usage:    ./backup-supabase.sh <output-folder>
#   Example:  ./backup-supabase.sh /d/SeaKing-Backups
#
# Run it in Git Bash. Needs Docker Desktop (running), the Supabase CLI and Node.js 18+.
# Read README.md (next to this file) before the first run.
#
# It asks for (your typing stays hidden):
#   1. the database connection string - Dashboard > Connect > "Session pooler" URI, with the password
#   2. optionally the project URL and the service_role (or secret) key, to also save Storage files
# Those answers are never shown, never written to disk, and never put on a command line
# (they reach the Supabase CLI, psql and Node only as environment variables of that one command).
#
# It creates <output-folder>/supabase-backup-<project>-<UTC time>/ holding:
#   roles.sql, schema.sql, data.sql      `supabase db dump` (--role-only / default / --data-only --use-copy)
#   migration_history_*.sql              the CLI migration history (schema supabase_migrations)
#   platform_customizations.sql          policies and triggers added to Supabase's own auth/storage/
#                                        realtime tables (schema.sql leaves these out)
#   cron_jobs.sql                        scheduled jobs (pg_cron) as cron.schedule_in_database() calls
#   vault-secret-names.txt               NAMES of Vault secrets (their values cannot be exported)
#   storage/<bucket>/<object path>       every Storage file (when a project URL and key were given)
#   manifest.json                        sizes, SHA-256 checksums, row counts; written LAST
#   README.txt                           what is inside and how to restore it
# A folder without manifest.json is not a complete backup.

set -Eeuo pipefail
umask 077

TOOL_VERSION="1.0.0"
STEP="checking the setup"
SNAP=""
WORK=""
SUCCESS=0

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
step() { STEP="$*"; printf '\n==> %s\n' "$*"; }

cleanup() {
  local rc=$?
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then rm -rf -- "$WORK"; fi
  if [ "$SUCCESS" != 1 ]; then
    if [ -n "$SNAP" ] && [ -d "$SNAP" ]; then
      if mv -- "$SNAP" "${SNAP}-INCOMPLETE" 2>/dev/null; then SNAP="${SNAP}-INCOMPLETE"; fi
      printf 'This backup did NOT finish (it stopped while: %s).\nIt is not a usable backup. It may still contain client data: delete this folder.\n' "$STEP" > "$SNAP/INCOMPLETE.txt" 2>/dev/null || true
      printf '\nBACKUP FAILED while: %s\nThe unfinished folder was renamed to:\n  %s\nIt is NOT a usable backup and may contain client data: delete it, fix the problem shown above, and run the script again.\n' "$STEP" "$SNAP" >&2
    else
      printf '\nBACKUP FAILED while: %s\nNothing was saved.\n' "$STEP" >&2
    fi
    [ "$rc" -ne 0 ] || rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT

to_unix()  { if command -v cygpath >/dev/null 2>&1; then cygpath -u -- "$1"; else printf '%s' "$1"; fi; }
to_win()   { if command -v cygpath >/dev/null 2>&1; then cygpath -w -- "$1"; else printf '%s' "$1"; fi; }
to_mixed() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -- "$1"; else printf '%s' "$1"; fi; }

# Read one answer without showing it. Strips stray carriage returns and surrounding spaces.
ask_secret() {
  local __answer=""
  if ! IFS= read -r -s -p "$1" __answer; then printf '\n' >&2; die "No answer was typed (input ended)."; fi
  printf '\n' >&2
  __answer="${__answer//$'\r'/}"
  __answer="${__answer#"${__answer%%[![:space:]]*}"}"
  __answer="${__answer%"${__answer##*[![:space:]]}"}"
  printf -v "$2" '%s' "$__answer"
}

# Undo %XX escapes (a password copied inside a URI may be percent-encoded). Result in REPLY.
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

# Split a postgresql:// connection string into parts. Sets the DB_* variables.
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
      ask_secret "   Type the database password (hidden): " DB_PASS
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

# The Supabase CLI, pinned to our private work folder (never a project folder).
cli() { ( cd "$WORK" && supabase --workdir "$WORK_WIN" "$@" ); }

# One `supabase db dump` into the snapshot. The password travels only in PGPASSWORD.
dump() {
  local file="$1"; shift
  PGPASSWORD="$DB_PASS" cli db dump --db-url "$DB_URL_NOPASS" "$@" -f "$(to_win "$SNAP/$file")" \
    || die "The Supabase CLI could not save $file (see the message above). A wrong password or connection string is the usual cause."
  [ -s "$SNAP/$file" ] || die "$file came out empty."
}

# psql from the Postgres image the CLI already uses (no psql install needed). SQL via -c or stdin.
pick_psql_image() {
  PSQL_IMAGE="$(docker image ls --format '{{.Repository}}:{{.Tag}}' 'public.ecr.aws/supabase/postgres' 2>/dev/null | grep -v '<none>' | sort -V | tail -n 1 || true)"
  if [ -z "$PSQL_IMAGE" ]; then PSQL_IMAGE="postgres:17-alpine"; say "(Docker will download the standard PostgreSQL client image once.)"; fi
}
psql_src() {
  PGPASSWORD="$DB_PASS" MSYS_NO_PATHCONV=1 docker run --rm -i --network host -e PGPASSWORD "$PSQL_IMAGE" \
    psql "$DB_URL_NOPASS" -X -q -v ON_ERROR_STOP=1 "$@"
}

# Storage download and manifest writer (Node.js). Keys arrive only through SB_URL / SB_KEY.
node_helper() {
  node - "$@" <<'__NODE_EOF__'
'use strict';
const fs = require('fs'), path = require('path'), crypto = require('crypto'), readline = require('readline');
const [mode, SNAP, WORK] = process.argv.slice(2);
const BASE = (process.env.SB_URL || '').replace(/\/+$/, '');
const KEY = process.env.SB_KEY || '';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const sha256 = (b) => crypto.createHash('sha256').update(b).digest('hex');
const encPath = (n) => n.split('/').map(encodeURIComponent).join('/');
const human = (n) => (n < 1024 ? n + ' B' : n < 1048576 ? (n / 1024).toFixed(1) + ' KB' : n < 1073741824 ? (n / 1048576).toFixed(1) + ' MB' : (n / 1073741824).toFixed(2) + ' GB');
function headers(extra) {
  const h = Object.assign({ apikey: KEY }, extra || {});
  if (!KEY.startsWith('sb_')) h.Authorization = 'Bearer ' + KEY; // legacy JWT keys; new sb_secret_ keys go in apikey only
  return h;
}
class HttpError extends Error { constructor(status, body) { super('HTTP ' + status + ': ' + String(body).slice(0, 300)); this.status = status; } }
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
async function listAll(bucket) {
  const out = [];
  async function walk(prefix) {
    for (let offset = 0; ; offset += 1000) {
      const page = await call('POST', '/storage/v1/object/list/' + encodeURIComponent(bucket), {
        extra: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }),
      });
      for (const it of page) {
        if (it.id === null || it.id === undefined) await walk(prefix + it.name + '/'); // a folder
        else out.push({ name: prefix + it.name, metadata: it.metadata || {} });
      }
      if (page.length < 1000) break;
    }
  }
  await walk('');
  return out;
}
// Object names may hold characters Windows cannot use in file names: escape them as %XX.
// The exact original name is always kept in manifest.json, so restores never rely on file names.
function safeSeg(s) {
  if (s === '') return '%00';
  if (s === '.' || s === '..') return s.replace(/\./g, '%2E');
  let t = s.replace(/[<>:"\\|?*%\x00-\x1f]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0'));
  if (/[. ]$/.test(t)) t = t.slice(0, -1) + '%' + t.charCodeAt(t.length - 1).toString(16).toUpperCase();
  if (/^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$/i.test(t)) t = '%' + t.charCodeAt(0).toString(16).toUpperCase() + t.slice(1);
  return t;
}
const used = new Set();
function writeNew(rel, buf) {
  const full = path.join(SNAP, 'storage', ...rel.split('/'));
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, buf, { flag: 'wx' }); // never overwrite
}
function placeFile(bucket, name, buf) {
  const base = [safeSeg(bucket), ...name.split('/').map(safeSeg)].join('/');
  let rel = base;
  for (let i = 2; used.has(rel.toLowerCase()); i++) { const ext = path.posix.extname(base); rel = base.slice(0, base.length - ext.length) + '~' + i + ext; }
  try { writeNew(rel, buf); }
  catch (e) { rel = '_other/' + safeSeg(bucket) + '/' + sha256(Buffer.from(name, 'utf8')).slice(0, 40) + '.bin'; writeNew(rel, buf); }
  used.add(rel.toLowerCase());
  return 'storage/' + rel;
}
function explainHttp(e) {
  if (e instanceof HttpError && (e.status === 401 || e.status === 403 || /Unauthorized|Invalid Compact JWS|invalid signature|Invalid API key/i.test(e.message))) return 'The key was refused (' + e.message.slice(0, 80) + '). Use the service_role key or a secret key (sb_secret_...), not the anon/publishable key.';
  return e.message;
}
function sha256File(p) {
  const h = crypto.createHash('sha256'); const fd = fs.openSync(p, 'r'); const buf = Buffer.alloc(1 << 20); let n;
  try { while ((n = fs.readSync(fd, buf, 0, buf.length, null)) > 0) h.update(buf.subarray(0, n)); } finally { fs.closeSync(fd); }
  return h.digest('hex');
}
function unquoteName(q) { // "schema"."table" -> schema.table
  const parts = []; let i = 0;
  while (i < q.length) {
    if (q[i] === '"') { let j = i + 1, s = ''; for (;;) { if (q[j] === '"' && q[j + 1] === '"') { s += '"'; j += 2; } else if (q[j] === '"') break; else s += q[j++]; } parts.push(s); i = j + 1; }
    else { let j = i; while (j < q.length && q[j] !== '.') j++; parts.push(q.slice(i, j)); i = j; }
    if (q[i] === '.') i++;
  }
  return parts.join('.');
}
async function copyCounts(file) {
  const out = []; let cur = null;
  if (!fs.existsSync(file)) return out;
  const rl = readline.createInterface({ input: fs.createReadStream(file, { encoding: 'utf8' }), crlfDelay: Infinity });
  for await (const line of rl) {
    if (cur) { if (line === '\\.') { out.push(cur); cur = null; } else cur.rows++; continue; }
    const m = /^COPY ((?:"(?:[^"]|"")+"|[^\s."]+)\.(?:"(?:[^"]|"")+"|[^\s."]+)) /.exec(line);
    if (m) cur = { table: unquoteName(m[1]), sql_name: m[1], rows: 0, file: path.basename(file) };
  }
  if (cur) throw new Error('Unterminated COPY block for ' + cur.table + ' in ' + path.basename(file));
  return out;
}
const countLines = (file, re) => (fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter((l) => re.test(l)).length : 0);

async function main() {
  if (mode === 'check') {
    const b = await call('GET', '/storage/v1/bucket');
    console.log('  Storage reachable: ' + b.length + ' bucket(s).');
    return;
  }
  if (mode === 'storage') {
    const buckets = (await call('GET', '/storage/v1/bucket')).sort((a, b) => a.id.localeCompare(b.id));
    fs.mkdirSync(path.join(SNAP, 'storage'), { recursive: true });
    const outBuckets = [], objects = [];
    for (const b of buckets) {
      const list = await listAll(b.id);
      let bytes = 0;
      for (const it of list) {
        const buf = await call('GET', '/storage/v1/object/' + encodeURIComponent(b.id) + '/' + encPath(it.name), { raw: true });
        const file = placeFile(b.id, it.name, buf);
        objects.push({ bucket: b.id, name: it.name, file, bytes: buf.length, sha256: sha256(buf), mimetype: it.metadata.mimetype || null, cacheControl: it.metadata.cacheControl || null });
        bytes += buf.length;
        if (objects.length % 25 === 0) console.log('  ...' + objects.length + ' files so far');
      }
      outBuckets.push({ id: b.id, name: b.name, public: !!b.public, file_size_limit: b.file_size_limit ?? null, allowed_mime_types: b.allowed_mime_types ?? null, objects: list.length, bytes });
      console.log('  bucket "' + b.id + '": ' + list.length + ' file(s), ' + human(bytes));
    }
    fs.writeFileSync(path.join(WORK, 'storage-index.json'), JSON.stringify({ buckets: outBuckets, objects }));
    return;
  }
  if (mode === 'manifest') {
    const env = process.env;
    const names = ['roles.sql', 'schema.sql', 'data.sql', 'migration_history_schema.sql', 'migration_history_data.sql',
      'platform_customizations.sql', 'cron_jobs.sql', 'vault-secret-names.txt', 'README.txt'];
    const files = names.filter((n) => fs.existsSync(path.join(SNAP, n)))
      .map((n) => ({ name: n, bytes: fs.statSync(path.join(SNAP, n)).size, sha256: sha256File(path.join(SNAP, n)) }));
    const tables = [...(await copyCounts(path.join(SNAP, 'data.sql'))), ...(await copyCounts(path.join(SNAP, 'migration_history_data.sql')))];
    const idxFile = path.join(WORK, 'storage-index.json');
    const idx = fs.existsSync(idxFile) ? JSON.parse(fs.readFileSync(idxFile, 'utf8')) : null;
    const warnings = [];
    const objRows = tables.find((t) => t.table === 'storage.objects');
    if (idx && objRows && objRows.rows !== idx.objects.length) {
      warnings.push('storage.objects has ' + objRows.rows + ' row(s) in data.sql but ' + idx.objects.length + ' file(s) were downloaded: files were probably added or deleted while the backup ran.');
    }
    const manifest = {
      format: 'seaking-supabase-backup/1',
      complete: true,
      tool: { name: 'backup-supabase.sh', version: env.BK_TOOL_VERSION },
      created_utc: env.BK_CREATED_UTC,
      supabase_cli_version: env.BK_CLI_VERSION,
      psql_image: env.BK_PSQL_IMAGE,
      source: { project_ref: env.BK_REF || null, host: env.BK_HOST, port: Number(env.BK_PORT), database: env.BK_DB, user: env.BK_USER, server_version_num: Number(env.BK_SERVER_VERSION) },
      files,
      database: {
        tables_count: tables.length,
        rows_total: tables.reduce((a, t) => a + t.rows, 0),
        tables,
        cron_jobs: countLines(path.join(SNAP, 'cron_jobs.sql'), /^SELECT cron\.schedule_in_database\(/),
        platform_policies: countLines(path.join(SNAP, 'platform_customizations.sql'), /^CREATE POLICY /),
        platform_triggers: countLines(path.join(SNAP, 'platform_customizations.sql'), /^CREATE OR REPLACE TRIGGER /),
        vault_secret_names: countLines(path.join(SNAP, 'vault-secret-names.txt'), /^[^#\s]/),
      },
      storage: idx
        ? { included: true, buckets: idx.buckets, objects_count: idx.objects.length, bytes_total: idx.objects.reduce((a, o) => a + o.bytes, 0), objects: idx.objects }
        : { included: false, buckets: [], objects_count: 0, bytes_total: 0, objects: [] },
      warnings,
    };
    fs.writeFileSync(path.join(SNAP, 'manifest.json.tmp'), JSON.stringify(manifest, null, 2) + '\n');
    fs.renameSync(path.join(SNAP, 'manifest.json.tmp'), path.join(SNAP, 'manifest.json'));
    const d = manifest.database, s = manifest.storage;
    console.log('  Database:       ' + d.tables_count + ' tables, ' + d.rows_total + ' rows');
    console.log('  Storage:        ' + (s.included ? s.buckets.length + ' bucket(s), ' + s.objects_count + ' file(s), ' + human(s.bytes_total) : 'NOT included (no project URL was given)'));
    console.log('  Scheduled jobs: ' + d.cron_jobs + '    Auth/Storage policies: ' + d.platform_policies + '    Auth/Storage triggers: ' + d.platform_triggers + '    Vault secret names: ' + d.vault_secret_names);
    for (const w of warnings) console.log('  WARNING: ' + w);
    return;
  }
  throw new Error('unknown mode ' + mode);
}
main().catch((e) => { console.error('ERROR: ' + explainHttp(e)); process.exit(1); });
__NODE_EOF__
}

# ------------------------------------------------------------------------------------------------
# 1. Arguments and the output folder
# ------------------------------------------------------------------------------------------------
if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  printf 'Usage: %s <output-folder>\n   e.g. %s /d/SeaKing-Backups\n' "$(basename "$0")" "$(basename "$0")" >&2
  exit 2
fi
case "$1" in -h|--help) sed -n '2,27p' "$0"; exit 0 ;; esac

OUT="$(to_unix "$1")"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
OUT="${OUT%/}"

d="$OUT"
while :; do
  if [ -e "$d/.git" ]; then
    die "The output folder is inside a git repository ($d). Backups hold client personal and financial data and must never be where they could be committed or pushed. Choose a folder outside any repository."
  fi
  parent="$(dirname -- "$d")"; [ "$parent" = "$d" ] && break; d="$parent"
done
if command -v git >/dev/null 2>&1; then
  d="$OUT"; while [ ! -d "$d" ]; do d="$(dirname -- "$d")"; done
  if [ "$(git -C "$d" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
    die "The output folder is inside a git working tree. Choose a folder outside any repository."
  fi
fi
[ -f "$OUT/manifest.json" ] && die "That folder is itself a backup snapshot. Give the folder that should CONTAIN the new snapshot."
case "$(printf '%s' "$OUT" | tr '[:upper:]' '[:lower:]')" in
  *onedrive*|*dropbox*|*"google drive"*|*googledrive*|*"my drive"*|*icloud*|*/box/*|*"box sync"*)
    warn "The output folder looks like a cloud-synced folder: $OUT"
    warn "A backup holds client personal and financial data. Keep it on an encrypted drive or inside an encrypted archive, not in a synced folder."
    ans=""; IFS= read -r -p "Type YES to save here anyway, or just press Enter to stop: " ans || true
    [ "${ans//$'\r'/}" = "YES" ] || die "Stopped. Run again with a folder that is not synced to the cloud."
    ;;
esac

# ------------------------------------------------------------------------------------------------
# 2. Tools
# ------------------------------------------------------------------------------------------------
command -v supabase >/dev/null 2>&1 || die "The Supabase CLI was not found. See README.md, 'One-time setup'."
command -v docker   >/dev/null 2>&1 || die "Docker was not found. Install Docker Desktop and start it."
command -v node     >/dev/null 2>&1 || die "Node.js was not found. Install the LTS version from nodejs.org, then reopen Git Bash."
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 18 ? 0 : 1)' || die "Node.js 18 or newer is needed (you have $(node --version))."
docker info >/dev/null 2>&1 || die "Docker Desktop is not running. Start it, wait until it shows 'Engine running', then try again."

WORK="$(mktemp -d)"
WORK_WIN="$(to_win "$WORK")"
mkdir -p "$WORK/supabase/.temp"
# Keep the CLI from calling the internet to ask whether a newer CLI exists: this script should
# only ever talk to your project. (The dead local proxy makes that one check fail instantly;
# the version written below then satisfies the CLI's check for every later command.)
CLI_VERSION="$(cd "$WORK" && HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
  supabase --version 2>/dev/null | head -n 1 | tr -d '\r' || true)"
[ -n "$CLI_VERSION" ] || die "Could not run the Supabase CLI ('supabase --version' failed)."
printf 'v%s' "$CLI_VERSION" > "$WORK/supabase/.temp/cli-latest"

# ------------------------------------------------------------------------------------------------
# 3. Questions (hidden)
# ------------------------------------------------------------------------------------------------
STEP="reading your answers"
say ""
say "Supabase backup $TOOL_VERSION. What you type or paste below is hidden - that is normal."
say "In Git Bash, paste with a right-click or Shift+Insert, then press Enter."
say ""
ask_secret "1) Database connection string (Session pooler URI, with password): " DB_CONN
[ -n "$DB_CONN" ] || die "No connection string was given."
say "   received (${#DB_CONN} characters)."
parse_conn "$DB_CONN"
unset DB_CONN

SB_URL=""; SB_KEY=""
ask_secret "2) Project URL, to also save Storage files (press Enter to skip files): " SB_URL
if [ -n "$SB_URL" ]; then
  SB_URL="${SB_URL%/}"
  case "$SB_URL" in
    https://*|http://127.0.0.1:*|http://localhost:*) ;;
    *) die "The project URL must start with https:// (Dashboard > Project Settings > Data API > Project URL)." ;;
  esac
  if [ -n "$DB_REF" ]; then
    case "$SB_URL" in
      "https://$DB_REF.supabase.co") ;;
      https://*.supabase.co) die "The project URL belongs to a different project than the connection string (expected https://$DB_REF.supabase.co). Copy both from the same project." ;;
    esac
  fi
  say "   received."
  ask_secret "3) service_role key or secret key (sb_secret_...): " SB_KEY
  [ -n "$SB_KEY" ] || die "A key is needed to save Storage files. Run again and press Enter at question 2 if you want to skip files."
  case "$SB_KEY" in sb_publishable_*) die "That is the publishable key. Storage backup needs the secret key (sb_secret_...) or the legacy service_role key." ;; esac
  KEY_ROLE="$(SB_KEY="$SB_KEY" node -e 'try{const p=process.env.SB_KEY.split(".");if(p.length===3)process.stdout.write(JSON.parse(Buffer.from(p[1],"base64url").toString()).role||"?")}catch(e){process.stdout.write("?")}')"
  case "$KEY_ROLE" in ""|service_role) ;; anon) die "That is the anon key. Storage backup needs the service_role key or a secret key." ;; *) warn "Could not recognise the key type; trying it anyway." ;; esac
  say "   received (${#SB_KEY} characters)."
else
  warn "Storage files will NOT be backed up (no project URL given). Only the database will be saved."
fi

if [ -n "$DB_REF" ]; then LABEL="$DB_REF"
else case "$DB_HOST" in 127.0.0.1|localhost|::1) LABEL="local-$DB_PORT" ;; *) LABEL="$(printf '%s' "$DB_HOST" | tr -c 'A-Za-z0-9.-' '_')" ;; esac
fi

if [ -n "$SB_URL" ]; then
  step "Checking the Storage key"
  SB_URL="$SB_URL" SB_KEY="$SB_KEY" node_helper check "$(to_mixed "$WORK")" "$(to_mixed "$WORK")" \
    || die "Could not use the project URL and key for Storage (see above)."
fi

# ------------------------------------------------------------------------------------------------
# 4. Snapshot folder (never overwrites)
# ------------------------------------------------------------------------------------------------
STEP="creating the snapshot folder"
CREATED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p -- "$OUT" || die "Could not create the output folder $OUT."
NAME="supabase-backup-${LABEL}-${STAMP}"
if [ -e "$OUT/$NAME" ] || [ -e "$OUT/$NAME-INCOMPLETE" ]; then
  die "A snapshot called $NAME already exists. Refusing to overwrite it; wait a second and run again."
fi
mkdir -- "$OUT/$NAME" || die "Could not create $OUT/$NAME. Nothing was overwritten."
SNAP="$OUT/$NAME"
say ""
say "Saving to: $(to_win "$SNAP")"

# ------------------------------------------------------------------------------------------------
# 5. Database
# ------------------------------------------------------------------------------------------------
step "1/7 Saving database roles (this also tests the connection)"
dump roles.sql --role-only
step "2/7 Saving the database structure (tables, views, functions, policies)"
dump schema.sql
step "3/7 Saving all table data (can take a few minutes)"
dump data.sql --data-only --use-copy
step "4/7 Saving the migration history"
dump migration_history_schema.sql --schema supabase_migrations
dump migration_history_data.sql --data-only --use-copy --schema supabase_migrations

step "5/7 Saving scheduled jobs, auth/storage policies and triggers, Vault secret names"
pick_psql_image
SERVER_VERSION="$(psql_src -At -c "select current_setting('server_version_num')" </dev/null | tr -d '\r')" \
  || die "Could not query the database through Docker (psql)."
HAS_CRON="$(psql_src -At -c "select exists (select 1 from pg_catalog.pg_extension where extname = 'pg_cron')" </dev/null | tr -d '\r')" \
  || die "Could not check for scheduled jobs."
{
  printf -- '-- Scheduled jobs (pg_cron) saved by backup-supabase.sh at %s.\n' "$CREATED_UTC"
  printf -- '-- The CLI data dump does not include them. Each statement re-creates one job by name.\n'
  printf -- '-- The user argument is NULL (= the restoring user, postgres): pg_cron lets only a superuser\n'
  printf -- '-- name a user explicitly, and on Supabase nobody is superuser.\n'
  if [ "$HAS_CRON" = t ]; then
    psql_src -At </dev/null -c "select case when username <> current_user then format('-- NOTE: the next job ran as role %I; it will be re-created to run as the restoring user.', username) || E'\n' else '' end || format('SELECT cron.schedule_in_database(%L, %L, %L, %L, NULL, %L);', coalesce(jobname, 'restored-job-' || jobid), schedule, command, database, active) from cron.job order by jobid"
  else
    printf -- '-- pg_cron is not installed in the source project: there are no jobs.\n'
  fi
} > "$SNAP/cron_jobs.sql" || die "Could not save the scheduled jobs."

{
  printf -- '-- Policies and triggers on Supabase-managed tables (auth, storage, realtime), saved by\n'
  printf -- '-- backup-supabase.sh at %s. schema.sql leaves these schemas out, so without this file\n' "$CREATED_UTC"
  printf -- '-- a restore would lose e.g. who may read which Storage files. Names are fully qualified.\n'
  psql_src -At -f - <<'__SQL_EOF__'
BEGIN READ ONLY;
SET LOCAL search_path = ''; -- makes pg_get_expr/pg_get_triggerdef write fully qualified names
SELECT format(E'DROP POLICY IF EXISTS %I ON %I.%I;\nCREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
       pol.polname, n.nspname, c.relname, pol.polname, n.nspname, c.relname,
       CASE WHEN pol.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
       CASE pol.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT' WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE' ELSE 'ALL' END,
       CASE WHEN pol.polroles = '{0}'::oid[] THEN 'PUBLIC'
            ELSE (SELECT string_agg(quote_ident(r.rolname), ', ' ORDER BY r.rolname) FROM pg_catalog.pg_roles r WHERE r.oid = ANY (pol.polroles)) END,
       CASE WHEN pol.polqual IS NULL THEN '' ELSE ' USING (' || pg_catalog.pg_get_expr(pol.polqual, pol.polrelid) || ')' END,
       CASE WHEN pol.polwithcheck IS NULL THEN '' ELSE ' WITH CHECK (' || pg_catalog.pg_get_expr(pol.polwithcheck, pol.polrelid) || ')' END)
FROM pg_catalog.pg_policy pol
JOIN pg_catalog.pg_class c ON c.oid = pol.polrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('auth', 'storage', 'realtime')
ORDER BY n.nspname, c.relname, pol.polname;
-- User triggers on those tables. Supabase's own triggers call functions in its own schemas.
SELECT regexp_replace(pg_catalog.pg_get_triggerdef(t.oid), '^CREATE TRIGGER', 'CREATE OR REPLACE TRIGGER') || ';'
FROM pg_catalog.pg_trigger t
JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
JOIN pg_catalog.pg_namespace pn ON pn.oid = p.pronamespace
WHERE NOT t.tgisinternal AND t.tgconstraint = 0
  AND n.nspname IN ('auth', 'storage', 'realtime')
  AND pn.nspname NOT IN ('auth', 'storage', 'realtime')
ORDER BY n.nspname, c.relname, t.tgname;
COMMIT;
__SQL_EOF__
} > "$SNAP/platform_customizations.sql" || die "Could not save the auth/storage policies and triggers."

VAULT_OK="$(psql_src -At -c "select coalesce(has_table_privilege(to_regclass('vault.secrets'), 'SELECT'), false)" </dev/null | tr -d '\r')" || VAULT_OK=f
{
  printf '# Vault secrets that existed at %s - NAMES ONLY, never values.\n' "$CREATED_UTC"
  printf '# Their values are encrypted with a key that belongs to the project and cannot be exported.\n'
  printf '# After a restore into a NEW project each one must be created again (see README.md).\n'
  printf '# name<TAB>description<TAB>id\n'
  if [ "$VAULT_OK" = t ]; then
    psql_src -At </dev/null -c "select format(E'%s\t%s\t%s', name, coalesce(description, ''), id) from vault.secrets order by name"
  else
    printf '# (Vault is not installed, or this login may not list it.)\n'
  fi
} > "$SNAP/vault-secret-names.txt" || die "Could not list the Vault secret names."

# ------------------------------------------------------------------------------------------------
# 6. Storage files
# ------------------------------------------------------------------------------------------------
if [ -n "$SB_URL" ]; then
  step "6/7 Downloading every Storage file"
  SB_URL="$SB_URL" SB_KEY="$SB_KEY" node_helper storage "$(to_mixed "$SNAP")" "$(to_mixed "$WORK")" \
    || die "Could not download the Storage files (see above)."
else
  step "6/7 Storage files skipped (no project URL given)"
fi

# ------------------------------------------------------------------------------------------------
# 7. README.txt, then manifest.json last
# ------------------------------------------------------------------------------------------------
step "7/7 Writing README.txt and manifest.json (checksums)"
cat > "$SNAP/README.txt" <<__README_EOF__
SUPABASE BACKUP SNAPSHOT
========================
Project:  ${LABEL}
Taken:    ${CREATED_UTC} (UTC) by backup-supabase.sh ${TOOL_VERSION}, Supabase CLI ${CLI_VERSION}

THIS FOLDER CONTAINS CLIENT PERSONAL AND FINANCIAL DATA.
Keep it on an encrypted drive or inside an encrypted archive (for example a 7-Zip file with
AES-256 and a strong password). Never put it in a git repository, and never in Dropbox, OneDrive,
Google Drive or email unless it is encrypted first. Delete old snapshots you no longer need.

WHAT IS IN IT
  roles.sql                     custom database roles (without passwords)
  schema.sql                    tables, views, functions, triggers, row-level-security policies
  data.sql                      every row of every table, including sign-in users (auth) and the
                                Storage file list (storage.objects)
  migration_history_*.sql       which migrations had been applied (supabase_migrations)
  platform_customizations.sql   policies/triggers added to Supabase's own auth/storage tables
  cron_jobs.sql                 scheduled jobs (pg_cron)
  vault-secret-names.txt        the NAMES of Vault secrets (not their values)
  storage/                      a copy of every Storage file, by bucket and path
  manifest.json                 size and SHA-256 checksum of every file, row counts per table

WHAT IS NOT IN IT
  - Vault secret values (for example the Plaid access tokens and the cron secret). They are
    encrypted with the project's own key. In a new project they must be created again.
  - Dashboard-only settings: Auth settings, SMTP / email templates, redirect URLs, OAuth
    providers, API keys, custom domains, network restrictions.
  - Edge Function code and Edge Function secrets; Netlify environment variables.
  - Custom role passwords, pg_cron run history, pg_net request logs, Realtime settings.
  - Anything that changed after the time above.

HOW TO RESTORE (into a NEW, EMPTY Supabase project)
  1. Create a new project in the Supabase dashboard (same region; note its database password).
  2. In Git Bash:  ./restore-supabase.sh "<path to this folder>"
     It checks every checksum first, refuses a project that is not empty, loads the database
     in one transaction (all or nothing), re-creates scheduled jobs, re-uploads every Storage
     file, and then compares row counts and file checksums with manifest.json.
  3. Do the manual steps it prints at the end (Vault secrets, Auth settings, keys, Netlify).
  See README.md next to the scripts for the full, plain-language runbook.
__README_EOF__

BK_TOOL_VERSION="$TOOL_VERSION" BK_CREATED_UTC="$CREATED_UTC" BK_CLI_VERSION="$CLI_VERSION" BK_PSQL_IMAGE="$PSQL_IMAGE" \
BK_REF="$DB_REF" BK_HOST="$DB_HOST" BK_PORT="$DB_PORT" BK_DB="$DB_NAME" BK_USER="$DB_USER" BK_SERVER_VERSION="$SERVER_VERSION" \
  node_helper manifest "$(to_mixed "$SNAP")" "$(to_mixed "$WORK")" || die "Could not write manifest.json."

SUCCESS=1
unset DB_PASS SB_KEY
say ""
say "BACKUP COMPLETE"
say "  Folder: $(to_win "$SNAP")"
say ""
say "Next: move this folder to encrypted storage (README.md, 'Where to keep backups')."
say "It holds client personal and financial data."
