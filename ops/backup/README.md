# Supabase backups: the runbook

Two scripts, run in Git Bash on your own computer:

- `backup-supabase.sh` makes a full copy of one Supabase project (a **snapshot**): the database, every Storage file, and a checklist with checksums.
- `restore-supabase.sh` loads a snapshot into a **new, empty** Supabase project and checks that everything arrived.

They were built for Kraken, but they work on any Supabase project.

---

## 1. What a backup protects you against

- **Data damaged or deleted by mistake.** A bug, a bad import, or a wrong click. You can go back to a copy from before it happened.
- **Losing the project itself.** An account problem, a deleted or suspended project, or a Supabase incident. Supabase's own backups live inside the project, so they would be lost with it. Your snapshot does not.
- **Needing to look at the past.** "What did this invoice look like last month?"

A snapshot is a picture of one moment. Anything that changed after it was taken is not in it.

## 2. What you already have without this tool

1. **Supabase's own daily backups (paid plans only).** Check them now: open the project in the dashboard, then **Database → Backups**.
   - If you see a list of daily backups, Supabase keeps them for you: 7 days on Pro, 14 on Team.
   - If the page says backups are not on your plan, you have none.
   - Two limits: they do **not** contain Storage files (only the list of files), and they belong to the project. Delete the project or lose the account, and they go too.
   - "Point in Time Recovery" (restore to any minute) is a paid add-on on the same page.
2. **GitHub has the code.** That includes every database migration, so the *structure* of the database can be rebuilt. It has **no data**.
3. **Netlify has every website release.** To undo a bad release: Netlify → the site → **Deploys** → pick an earlier deploy → **Publish deploy**. That fixes the website, not data.

This tool adds the one thing missing: **a complete copy of the data and files that you hold yourself.**

## 3. One-time setup

You need four programs. All are already installed on your main computer. To check, open **Git Bash** and type each line, then press Enter:

```
supabase --version
docker info
node --version
git --version
```

- **Git Bash** is the black command window that comes with Git for Windows. Start menu → "Git Bash".
- **Docker Desktop** must be *running* (whale icon in the taskbar; its window says "Engine running"). The scripts use it to run the database tools.
- **Supabase CLI** is Supabase's command-line tool. Any recent version works.
- **Node.js** is a program runner; version 18 or newer.

## 4. How to take a backup

### Step 1: collect three things from the Supabase dashboard

Open the project (for Kraken: the production project) in the dashboard.

1. **The connection string.** Click **Connect** in the top bar → **Connection string** → choose **Session pooler** → copy the line that starts with `postgresql://`.
   - It looks like `postgresql://postgres.abcd1234:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:5432/postgres`.
   - You can leave `[YOUR-PASSWORD]` in it. The script will then ask for the password on its own.
   - Use **Session pooler**, not "Transaction pooler" (port 6543, which cannot run backups) and not "Direct connection" (it needs IPv6, which most networks lack).
   - If you do not know the database password, ask before resetting it. Resetting it disconnects every tool that uses it.
2. **The project URL**, for the files. **Project Settings → Data API** → "Project URL" (`https://<something>.supabase.co`).
3. **The service key**, for the files. **Project Settings → API Keys**. Use either:
   - the **Secret key** (starts `sb_secret_`), or
   - under "Legacy API keys", the **service_role** key.
   - This key can read and change everything. Paste it only into the script. Never into email, chat or a document.

### Step 2: run the script

Open Git Bash and type (replace the last part with your backup folder):

```
cd "/c/Users/stink/Claude Projects/SEAKING-SUITE/ops/backup"
./backup-supabase.sh /d/SeaKing-Backups
```

- In Git Bash, `D:\SeaKing-Backups` is written `/d/SeaKing-Backups`. If the folder name has spaces, put it in "quotes".
- The script asks three questions. **What you paste stays invisible. That is on purpose.** To paste in Git Bash, right-click or press Shift+Insert (Ctrl+V does not work there). Then press Enter.
- To back up only the database, press Enter at question 2 and it skips the files.
- It takes a few seconds to a few minutes. At the end you see **BACKUP COMPLETE** and the folder name, for example `supabase-backup-abcd1234-20261001T090000Z`.

What the script refuses to do, on purpose:

- Save into a folder that is inside a code repository. A backup must never be uploaded to GitHub by accident.
- Overwrite an existing snapshot. Each run makes a new folder named with the time.
- Save into OneDrive, Dropbox or Google Drive, unless you type YES to confirm.

If it says **BACKUP FAILED**, read the line starting with `ERROR`. The unfinished folder is renamed `...-INCOMPLETE`. It is not a usable backup and may contain client data, so delete it. Fix the problem and run it again.

Nothing you type is shown, saved to disk, or visible to other programs. The password and key are passed to each tool only while it runs.

## 5. Where to keep backups

**A snapshot contains client personal and financial data:** names, email addresses, sign-in records, bank and invoice data, and every uploaded document. Treat it like the documents themselves.

- **Best: an encrypted external drive.** On Windows: right-click the drive in File Explorer → **Turn on BitLocker**, and keep the recovery key in your password manager.
- **Or an encrypted archive.** With 7-Zip: right-click the snapshot folder → 7-Zip → Add to archive → format **7z**, encryption **AES-256**, tick **Encrypt file names**, and use a long password from your password manager. Then delete the open folder.
- **Keep two copies in two places.** For example one drive at the office and one at home. An encrypted `.7z` file may also go to cloud storage. The open folder never should.
- **Never:** in a code repository, in an unencrypted cloud folder, or attached to an email.
- **Delete old snapshots** you no longer need (empty the Recycle Bin too).

## 6. How often

- **Every week**, and **before any big change**: a large import, a bulk data fix, or a major Kraken release.
- **Keep:** the last 4 weekly snapshots, plus one per month for 12 months.
- **Every one to two months, test a restore** (next section). A backup that has never been restored is only a hope.

## 7. How to test a restore (into a scratch project)

1. In the Supabase dashboard, create a **new project**, for example "restore-test-2026-10". Use the same region and a strong database password.
2. From that new project, collect the same three things as in section 4.
3. In Git Bash:
   ```
   cd "/c/Users/stink/Claude Projects/SEAKING-SUITE/ops/backup"
   ./restore-supabase.sh "/d/SeaKing-Backups/supabase-backup-abcd1234-20261001T090000Z"
   ```
   Point it at the snapshot folder itself (the one with `manifest.json` inside). Answer with the **scratch** project's details, then type `RESTORE` to confirm.
4. What it does:
   - checks every file against its checksum, and refuses a damaged snapshot;
   - refuses a project that is not empty, so it never overwrites anything;
   - loads the database all-or-nothing: if anything fails, the project is left untouched;
   - re-creates the scheduled jobs and uploads every file, reading each one back to check it;
   - compares the row count of every table with the snapshot.
5. **Success** is the line **RESTORE COMPLETE - every check matched the snapshot.** Look around in the scratch project's Table Editor and Storage.
6. **Delete the scratch project when you are done:** Project Settings → General → Delete project. It holds real client data.
   - Its scheduled jobs start running. Without the Vault secrets (next section) they fail harmlessly.
   - Do **not** add the real secrets to a test project.

If only the file upload failed (for example the internet dropped), finish with `./restore-supabase.sh --storage-only "<snapshot folder>"`. Files already uploaded are simply replaced.

**Restoring for real** (the project is lost) is the same procedure into a new project. Then do every step in the next section, and point the apps at the new project. Do this with a Kraken session's help.

## 8. What a backup cannot carry, and what to do about it

The restore prints this list at the end. Write down the dashboard settings now, while the project is healthy (screenshots are fine).

1. **Vault secret values.** Kraken keeps secrets in Supabase Vault: the cron secret, the Edge Functions address and key used by scheduled jobs, and each client's Plaid bank-connection token.
   - They are encrypted with a key that belongs to the project and never leaves Supabase. So they cannot be exported.
   - The snapshot lists their **names** (never values) in `vault-secret-names.txt`. In a new project, create each one again in the SQL Editor: `select vault.create_secret('<value>', '<name>');`
   - The ones that hold the old project's address or keys need the **new** project's values.
   - **Plaid:** a bank connection's token cannot be recovered from Plaid. If the old project is gone, each client has to reconnect their bank. If it still exists, a Kraken session can copy the tokens across.
2. **Dashboard-only settings.** Authentication (Site URL, redirect URLs, email templates, SMTP server and password, sign-in providers, two-factor options), custom domain, network restrictions, compute size and backup plan.
3. **New address and keys.** A new project has a new URL and new API keys. Update them in Netlify (Site → Site configuration → Environment variables), then redeploy.
4. **Edge Functions.** Their code is in GitHub; deploy it to the new project. Their secrets (Dashboard → Edge Functions → Secrets) are not in the backup; enter them again.
5. **Netlify environment variables** live only in Netlify. Keep a copy in your password manager.
6. **Sign-ins.** Everyone has to sign in again; their passwords still work. Two-factor (authenticator app) enrolments are copied, but this was not tested on a new hosted project. Be ready for users to set their authenticator app up again.
7. **Small things.** Passwords of custom database roles (Kraken has none), the history of past scheduled-job runs, and logs of outgoing web requests (pg_net).

## 9. If something goes wrong

| Message | What it means |
|---|---|
| `password authentication failed` | Wrong database password. |
| `Docker Desktop is not running` | Start Docker Desktop and wait for "Engine running". |
| `Network is unreachable` / cannot connect | You used the Direct connection string. Use **Session pooler**. |
| `The key was refused` | You pasted the anon/publishable key. Use the service_role or secret key. |
| `The target already has ... table(s)` | The target project is not empty. Create a fresh project. |
| `The snapshot failed its checksum test` | That snapshot was damaged or changed. Use another one. |
| Restore stopped with an `ERROR` line | Nothing was changed. The load is all-or-nothing. Send the ERROR line to a Kraken session. |

---

## Technical notes (for a developer)

- **Backup contents**
  - `supabase db dump` (`--role-only`; default; `--data-only --use-copy`), plus `--schema supabase_migrations` (schema and data) for the migration history.
  - `platform_customizations.sql`: RLS policies on `auth`/`storage`/`realtime` tables, plus user triggers there. The CLI excludes those schemas, so Kraken's `ara_obj_*` storage policies would otherwise be lost. Generated from the catalog with `search_path=''`.
  - `cron_jobs.sql`: `cron.job` is extension-owned, so its rows are not in `data.sql`. Each job is written as `cron.schedule_in_database(name, schedule, command, db, NULL, active)`. The user argument must be NULL because only a superuser may name one.
  - Vault secret names; Storage objects via REST (`/object/list` recursion, then download); `manifest.json` (sha256, COPY-block row counts), written last.
- **Restore details**
  - One `psql --single-transaction`, run from the CLI's Postgres image with `--network host`.
  - Before `schema.sql`, the target's `public` default privileges for `postgres` are cleared, and `schema.sql` re-creates them. Without this, Supabase's default grants would silently re-grant `anon` on objects where the source revoked it. Kraken's migrations contain 38 `REVOKE … FROM anon/public` statements, mostly on views and materialized views, which RLS does not protect.
  - Empty COPY blocks are skipped (`storage.buckets_vectors` rejects even those). Data loads with `session_replication_role = replica`, then materialized views are refreshed.
  - Storage is re-uploaded with `x-upsert` and verified by reading each file back.
- **Secrets** reach child processes only through environment variables (`PGPASSWORD`, `SB_KEY`), never in argv. The CLI's online update check is suppressed.
- **Tested 2026-09-27:** a local round trip between two throwaway CLI stacks (PG 17.6). **Not tested:**
  - against a hosted project;
  - into a PG < 17 target (a `transaction_timeout` filter is in place);
  - vector/analytics buckets;
  - more than 1,000 objects in one folder (paging is coded);
  - object names Windows cannot store (an escaping fallback is coded).
