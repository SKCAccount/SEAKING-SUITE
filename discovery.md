# Sea King estate — discovery

**The master process file.** Per Derek, 2026-08-03: *"before we proceed, we need to do discovery on each of the existing projects … this is not something we can just assume and build."* This document records what was actually found, with evidence for every claim. [suite-design.md](suite-design.md) holds the decisions; this file holds the facts those decisions must be revised against — §9 lists where discovery has already contradicted the draft design.

**How this file is maintained:** every claim carries its evidence (a path, a query, a DNS record). Anything not yet verified is tagged **[UNVERIFIED]**. Anything needing Derek/Austin is tagged **[ASK]**. New findings append to the discovery log (§11) with a date. Nothing gets deleted — superseded findings get struck through with the correction beside them.

---

## 1. Estate map

Nine systems/artifacts found. Three were previously unknown to the suite conversation entirely.

| System | What it is | Code | Production | Data | Status |
|---|---|---|---|---|---|
| **Kraken** | PO-financing / AR-factoring system of record | `SKCAccount/KRAKEN`; working copy `sea-king-capital-servicing-engine` | **Netlify ×2**: `app.seakingcapital.com` (manager), `portal.seakingcapital.com` (client portal) | Supabase `ucfy…` (own project), 21 MB | **Live, early** — 3 users, 5 ledger events, 8 daily crons, production Plaid |
| **Plunder** | Event sourcing & scoring engine for BD ("find rooms dense with qualified buyers") | `SKCAccount/PLUNDER`, local `plunder/` | **GitHub Actions cron** (nightly chain + Monday digest) | `seaking` → `plunder` schema, ~3.5k rows | Live; ran 2026-08-03 10:16 UTC |
| **MANIFEST** | Derek's personal rolodex | this repo | local dev today; Vercel pending | `seaking` → `manifest` schema | Deployed 2026-08-03, empty, awaiting first entries |
| **Harpoon** | Award-triggered govcon origination agent | `SKCAccount/HARPOON`, local `harpoon/` | **Local Docker** (`harpoon-queue`, 127.0.0.1:8010) + weekly Windows task | SQLite in Docker volume | Live locally; deliberate PII containment |
| **Deepwatch** | Deterministic conditional document-assembly engine (deals) | `SKCAccount/DEEPWATCH` (pushed 2026-08-03), local `deepwatch/` | none | filesystem (`corpus/`, `deals/`, `out/`) | Active July; remote risk closed ✓ |
| **seaking** (platform) | The combined Supabase project | — | ref `oznvdznekexdgblmxwqr` | schemas: `manifest`, `plunder`, empty `public` | Live; 1 auth user; signup off |
| `seaking-accountingevent-crm` | Atomic CRM fork (React + Supabase) with inbox-scan for in-person events | `SKCAccount/seaking-event-crm` | unknown | unknown | Last commit 2026-06-26 — **[ASK]** retired? Overlaps Plunder (events) + MANIFEST (CRM) |
| `sea-king-app` | React/Vite + Supabase starter | local only, no remote found | none apparent | local config only | **[ASK]** abandoned prototype? |
| `seakingcapital-website` | Marketing site | `SKCAccount/seakingcapital-website` | **GoDaddy cPanel** (apex A 208.109.29.159) | static | Live. **DNS for the whole cookie-domain plan lives at GoDaddy** |

---

## 2. Kraken — deep findings

### 2.1 Code and repo state

- Monorepo `sea-king-command`: `apps/manager`, `apps/client-portal`, `apps/jobs` (**README stub only**), 13 packages, 166 timestamped forward-only migrations, event-sourced ledger + projections. `CLAUDE.md` (515 lines) carries non-negotiable invariants and a **"Decisions already locked"** section this suite work must defer to inside Kraken's boundary.
- **The working copy is ahead of origin**: local HEAD 2026-07-20 (*"docs(auth): switch password-reset email to the token_hash flow"*) vs origin 2026-07-17. Unpushed auth-relevant work exists. **[ASK]** push before any port work baselines the repo.
- Overnight-review harness (`overnight-review.ps1`, session logs) — same pattern exists in Plunder. These are review sessions, not runtime.

### 2.2 Auth & authorization (verified in migrations)

- Email + password; portal has self-service forgot-password (token_hash flow per the unpushed commit).
- Roles ×5: `admin_manager`, `operator`, `client` (+`investor`, `creditor` stubs). `users.id → auth.users(id)`; client ⇔ `client_id` CHECK.
- **Grant-scoping is live for every manager tier** via `user_client_access` (2026-07-17 hardening closed the last unscoped policies; client-INSERT + service-role self-grant is the one designed exception). House rule stated in that migration: *"RLS is the authority and the app layer is convenience."*
- RLS helper functions live **unqualified in `public`** — they move + get pinned `search_path` at port.

### 2.3 Production reality (read 2026-08-03 via dashboard session, read-only)

| Fact | Value | Evidence |
|---|---|---|
| Hosting | Netlify ×2: `skckraken.netlify.app` ← `app.seakingcapital.com`; `skcportal.netlify.app` ← `portal.seakingcapital.com` | DNS CNAMEs + `ucfy` auth allowlist (exactly those four hosts) |
| DB size | 21 MB | `pg_database_size` |
| Users | `admin_manager:1 operator:1 client:1` — **one real external client user exists** | `public.users` group by |
| Ledger | `ledger_events: 5` rows; `audit_log: 67` | `pg_stat_user_tables` |
| Storage | 4 buckets: `payment-uploads(31)`, `po-uploads(18)`, `invoice-uploads(10)`, `advance-request-attachments(0)` — **3 more buckets than the repo grep suggested** | `storage.buckets` join objects |
| pg_cron | 8 jobs: `daily-fee-accrual 06:00`, `projection-drift-check 07:30`, `gl-audit 07:45`, `plaid-sync 08:00`, `aged-out-warning-email 11:30`, `insurance-claim-deadlines 12:00`, `state-of-default-reminder monthly`, `weekly-digest-email Mon 12:00` | `cron.job` |
| CLI migrations applied | **166 = repo count exactly** (parity ✓) | `supabase_migrations.schema_migrations` |
| Plaid | `PLAID_ENV=production` in manager env — **live bank connections** | working-copy `.env.local` (names + this value only) |
| App email | `RESEND_API_KEY` in portal env — app-layer email is on Resend | working-copy `.env.local` names |
| Auth email (SMTP) | **NOT configured** — password resets for the real client ride Supabase built-in free-tier email **today** | `SMTP_HOST` empty in auth config |
| Signup | **OPEN** (`DISABLE_SIGNUP: false`) on a production financial realm | auth config |
| Edge functions | ~~Repo has 7 function dirs + `_shared`; platform functions endpoint returned **empty**. How the `-email` crons deliver, and whether functions are deployed at all, is **[UNVERIFIED]**~~ **Corrected 2026-08-06 from Kraken's own docs (§2.5): functions ARE deployed and live-verified repeatedly** (aged-out-warning, weekly-digest, projection-drift-check, gl-audit, plaid-sync, insurance-claim-deadlines, state-of-default-reminder). Delivery mechanism resolved: pg_cron → `invoke_edge_job(name)` → pg_net async POST with `verify_jwt` ON + an `x-cron-secret` header checked against a Vault-held secret (`cron_secret`; `get_cron_secret()` is the service-role-only mirror). Email = Resend REST via fetch. The 2026-08-03 platform-API query that returned empty was wrong or mis-scoped — re-enumerate from the dashboard at K0 | Kraken `CLAUDE.md` (2026-07-04 entries, live-verification records) |
| Secrets | Project secrets exist; names not enumerable through the tooling used (redacted) — inventory at K0 from dashboard | platform secrets endpoint |

### 2.4 Flags (found, not fixed — nothing was changed on `ucfy`)

1. **Open signup on production.** Stray signups get no `users` row → no data (deny-by-default holds), but a public financial system accepting signups is at minimum hygiene debt. **[ASK]** intentional (invite flow dependency?) or oversight — if oversight, fix on `ucfy` now, independent of any port. *(Resolved §10a: close it — deferred behind the freeze.)* **✓ Executed on `ucfy` 2026-08-07 by the Kraken workstream** — `disable_signup=true`; self-signup refused (422 `signup_disabled`), invite round-trip verified unaffected. As-built card: Kraken `CLAUDE.md` → "Supabase dashboard configuration (NOT in code)".
2. **No custom SMTP** while a real client can request password resets. Pre-existing risk, not port-introduced. *(Resolved §10a: Resend — deferred behind the freeze.)* **✓ Executed on `ucfy` 2026-08-07 by the Kraken workstream** — Resend SMTP live (`smtp.resend.com:465`, portal's send-only key, sender `Sea King Capital <no-reply@seakingcapital.com>`), auth email rate limit raised 2→30/hr (a separate setting SMTP alone does not lift — noted for K4). Same as-built card.
3. Unpushed working-copy commits (2.1). *(Resolved §10a: pushed.)*
4. `apps/jobs` is a stub — no runtime to port. *(Still true 2026-08-06: the edge functions live at `supabase/functions/`; `apps/jobs/README.md` is the subsystem doc.)*

### 2.5 Kraken context appendix (read 2026-08-06: `CLAUDE.md` full read + `ARCHITECTURE.md` §2)

The locked-decisions read the discovery tail owed. Everything here is from Kraken's own docs, which are unusually rigorous (dated decisions, per-bug pitfall log, live-verification records). Suite-relevant facts only — the full detail lives in the repo.

**Locked decisions the suite must defer to** (headline set; `CLAUDE.md` "Decisions already locked"): integer-cents money; three-part PO key; append-only `ledger_events` (trigger-enforced, even against service_role); RLS deny-by-default with *"RLS is the authority"*; **no loan vocabulary anywhere** (advance/fees/Client — never loan/interest/borrower); **balances never forgiven** (no write-off action exists; the term is banned from UI); the legal-default waterfall (2026-07-03, per the OLS Factoring/PSA docs); **batches removed entirely** (2026-07-10 teardown); every money-moving RPC serializes on a shared per-Client advisory lock; fees prospective / BB retroactive.

**Facts that change the port runbook** (fold into suite-design §9 — done 2026-08-06):

1. **Kraken spans TWO schemas now, not one.** Migration 20260704150001 moved the 10 projection objects (4 MVs + 6 views) into a non-PostgREST-exposed **`internal` schema**, with scoped SECURITY DEFINER wrapper views at the original `public` names (`is_service_request() OR client_id IN current_user_client_ids()`). `refresh_po_projections` runs with `search_path=internal,public`. The K1 transform is therefore `public → kraken` **plus** `internal → kraken_internal` (name at K1; the property that matters is non-exposure), with the wrappers' definer bodies and pinned search_paths rewritten in lockstep. Rationale recorded as pitfall #18: views bypass RLS, MVs have none — the wrapper layer IS the tenant boundary for projections.
2. **Supabase Vault is load-bearing.** Two uses: the `cron_secret` (edge-function auth; generated inside the DB, never in git) and **Plaid access tokens** (migration 20260709120017 dropped the plaintext column; `plaid_items.access_token_secret_id` points into Vault; store/get RPCs + a delete trigger). A pg_dump does not carry Vault → **K2 must migrate Vault secrets explicitly** (re-store tokens via the RPCs on the new project).
3. **The System service account** (fixed UUID `00000000-…-000000000001`; `auth.users` + `users` rows, role `operator`, status `disabled`, non-login) is how pg_cron calls guarded RPCs: SECURITY DEFINER wrappers set `request.jwt.claim.sub` to it (pitfall #17). **K2 must preserve this user at its exact UUID.**
4. **Plaid webhook is registered on the live Chase item** pointing at `app.seakingcapital.com/api/plaid-webhook` (instant sync; ES256-verified). The manager's move to `/kraken` moves that route → **webhook re-registration (`itemWebhookUpdate`) is a cutover step**; `resolvePlaidWebhookUrl` prefers `PLAID_WEBHOOK_URL` env, so it's an env change + one registration call.
5. **Auth realm config that lives only in the dashboard** — the K4 checklist, verbatim from their trap writeups: Site URL (`https://app.seakingcapital.com`) **doubles as the silent fallback for any non-allowlisted redirect** — a portal misconfiguration dumps Clients on the Manager sign-in with no error; redirect allowlist must be **one wildcard entry per origin** (`https://host/**` — bare `/auth/callback` entries do NOT match `?next=` variants, which is exactly what resets send; scheme-exact); the **Reset Password email template is customized** to the `token_hash`/OTP flow (`{{ .RedirectTo }}&token_hash={{ .TokenHash }}&type=recovery`) because the default PKCE flow dies cross-device — and the template + the apps' `?next=` are **load-bearing in both directions**; other templates stay default. **Never add localhost entries to the production realm** (anyone with the anon key could aim a live recovery token at the recipient's own machine). Post-change verification: `node docs/diagnostics/verify-auth-redirects.mjs` (~10s, probes every origin × path shape). Invites deliberately use `{{ .ConfirmationURL }}` — leave them.
6. **Dev and prod share the one `ucfy` project** — there is no separate Kraken dev project. (After the port: dev and prod share `seaking`. Same posture, bigger blast radius — worth revisiting someday, not now.)
7. **Migration lineage is mixed-format and growing**: sequential `0001…` files then timestamped `20260531…+`; 166 was the 2026-08-03 parity count, 20260806120001 has already landed. 20 documented DB pitfalls, several of which ARE the K1 transform spec: #2 (SQL functions inlined in MVs need pinned `search_path`), #3/#14 (SECURITY DEFINER + pinned path on triggers touching RLS'd tables), #1 (enum ADD VALUE solo-migration), #18 (projection-object exposure), #20 (CRLF bodies from Windows-authored migrations — `pg_get_functiondef` preserves them; normalize before splicing).
8. **Netlify's deploy gate keys on the git PUSH ACTOR**, not commit authorship — pushes must go out under the `SKCAccount` credential or they silently never deploy (three days of pushes were once blocked this way). Any suite-side deploy tooling for the shell inherits this rule.
9. **RLS helper inventory** (ARCHITECTURE.md §2): `current_user_client_ids()`, `is_manager()`, `is_admin_manager()`, `is_client_user()`, plus `is_service_request()` from the wrapper layer — all in `public` today, all move + pin at K1. Auth callback handles both PKCE (`?code=`) and OTP (`?token_hash=`) shapes in one route; invite and reset flows are documented end-to-end and unchanged by the port except for origins.

**Estate-level correction**: §1's "8 daily crons" and §2.3's cron row remain accurate as of 2026-08-03, and the cron *bodies* are now known from docs (per-job: daily-fee-accrual = in-DB RPC via System-user wrapper at 06:00 UTC; the rest invoke deployed edge functions via `invoke_edge_job`). K0 still confirms live state, but this is no longer an unknown — it's a checklist.

---

## 3. Plunder — deep findings

- **What it is** (its own README): nightly engine finding in-person events "dense with qualified buyers," scoring for relevance/accessibility/cost, review dashboard for the keep/skip decision. Active: last commit 2026-07-30 (specialty-finance sources), last run **2026-08-03 10:16 UTC**, 643 runs total, 959 events scored.
- **Architecture**: `apps/worker` (Node/tsx CLI — the nightly entrypoint), `apps/dashboard` (React/Vite review UI), `packages/{core,db,ingest,config}`. DB client pins `schema: 'plunder'` — it adopted the suite convention independently.
- **The runner is GitHub Actions cron** (README M11: "GitHub Actions cron drives the nightly chain and the Monday digest"). ~~Nightly chain: `worker run --all && worker score && worker detect`~~ **Workflow files read 2026-08-06** (`.github/workflows/nightly.yml` + `digest.yml`), exact facts:
  - **nightly**: cron `30 6 * * *` (06:30 UTC ≈ 01:30/02:30 ET), 60-min timeout, concurrency group `plunder-worker` + an in-DB advisory lock backstop. Chain: `pnpm worker migrate` → `sync-sources` (config→DB upsert, never deletes) → `run --all --due` (each source's own `scheduleCron` decides participation — the weekly Brave discovery matrix fires Sundays only) → `score` → `detect` → `runs --limit 40`. Playwright Chromium installed per run (renderer).
  - **⚠ `worker migrate` runs in CI nightly** — Plunder's migrations auto-apply from GitHub Actions on every nightly run. Its deploy runner *is* the nightly workflow. Any suite change touching `plunder.*` must land through Plunder's own migration dir or the nightly will fight it; conversely the §3.1 policy-gate migration ships by merging to Plunder's main and letting the nightly (or a manual `workflow_dispatch`) apply it.
  - **digest**: cron `0 12 * * 1` (Mon 12:00 UTC ≈ 08:00 EDT), idempotency-keyed, dry-runs harmlessly without a Resend key.
  - **Full GitHub-secrets inventory** (both workflows): `PLUNDER_DATABASE_URL` (direct Postgres to `seaking`), `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` (auto-detect prefers Anthropic when both exist — cost note in the workflow comment), `PLUNDER_EXTRACTION_PROVIDER` / `PLUNDER_SCORING_PROVIDER` / `PLUNDER_DETECT_PROVIDER` (pins), `DISCOVERY_SEARCH_PROVIDER` + `DISCOVERY_SEARCH_API_KEY` (Brave), `RESEND_API_KEY`, `DIGEST_FROM_EMAIL`, `DIGEST_TO_EMAIL`. **Consequence confirmed: GitHub Actions is a first-class credential holder for `seaking`** — and Plunder has its own Resend key (email map §8.3 updated).
- **Dashboard runs locally** (Vite dev; no deployment found) against `VITE_PLUNDER_SUPABASE_URL` + anon key.
- **Migrations**: 10, in-app tracker `plunder._migrations` (`0001_init` → `0010_factoring_abl_category`). Its CLI history is the frozen `supabase_migrations` (26 rows).

### 3.1 ⚠ The headline security finding of this discovery

Verified live on `seaking`, 2026-08-03:

- `anon`: **zero grants** on `plunder.*` — the publishable key alone reads nothing. ✓
- `authenticated`: **ALL privileges** (SELECT…TRUNCATE), and every data table's single policy is `FOR ALL TO authenticated USING (true) WITH CHECK (true)`.

**Meaning: any signed-in user of the seaking realm has full read/write on all Plunder data.** Today the realm contains exactly one user (Derek), so there is no live exposure — but the entire Kraken port plan brings staff and **external client users** into this realm. The moment the second human can sign in, Plunder is open to them.

This is the deny-by-default violation §4 of the design doc treats as the cardinal rule, present in production. It was invisible from the code review (the policies live in Plunder's migrations, applied long ago) and surfaced only by inspecting the live database — which is exactly the argument for this discovery process.

**Gate (proposed, not built): `plunder.members` + membership-checked policies must land before any second user exists in the seaking realm** — i.e., strictly before Kraken's K2. Recorded as a design-doc correction (§9).

---

## 4. Harpoon — findings

- **What it is**: "Award-triggered govcon origination agent" (its pyproject). Python. Watches government contract awards (`SAM_API_KEY` = SAM.gov) and originates outreach: search + verifier providers, **Twilio** (SID + auth token), **its own Gmail OAuth** (client id/secret/refresh token), LLM keys (`ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY`), `DOC_ENGINE_WEBHOOK_URL` ~~(→ almost certainly Deepwatch integration — **[UNVERIFIED]**)~~ **resolved 2026-08-06, see §4.1**, `ALLOW_THIRD_PARTY_PII` + `HARPOON_DRY_RUN` flags.
- **Runtime**: Docker compose. `harpoon-queue` (up 15h, healthy, restart unless-stopped) = "the always-on half: approval queue, pipeline board, lead pages, Run panel" — **bound to 127.0.0.1:8010 deliberately: "This database holds lead PII; do not expose it on the LAN."** A `harpoon-scheduler` service exists behind a compose profile and is **not running**. A Windows scheduled task **"Harpoon Warmup"** runs `python -m harpoon.cli warmup` **weekly** (last: 2026-08-03 09:30, exit 0).
- **Data**: SQLite at `/var/lib/harpoon` (Docker volume `harpoon_harpoon-db`) — not on Supabase at all. Backup story **[UNVERIFIED]**.
- **Secrets hygiene**: the Google OAuth `client_secret_*.json` in the repo dir **is gitignored** ✓; live secrets are injected via compose env.
- **Suite relevance**: no shared auth surface today (localhost UI, single operator). Future: joins the web surface eventually (§10a #7); PII posture travels with it. Docs read 2026-08-06 — see §4.1.

### 4.1 Harpoon docs pass (2026-08-06: `WORKFLOWS.md`, `apis.md`, `handoff.py`)

- **The Deepwatch webhook question, resolved three ways**: (1) `handoff.py` is the sending half — when Derek marks a lead `qualified_for_terms`, Harpoon assembles an intake packet (dossier + thread + state counters) and POSTs it to `DOC_ENGINE_WEBHOOK_URL`, then **locks the lead** (economics talk refused thereafter — "terms, disclosures, and every number live in the document engine, never here"); per-state counters increment only via the doc-engine callback. (2) **The live `.env` value is EMPTY** — the POST is skipped (`webhook_configured=false`), the lock still happens; the code stubs gracefully. (3) **Deepwatch has no receiving endpoint** — its server routes are `/api/inputs|preview|render|save-profile` only; zero `intake`/`harpoon` references in its code. **Verdict: the integration is designed on Harpoon's side, unbuilt on Deepwatch's, unwired in between.** The design intent (Deepwatch as the doc engine) is confirmed by shape, not by configuration.
- **Safety model** (WORKFLOWS.md §5 — this is the PII posture that must travel to any web mount): human gate on every send; dry-run default (`HARPOON_DRY_RUN=0` + a send tick required); compliance-as-code (lexical linter, dossier grounding, structural rules, 100% test coverage enforced); global kill switch on bounce/spam signals; permanent suppression; **PII tokenization** — DeepSeek (cost-tier drafting) never sees contact PII (tokenized out and restored post-response); reply drafting stays on Anthropic.
- **External services** (§6 + apis.md): USAspending (no key), SAM.gov Entity API, MailRook/NeverBounce verifier, optional Google CSE/SerpAPI, Anthropic, DeepSeek, Gmail API (OAuth, isolated domain), Twilio Lookup v2 (line-type only — mobile ⇒ email-only). FPDS adapter removed 2026-07-18.
- **Runtime shape** (§7): two long-lived processes over SQLite WAL — consistent with the queue container + the dormant scheduler profile.

## 5. Deepwatch — findings

- "Deterministic conditional document assembly engine" — assembles deal documents from fragments/corpus with conditional logic (FOREACH, draft gating, bounded enumeration per its build log). Renamed SENTINEL → DEEPWATCH 2026-07-12. Python, venv-bound.
- **Git repo with no remote, clean tree, local-only.** One disk failure loses the entire system. Highest-priority operational flag outside Kraken. **[ASK]**: push to `SKCAccount/DEEPWATCH`. *(Resolved §10a #4: pushed 2026-08-03.)*
- Integration hypothesis: Harpoon's `DOC_ENGINE_WEBHOOK_URL` points at it (capability letters for govcon outreach). ~~**[UNVERIFIED]**~~ **Resolved 2026-08-06 — see §4.1: intended yes, wired no.** Deepwatch has no intake endpoint; the env var is empty.
- **Docs pass (2026-08-06)**: README is one line ("Deal onboarding engine — background check, document preparation"); `BUILD_LOG.md` is the real doc — v5 engine (list inputs + FOREACH, draft gating, bounded enumeration), all spec phases 0–4 complete 2026-07-13, re-architected 2026-07-26, "engine feature-complete." Repo layout: `engine/` (incl. a **dependency-free stdlib HTTP server** serving a single-page `ui/index.html` locally), `corpus/`, `fragments/`, `assemblies/`, `profiles/`, `deals/`, `out/`, `phase0/`, tests. **It already has a local web UI** — server prints `DEEPWATCH UI -> http://host:port`. Suite mount someday = this UI behind a membership check; nothing blocks on it.

## 6. MANIFEST — reference

Fully documented in this repo ([README](../README.md)). Deployed to `seaking` 2026-08-03; forward-only; per-system ledger; fixture-sync guard; password auth. Pending: ~~Vercel~~ Netlify deploy (D15), Google OAuth app, first thirty relationships. Suite-relevant: it defined the membership pattern (`app_owners`) and the ledger convention the other systems adopt.

### 6.1 The app is built; the sign-in was never exercised on `seaking` (found 2026-08-07)

Derek: *"has manifest itself been built? I have never gotten past the login screen."* Investigated read-only; the app is **substantially built** — 22 routes (`/`, `/rolodex`, `/directory`, `/person/[id]` + new/edit, `/watchlist`, `/geography`, `/review`, `/sources`, `/sync`, `/offline`, plus capture / cron / Google-OAuth / auth API routes), 30 components, full `src/lib` (queries, actions, sync, capture, offline queue, phone, validation). Not a shell.

`npm run doctor` against `seaking` returns **Ready**: schema deployed, 96 taxonomy values seeded, 8 views queryable, owner row present, auth user present, people table empty. Two deliberate warns (Google OAuth unconfigured until after the thirty; `ANTHROPIC_API_KEY` unset — quick-capture falls back to the manual form).

**The correction.** ~~"Password sign-in works on localhost" (logged 2026-08-03)~~ — **not true of `seaking`.** Read via the admin API 2026-08-07, the sole auth user (`derek@seakingcapital.com`) shows:

| Field | Value |
|---|---|
| `created_at` | 2026-06-20T23:42:20Z |
| `email_confirmed_at` | 2026-06-20T23:42:46Z |
| `last_sign_in_at` | **2026-06-20T23:42:46Z** — 26s after creation, i.e. the confirm itself |

`last_sign_in_at` advances on password sign-in, so **no password sign-in has ever succeeded on `seaking`** — not on 2026-08-03, not since. The 2026-08-03 claim was almost certainly verified against the **local** stack: `.env.local` carries a commented-out `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321` block directly beneath the live `oznvdznekexdgblmxwqr` line, so both configurations existed and the local one was in use at some point. Lesson for the log: "works on localhost" and "works on the deployed project" are different claims about different databases, and only the second one matters here.

**Consequence:** the login screen is rejecting a password that was never set on this project. Fix is one interactive command — `npm run auth:set-password` (service-key admin call, TTY-only by design so the password never reaches argv, env, or shell history). Magic link is the alternate way in (Supabase built-in email, fine at one user). Neither is a code change; nothing about the app needed building.

## 7. The seaking platform project — reference

Ref `oznvdznekexdgblmxwqr`, named `seaking` (renamed from `plunder` 2026-08-03). Schemas `manifest` + `plunder` + empty `public`; exposed: `public, graphql_public, plunder, manifest`. Auth realm: 1 user, signup disabled, localhost callback allowlisted, new-generation API keys. Frozen `supabase_migrations` = Plunder CLI history (26). Known platform quirk: project-scoped dashboard pages render blank in Derek's Chrome; org pages fine; workaround = platform API via session.

---

## 8. Cross-cutting maps

### 8.1 Where credentials live (the real secret-sprawl inventory)

| Holder | Holds |
|---|---|
| Netlify (site env ×2) | `ucfy` URL + anon + **service_role**, Plaid production creds (manager), Resend key (portal) — **[UNVERIFIED: enumerate at K0 from Netlify UI]** |
| GitHub Actions (`SKCAccount/PLUNDER` secrets) | **direct Postgres URL to `seaking`**, DeepSeek key |
| Local `.env.local` files (this machine) | everything above in dev form, incl. production Plaid values and both projects' service keys |
| Docker compose env (harpoon) | Twilio, Gmail OAuth pair + refresh token, SAM, search/verifier, LLM keys |
| Supabase `ucfy` secrets store | present; names not yet enumerated **[UNVERIFIED]** |
| Windows Task Scheduler | none (invokes venv python only) ✓ |

### 8.2 Scheduler map (what runs unattended, where)

| Trigger | System | What |
|---|---|---|
| pg_cron on `ucfy` ×8 | Kraken | fee accrual (in-DB RPC via System user, 06:00 UTC), drift check, gl-audit, plaid-sync, notice emails, digest — the rest via `invoke_edge_job` → pg_net → deployed edge functions (§2.5) |
| (event) Plaid webhook → `app.seakingcapital.com/api/plaid-webhook` | Kraken | instant transaction sync on bank activity; nightly job is the backstop (§2.5 #4) |
| GitHub Actions cron ×2 | Plunder | nightly 06:30 UTC (incl. `worker migrate` — CI auto-applies migrations!) + digest Mon 12:00 UTC (§3) |
| Windows Task "Harpoon Warmup" weekly | Harpoon | `harpoon.cli warmup` |
| (dormant compose profile) | Harpoon | `harpoon-scheduler` |
| ~~(pending) Vercel cron~~ **(pending) Netlify scheduled functions** per D15 | MANIFEST | gmail hourly (:17) / gcal 4-hourly (:42) — rewritten from `vercel.json` at S2 |

### 8.3 Email map

| Path | Used by | State |
|---|---|---|
| Supabase built-in SMTP on `ucfy` | Kraken auth mail (incl. client password resets) | **free-tier limits, live today** ⚠ — and the reset template is customized (token_hash flow); must be replicated at K4 (§2.5 #5) |
| Resend (app-layer) | Kraken portal notifications + advance-request email + edge-function jobs (aged-out warnings, weekly digest, drift/audit alarms) | keys in portal env + function secrets |
| Supabase built-in on `seaking` | MANIFEST magic-link recovery | fine while single-user |
| ~~Kraken cron `-email` jobs — mechanism **[UNVERIFIED]**~~ | **Resolved (§2.5): deployed edge functions → Resend REST** | confirm live at K0 |
| Resend via Plunder's GitHub secrets | Plunder Monday digest (`DIGEST_FROM_EMAIL` → `DIGEST_TO_EMAIL`) | found 2026-08-06 in `digest.yml` |
| Harpoon Gmail OAuth | its own outreach sending | separate from everything above |

### 8.4 Domains (GoDaddy DNS, verified by resolution)

`seakingcapital.com` A→208.109.29.159 (GoDaddy site) · `www` CNAME apex · `app` → skckraken.netlify.app · `portal` → skcportal.netlify.app · `manager`/`kraken` → no records. MANIFEST's future subdomain: **[ASK]** (`manifest.` proposed). *Superseded by the one-origin pivot (§10a #9): no per-tool subdomain is needed; tools mount under paths on `app.`.*

### 8.5 Mount constraints for the one-origin shell (found 2026-08-06)

The pivot to one origin makes several previously-irrelevant app details load-bearing. Found by reading the repos directly:

| Constraint | Evidence | Why it matters under one origin |
|---|---|---|
| **`@supabase/ssr` version split** — Kraken `^0.5.2` (manager, client-portal, `packages/auth`), MANIFEST `^0.7.0` | the four `package.json` files | Every app on `app.seakingcapital.com` talks to the same project ref, so they all read and write **the same cookie name**. That shared cookie is exactly what makes sign-in-once work — and it means two versions with different cookie chunking/encoding behavior would be fighting over one jar. Pin one version suite-wide, or centralize the client in a shared package. **Must be tested, not assumed.** |
| **Neither app sets `basePath`** | `manifest/next.config.ts`, `apps/manager/next.config.ts` | Every mounted tool needs `basePath` + `assetPrefix` before it can live under a path. Kraken's manager is today *at* `app.seakingcapital.com`; mounting it at `/kraken` is a URL change for a live app with real users. |
| **MANIFEST is a root-scoped PWA** — `manifest.webmanifest` has `start_url: "/"`, `scope: "/"`; `/sw.js` registered from `src/lib/offline-queue.ts:130`; `next.config.ts` sends `Service-Worker-Allowed: /` | those three files | A service worker scoped to `/` claims **the whole origin** — MANIFEST's would intercept `/kraken/*`. At a path mount, all of it re-scopes to `/manifest/`: SW path, SW scope header, `start_url`, `scope`, both shortcut URLs (`/?capture=1`, `/watchlist`), icon paths. All config, no architecture — but Derek re-installs the phone PWA after the move. |
| **MANIFEST sends `X-Frame-Options: DENY`** | `manifest/next.config.ts` | The shell must route by path, not embed tools in iframes. (Correct anyway; this forecloses the wrong design.) |
| Next versions differ — Kraken `^15.5.20`, MANIFEST `^15.5.4` | same `package.json` files | Not blocking: multi-zone tolerates version skew between zones. Noted so nobody assumes lockstep. |

---

## 9. Corrections this discovery forces on suite-design.md

**Status: APPLIED 2026-08-06** in the design doc's one-origin revision. This section stays as the record of what the draft got wrong and what corrected it. Recorded here first so the doc and the facts never silently diverge:

1. **§8 Hosting table is wrong**: manager lives at `app.` (not `manager.`), both Kraken apps are **Netlify** (not unknown/Vercel). Cutover = Netlify env swap; allowlist must add the two Netlify hostnames on `seaking`.
2. **New hard gate before K2**: Plunder membership + real policies (§3.1). The current design doc treats Plunder authorization as "arrives with its first UI" — discovery shows it must arrive **before Kraken's users do**.
3. **K-runbook additions**: 4 storage buckets (not 1); pg_cron jobs are 8 with exact schedules to re-create; Plaid is production (key rotation/cutover choreography needed); email-delivery mechanism resolution; secrets enumeration from Netlify + Supabase dashboards.
4. **§3.2 SMTP**: not just a K4 gate — it is a live deficiency on `ucfy` today; candidate for immediate fix independent of the port.
5. **Signup open on `ucfy`** production realm — resolve intent, likely close now.
6. **Estate is bigger than the doc knew**: Harpoon (local, PII-deliberate, Twilio/Gmail/SAM), Deepwatch (un-remoted!), the CRM experiment, `sea-king-app`, the GoDaddy-hosted site (where DNS lives). The design doc's §1.4 "unknown" sections get real content.
7. **GitHub Actions as credential holder** for `seaking` joins the key-management story (§5.3).

## 10. Consolidated [ASK] list for Derek (and Austin)

1. §3.1 Plunder policy gate — agree it blocks any second realm user? (Recommended: yes, hard gate.)
2. `ucfy` open signup — intentional or close it now?
3. Custom SMTP on `ucfy` now (Resend is already in the family) — proceed ahead of any port?
4. Deepwatch: push to a private `SKCAccount` remote this week? (One-command fix to a single-point-of-failure.)
5. Kraken working copy's unpushed commits — push?
6. `seaking-accountingevent-crm` and `sea-king-app` — retired? If yes, archive the repos and note it here; if no, they join the suite inventory properly.
7. Harpoon's future re: shared sign-in — does its queue UI stay localhost-forever (fine), or eventually join the suite's web surface?
8. Netlify account: who owns it, and can I get read access to enumerate both sites' env vars at K0?
9. MANIFEST subdomain choice (`manifest.seakingcapital.com`?) — needed for the Vercel deploy + GoDaddy DNS entry.
10. Austin's review of this file + the design doc.

## 10a. Decisions received (2026-08-03, Derek) — and the standing freeze

**⛔ Standing constraint, effective immediately: production Kraken is frozen.** No changes to the Netlify sites or to the `ucfy` Supabase project until Derek lifts this. Two already-approved fixes are therefore **deferred, not done**: closing signup on `ucfy` (#2) and custom SMTP on `ucfy` (#3 — Resend, `no-reply@seakingcapital.com`). Both execute at freeze-lift or as an early port step. (I was mid-flight on both when the freeze landed; nothing was touched.)

> **Update 2026-08-07: both fixes are EXECUTED on `ucfy` — by the Kraken workstream, not this one.** Derek moved them to the Kraken session via `krakenauthhandoff.md` so the suite side stayed hands-off production. Signup closed (refusal + invite round-trip verified), Resend SMTP live (`no-reply@seakingcapital.com`, rate limit 2→30/hr), redirect probe 12/12 before and after. The as-built configuration — written as the K4 rebuild card — is Kraken `CLAUDE.md` → "Supabase dashboard configuration (NOT in code)"; the port note is Kraken `docs/BACKLOG.md` → "For the `seaking` port".

> **Scope clarified 2026-08-06 (Derek).** The freeze is **suite-side**. It binds suite sessions — this workstream makes no changes to the Netlify sites or `ucfy`, and does not execute the two queued fixes — and it does **not** restrict Kraken's own product development, which continues on its normal cadence. The clarification was prompted by evidence that the literal wording and the practice had diverged: seven commits landed in the Kraken working copy on 2026-08-06 (`6a1fe51`…`c076837`), including `c4a547f` *"retrigger Netlify deploy after Pro upgrade"* — a production deploy — and migration `20260806120001_auto_parity_txn_ref_tiebreak.sql`. Kraken's own `CLAUDE.md` carries no mention of the freeze, and that repo's established norm runs migrations autonomously. So: two workstreams, one production system, one of them (this one) hands-off. The two approved `ucfy` fixes stay queued and are **not** suite work to execute unilaterally.

**Decision, 2026-08-06 (Derek): build order.** In his words: build the consolidated suite **in parallel** while he continues to debug Kraken on the side; when the suite is fully set up **excluding Kraken**, an extended session brings Kraken in and cuts over; that is **the last task**, because Kraken stays in daily production use throughout the build and *"we cannot have that tool exist in two places — there needs to be a clean cutover."*

Consequences recorded with it:
1. The K-runbook (suite-design §9) executes as **one compressed extended session at the end**, phases consecutive, gates intact — not spread over weeks. Inside that session, data copied early gets a **final delta sync inside a brief prod write-freeze at cutover**, so the no-dual-existence constraint holds operationally, not just organizationally.
2. **The suite builds at an interim origin.** `app.seakingcapital.com` *is* the manager today; the shell cannot occupy that root until the extended session claims it. The S-track (shell, MANIFEST mount, toggles) lives on an interim host until cutover; the `app.` flip is part of the session. Interim host naming: small [OPEN], folds into the D15 decision.
3. The suite-side freeze on `ucfy`/Netlify effectively stands until that session — the session's green light and the freeze-lift are the same moment. Read-only discovery on `ucfy` (cron bodies, env enumeration with Derek) remains allowed anytime and shortens the session.

**Decision, 2026-08-06 (Derek): D15 approved as recommended.** Mount mechanism = **edge routing at the platform level** (option b — routing rules proxy `/manifest`, `/kraken`, … to independent deployments; the shell serves `/` only and sits outside every tool's request path). With it, the travelling sub-decisions: **platform = Netlify** (MANIFEST's two Vercel crons become Netlify scheduled functions at S2), and the S-track builds at an **interim origin** on a Netlify subdomain (exact name chosen at S1; a `suite.seakingcapital.com` CNAME is optional polish). D15 closes; the S-track is unblocked. Same message, Derek: continue discovery, including reading where Kraken's schema sits today — repo-level understanding now, even though the port itself stays last.

The §10 answers:

1. **Plunder gate: yes** — and generalized: account setup becomes per-system yes/no toggles ("Kraken access? Plunder access? …"), admin-driven; unpermissioned tools don't even appear in the main dash. Toggles = membership rows; the "main dash" implies a **suite shell/launcher** (see #9).
2. **Signup: never, anywhere.** Accounts exist only when an admin creates them. (~~Execution on `ucfy` deferred per the freeze~~ — executed on `ucfy` 2026-08-07 by the Kraken workstream; already true on `seaking`.)
3. **SMTP: approved** — Resend, portal's key, `no-reply@seakingcapital.com`. (~~Deferred per the freeze~~ — executed on `ucfy` 2026-08-07 by the Kraken workstream.)
4. **Deepwatch: DONE** — pushed to `SKCAccount/DEEPWATCH` (remote's auto-init README merged, history preserved). Single-machine risk closed.
5. **Kraken working copy: DONE** — both docs-only commits pushed (`25faf73..1c344d1`).
6. **Experiments: graveyard**, both (`seaking-accountingevent-crm`, `sea-king-app`). Estate map updated; archiving the CRM repo on GitHub is optional cleanup.
7. **Harpoon: eventually web** — joins the suite surface someday; PII posture travels with it.
8. **Netlify at K0 via session: fine** (unchanged by the freeze — K0 is read-only and comes later).
9. **Architecture pivot: one origin, not many subdomains.** `app.seakingcapital.com` becomes the *suite* — sign in once at a shell/launcher showing exactly the tools you're permissioned for; Kraken, MANIFEST, Plunder, Harpoon, Deepwatch live under it. Supersedes the design doc's cookie-domain-widening plan (§3.3) and hosting table (§8): same-origin needs no domain cookie at all — simpler and safer. Realization shape (proposed): multi-zone — each tool stays its own deployable app mounted under a path (`/kraken`, `/manifest`, …), shell at the root owning the launcher + the toggle-based account admin. Open interim question: MANIFEST needs a phone-reachable URL before any shell exists (below).
10. **MANIFEST is the only per-user system** — everything else is shared-with-permissions. Understood and unambiguous; it matches D8 exactly.

**Opened and resolved the same day:**
- (a) Interim MANIFEST URL: **wait.** No deploy until the shell/URL picture settles; the thirty relationships can be entered against localhost in the meantime.
- (b) Client portal: **confirmed** — stays at `portal.seakingcapital.com`, permanently outside the shell. External clients never see the launcher.
- (c) Suite docs' home: **`SKCAccount/SEAKING-SUITE`, created by Derek.** `discovery.md` and `suite-design.md` live there now (this repo keeps a pointer in `docs/`). Future sessions open at the `Claude Projects` root, oriented by a root `CLAUDE.md` and launched with the suite repo's `START.md` prompt.

## 11. Discovery log

- **2026-08-03 (this session)** — Local estate sweep (`Claude Projects` dir, Docker, Task Scheduler, DNS). Identified all nine systems; found Plunder/Harpoon/Deepwatch code local; identified Kraken working copy (ahead of origin). Read Kraken auth stack + hardening migration; corrected two prior beliefs (grant-scoping is live; roles are five). Read `ucfy` production read-only via dashboard session: DB size/users/crons/buckets/migration parity/auth config; found open signup + missing SMTP; functions-deploy question opened. Read `seaking` live: Plunder migrations, run recency, **RLS policy audit → §3.1 finding**. Nothing was modified on either project during discovery.

- **2026-08-03, later** — Decision round recorded (§10a): **production-Kraken freeze in force** — the two approved `ucfy` fixes were halted mid-flight, nothing touched, both deferred. Executed outside the freeze: Deepwatch pushed to `SKCAccount/DEEPWATCH` (auto-init README merged), Kraken working-copy docs commits pushed, experiments marked graveyard. Same evening: the three open items resolved (wait / portal separate / suite repo go); docs relocated to `SKCAccount/SEAKING-SUITE`; root `CLAUDE.md` and `START.md` created for sessions opening at the `Claude Projects` root; MANIFEST's session commits pushed to `SKCAccount/MANIFEST`.

- **2026-08-06** — Session opened on the suite; three days since the last entry. Two things happened.

  **(1) The freeze's scope was clarified** (§10a, boxed note). Evidence of divergence between the wording and the practice: seven Kraken commits on 2026-08-06 including a production Netlify deploy (`c4a547f`) and a new migration (`20260806120001`). Derek's ruling: the freeze is suite-side — it binds this workstream, not Kraken's product development. The two queued `ucfy` fixes stay queued; suite work does not execute them. Nothing was touched on `ucfy` or Netlify this session.

  **(2) Mount-constraint discovery for the one-origin shell** → new §8.5. Read the four `package.json` files, both `next.config.ts` files, `manifest.webmanifest`, and MANIFEST's SW registration. Findings: a `@supabase/ssr` version split across the estate (Kraken `^0.5.2` / MANIFEST `^0.7.0`) that lands on a **shared cookie jar** under one origin; no `basePath` set anywhere; MANIFEST is a root-scoped PWA whose service worker would claim the whole origin. None of these are blockers — all are config — but all were invisible until the pivot made paths load-bearing, and none were in the design doc.

  **Then: `suite-design.md` fully revised for the one-origin model** — banner closed, §10a folded in, and the seven corrections in §9 below applied to the design doc. §9 stays as the record of what the draft got wrong and why; it is now *applied*, not *pending*.

  **(3) Mid-session, Derek added the build-order decision** (§10a above): suite built in parallel excluding Kraken; Kraken port is the last task, one extended session, clean cutover, no dual existence. Folded into the design doc (D13 decided in shape; §9 preamble; §11 restructured into the S-track and the K-finale; interim-origin consequence stated).

- **2026-08-06, later (same session)** — **D15 decided** (§10a): edge routing on Netlify, shell out of every tool's request path, interim origin on a Netlify subdomain; S-track unblocked. Then the five outstanding repo discovery passes, all executed:

  **Kraken** (`CLAUDE.md` full read + `ARCHITECTURE.md` §2) → **new §2.5 appendix.** Headlines: Kraken spans `public` + a non-exposed **`internal` schema** (projection wrappers = the tenant boundary); **Vault holds the cron secret and Plaid access tokens** (a dump won't carry them — K2 migrates explicitly); a fixed-UUID **System service account** underpins every pg_cron job; the **Plaid webhook** is registered against `app.seakingcapital.com` (re-register at cutover); the auth realm's dashboard config (Site-URL fallback trap, wildcard-per-origin allowlist, customized token_hash reset template, no-localhost rule) is documented from their own burn history and becomes the K4 checklist; **edge functions ARE deployed** — the 2026-08-03 "platform endpoint empty" finding was wrong and is struck through in §2.3; dev and prod share `ucfy`; 20 DB pitfalls, several being the K1 transform spec. Design doc updated the same hour (K1/K2/K3/K4 additions).

  **Plunder** (both workflow files) → §3 rewritten with exact crons, the full 11-name secret inventory, and the sleeper fact: **`worker migrate` runs in the nightly CI** — Plunder's deploy runner is GitHub Actions itself, so the §3.1 policy-gate migration ships by merge + nightly (or manual dispatch).

  **Harpoon** (docs + `handoff.py` + live `.env`) → new §4.1. The Deepwatch webhook: **designed (sending half built, lead-locking semantics), unwired (env empty), unbuilt on the receiving side.** Safety/PII model recorded — it is the posture any future web mount must preserve.

  **Deepwatch** (README, BUILD_LOG, `engine/server.py`) → §5 updated: engine feature-complete (v5), **already has a local single-page web UI** on a stdlib server; no intake endpoint.

  Cross-cutting maps (§8.2, §8.3) updated: Plaid webhook row, Plunder's Resend, MANIFEST's crons → Netlify scheduled functions per D15.

- **2026-08-07, decisions** — **D14 decided: option (a)** — universal grant-scoping stays; "admin sees all" is maintained by auto-granting designated partners/admins on client creation, not by an unscoped tier. Rationale in suite-design §5.5: the posture has been arrived at twice independently (the 2026-07-17 write-side hardening, then the 2026-08-06 `clients_write` split that made admin visibility grant-driven), and option (b) would have unwound both. Implementation lands at the K-session.

  **The two queued `ucfy` fixes move to the Kraken workstream.** Derek, this session: he will address closing signup and custom SMTP in a Kraken-specific session so suite work stays hands-off production. Launch prompt written to [`kraken-auth-handoff.md`](kraken-auth-handoff.md) — built around the auth traps in Kraken's own docs (Site-URL silent fallback, wildcard-per-origin allowlist, the token_hash reset template and its load-bearing coupling to the apps' `?next=`, the no-localhost rule, `verify-auth-redirects.mjs`), with a downstream checklist (signUp call sites, invite flow independence from `DISABLE_SIGNUP`, Resend domain/key choice, Supabase's *separate* auth email rate limit), SMTP-before-signup ordering with a cross-device gate, and a mandate to update the docs in the same commit and delete what the changes falsify. It also instructs that session to record the final configuration as something K4 can rebuild from. **These two items are no longer suite-side work** — §10a's "deferred" status resolves to "handed off," and the suite does not execute them.

- **2026-08-07, fourth round — two prompt refinements.** (1) The per-tool prompt now carries an explicit **purpose-statement template derived from Kraken's own** "What this app is" — six moves, quoted in full as the worked example, with the observation that the load-bearing sentence is *"It replaces Excel"*: naming what a tool replaces implies the condition under which it is succeeding. Also flags Kraken's adjacent "Terminology conventions" table as the pattern for any tool whose vocabulary encodes a legal or compliance reality (Harpoon's pre-offer language rules being the obvious case). (2) **Measured Kraken's `CLAUDE.md` composition**: 278,604 bytes / 533 lines, of which "What's shipped" (lines 150–340) is **200,843 bytes — 72%**, ~50–60k tokens loaded into every session and growing with every arc. New [`kraken-changelog-split.md`](kraken-changelog-split.md) handles the split. Its central point, and the reason it is not a five-minute task: **the changelog is not inert** — locked decisions, lockstep invariants, pitfall causes, "NOT yet verified" items, and records of deliberate dev data live inside those entries, often nowhere else. A straight move would degrade every future session; the prompt front-loads a four-bucket extraction (durable → permanent sections; live-state-disguised-as-history → BACKLOG and a dev-data section; genuine history → `CHANGELOG.md`; superseded → history, with a check that nothing permanent still asserts it) and a verification phase that proves nothing was lost. It also forbids the "keep the last N entries" pattern, which silently regrows the problem, in favor of a *state* section plus a pointer, and adds a maintenance rule so new work lands in the changelog by default.

- **2026-08-07, third round — the context gap across the estate.** Derek observed that Plunder and Harpoon sessions "often miss the point of an update, or make changes that only halfway address the root issue," attributing part of it to his own short prompts and an incomplete picture of what each finished tool looks like. He asked whether to rebuild those tools fresh using the current versions as reference, or to run review sessions and bulk up repo context.

  **Measured, rather than assumed:** `CLAUDE.md` exists in **Kraken only** (278 KB). Plunder, Harpoon, Deepwatch and MANIFEST have **none** — every session in those four starts with no purpose statement, no locked decisions, no working agreement, and no instruction to ask rather than assume. That is a structural difference, not a documentation-effort difference, and it explains much of the reported behavior: with nothing stating what a tool is *for*, an ambiguous short prompt has no goal to be resolved against, so the literal reading is the only reading available.

  **Recommendation given: do not rebuild.** Kraken's rigor is scar tissue accumulated by operating a system under real use — its pitfall log was written by hitting bugs, not by building. A rewrite resets that to zero and buys a fresh crop of unknown bugs, while discarding working software (Plunder ran last night; Harpoon holds live lead PII; Deepwatch is feature-complete; MANIFEST is deployed). Nor a big-bang documentation project: a context file written from a cold read of the code mostly restates the code. Instead, one right-sized session per tool capturing only what is *not* derivable from source — purpose, locked decisions, honest state, root-caused pitfalls mined from git history, and a working agreement.

  Prompt written to [`tool-context-prompt.md`](tool-context-prompt.md), run once per repo. Its design turns on one point: Derek cannot specify the finished vision, so the session **drafts it from evidence and interviews him to correct it** — reacting to a concrete proposal is where he is sharpest, and authoring from a blank page is not. It also writes the anti-half-fix discipline *into* each `CLAUDE.md` as a standing agreement (restate the outcome before implementing; name the root cause; distinguish verified from written; end each session proposing ranked next steps), caps the file at 200–400 lines with an explicit warning against reproducing Kraken's 278 KB (over half of which is changelog belonging in git), and requires **[UNVERIFIED]** tags rather than confident guesses — a plausible-but-fabricated context file being worse than none. Suggested order: MANIFEST (cheap pilot) → Plunder → Harpoon → Deepwatch. Derek's own calibration, recorded: modest improvement expected; real progress comes from using the tools, much of it after the suite launches.

- **2026-08-07, second round** — Three more answers from Derek, all recorded in suite-design §13: **client comms = email from Derek** (one notice before cutover, one after; no portal banner — the portal keeps its own origin, so the only Client-visible effect is a single re-login); **Austin does not need to review** the design before build — with the consequence noted that he was also the expected trigger for §7's gate, so nothing now announces a second realm user in advance and §7 must simply be closed before the S-track creates any second account; **Netlify access comes later** (read-only, wanted before K0 to shorten the K-session, blocking nothing until then). Remaining open: the soak window only. Also added a shorthand glossary to the suite README — `ucfy`, `seaking`, soak, S-track/K-session — after the jargon proved opaque in conversation.

- **2026-08-07** — Derek asked whether MANIFEST itself was built ("I have never gotten past the login screen"). Investigated read-only → **new §6.1**. The app is built (22 routes, 30 components, full lib); `doctor` says Ready against `seaking`. The blocker is auth, and it produced a **correction to a 2026-08-03 claim**: `last_sign_in_at` on the sole auth user is 2026-06-20 (26 seconds after creation — the email confirm), so *password sign-in has never succeeded on `seaking`*; the earlier "works on localhost" note was about the local stack, whose config still sits commented-out in `.env.local`. Fix is `npm run auth:set-password`, which Derek must run himself (TTY-only by design). No code change, no schema change; nothing was written this session.

- **2026-08-12** — Derek recorded two long-horizon architecture intents in **Kraken's backlog** (`sea-king-capital-servicing-engine/docs/BACKLOG.md` §"Major arcs"), captured via structured Q&A in a Kraken session; logged here because both are SUITE-level. **Arc A — standalone accounting/banking service**: extract Plaid + every bank feed + the Expense Inbox + the GL out of Kraken into a tool that plugs into Kraken, Deepwatch, and future tools. Driver: diligence fees are collected AND earned (on receipt, per Derek) while a lead is still in Deepwatch; today's workaround creates pre-signing Kraken clients that become clutter when deals die. Decided: full banking+GL boundary; prospect financial history stays in the tool at hand-off (Kraken starts at Advance 1); multi-entity bookkeeping designed in from day one (SKC-only populated); diligence fees land in the catch-all lockbox today. Note for the suite design: Kraken's GL is a same-database projection (`rebuild_gl_journal`), so the split forces a posting-event contract — and Deepwatch has no DB, so its side is greenfield. **Arc B — Kraken facility layer for multi-deal-type LMS**: interest-only business loan first (trigger: the imminent deal signing), then amortizing loans / MCA / borrowing-base revolver; vocabulary is per-product (true-sale ≠ loan ≠ MCA — MCAs are ratio-on-advance purchases, not loans, per Derek). **Sequencing: Arc B before Arc A.** Full context lives in the Kraken entry.

**Still to examine (next discovery sessions):** `ucfy` live-state confirmation at K0 (cron rows, function list, secrets names — now a checklist §2.5 rather than an unknown) · Netlify env enumeration [needs Derek's session] · the two experiment repos' GitHub disposition (archive or not — optional cleanup) · **the cookie-jar test** (§8.5: do `@supabase/ssr` 0.5.2 and 0.7.0 interoperate on one cookie? — first experiment of S1) · Harpoon's `reviews/` + capability-letter docs when its mount design actually starts.
