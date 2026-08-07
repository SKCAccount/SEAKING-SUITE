# Sea King Suite — identity, authorization, and consolidation

**Revised 2026-08-06 for the one-origin model.** The revision-pending banner is
closed: Derek's 2026-08-03 direction (discovery.md §10a) is folded in as
decided, and the seven corrections discovery forced on the draft (discovery.md
§9) are applied. What changed from the draft, and why, is listed in Appendix B.

This is the design for running Kraken, Plunder, MANIFEST, and later Harpoon and
Deepwatch as one suite: one Supabase project, one sign-in, one front door — and
what a signed-in person can do in each tool decided by that tool's own
permissioning and nothing else.

Every claim about running systems traces to [discovery.md](discovery.md), which
holds the evidence. Statements are tagged **[LIVE]** (running today),
**[DECIDED]** (Derek has ruled; not yet built), **[PROPOSED]** (this document's
recommendation, awaiting a decision), or **[OPEN]** (genuinely undecided).
Open items are collected in §13.

---

## 0. Decision summary

| # | Decision | State |
|---|---|---|
| D1 | One Supabase project (`seaking`, ref `oznvdznekexdgblmxwqr`) hosts every system | **[LIVE]** — `manifest` + `plunder` schemas are there today |
| D2 | One schema per system; `public` stays empty of system objects | **[LIVE]** for MANIFEST and Plunder; Kraken moves at port |
| D3 | One auth realm; email + password primary, magic link as recovery | **[LIVE]** |
| D4 | **No self-signup anywhere, ever.** Accounts exist only when an admin creates them | **[DECIDED]** 2026-08-03 · **[LIVE]** on `seaking`; `ucfy` fix queued behind the freeze |
| D5 | Being signed in grants nothing anywhere: every system keeps its own membership surface, deny-by-default | **[LIVE]** in MANIFEST (`app_owners`) and Kraken (`users` + RLS); **violated in Plunder today** — see §7 |
| D6 | Role vocabularies are per-system; no global role enum, no central ACL | **[PROPOSED]** |
| D7 | **One origin.** `app.seakingcapital.com` is the suite: a shell at the root, tools mounted under paths | **[DECIDED]** 2026-08-03 — supersedes the draft's subdomain + cookie-widening plan |
| D8 | Sign-in-once comes free from same-origin cookies — no domain widening, no shared-cookie configuration | **[PROPOSED]** mechanism for D7; prerequisite in §8.5 |
| D9 | The client portal stays at `portal.seakingcapital.com`, permanently outside the shell | **[DECIDED]** 2026-08-03 |
| D10 | Account setup = per-system yes/no toggles, admin-driven; unpermissioned tools don't appear | **[DECIDED]** 2026-08-03; mechanism in §5.3 |
| D11 | MANIFEST is per-user: one instance per person, never a shared rolodex | **[DECIDED]** 2026-08-03 |
| D12 | No `supabase db push` against the combined project — per-system migration ledgers | **[LIVE]** for MANIFEST; Kraken adopts at port |
| D13 | **Kraken comes last.** The suite is fully set up excluding Kraken; then one extended session ports and cuts over — Kraken never exists in two places | **[DECIDED]** 2026-08-06 in shape; runbook detail **[PROPOSED]** §9 |
| D14 | **Universal grant-scoping stays**; "admin sees all" is maintained by auto-granting designated partners/admins on client creation | **[DECIDED]** 2026-08-07 — §5.5 option (a) as recommended |
| D15 | Tools mount via **edge routing** on **Netlify**; shell serves `/` only, outside every tool's request path; S-track at an interim Netlify origin | **[DECIDED]** 2026-08-06 — §4.5 option (b) as recommended |

---

## 1. What exists today

Nine systems. Full detail and evidence: discovery.md §1–§7.

### 1.1 The combined project — `seaking` [LIVE]

Ref `oznvdznekexdgblmxwqr`, free tier, org "Sea King Capital LLC". Schemas
`manifest` and `plunder`; `public` empty of system objects by design. Exposed:
`public, graphql_public, plunder, manifest` — `kraken` joins at port. One auth
user (Derek), signup disabled, `http://localhost:3000/auth/callback`
allowlisted. New-generation API keys (`sb_publishable_…` / `sb_secret_…`).
`supabase_migrations.schema_migrations` holds Plunder's frozen CLI history (26
rows) — the reason D12 exists.

### 1.2 Kraken — the servicing engine [LIVE, standalone, actively developed]

Production PO-financing / AR-factoring system of record. Repo
`SKCAccount/KRAKEN`; working copy `sea-king-capital-servicing-engine`. Own
Supabase project `ucfyfnwkxzryywuomool`.

- **Hosting: Netlify ×2** — `skckraken.netlify.app` ← `app.seakingcapital.com`
  (manager), `skcportal.netlify.app` ← `portal.seakingcapital.com` (portal).
  *This corrects the draft, which guessed `manager.` and unknown hosting.*
- **Stack**: pnpm monorepo; `apps/manager` (Next), `apps/client-portal` (Next),
  `apps/jobs` (README stub — no runtime to port). Forward-only migrations at
  exact repo↔production parity — 166 at the 2026-08-03 count, and growing with
  Kraken's active development (167+ as of 2026-08-06); the authoritative count
  is taken at K0, inside the session. Event-sourced ledger with materialized
  projections. Its `CLAUDE.md` carries non-negotiable invariants
  and a "decisions already locked" section — **this design defers to those
  inside Kraken's own boundary.**
- **Auth**: email + password; portal has self-service forgot-password. Five
  roles (`admin_manager`, `operator`, `client`, + `investor`/`creditor` stubs);
  `users.id → auth.users(id)`; client ⇔ `client_id` CHECK-enforced.
- **Grant-scoping is live for every manager tier** via `user_client_access`;
  the 2026-07-17 hardening closed the last unscoped policies. The house rule,
  from that migration: *"RLS is the authority and the app layer is
  convenience."* **This design adopts that rule suite-wide, including for the
  shell** (§4.3).
- **Production reality**: 3 users (one real external client), 4 storage buckets,
  8 pg_cron jobs, production Plaid credentials, Resend for app-layer email.
  Two standing deficiencies: **signup is open** and **no custom SMTP** while a
  real client can request password resets.
- **RLS helpers live unqualified in `public`** — they move into `kraken` with
  pinned `search_path` at port.
- **17+ migrations hard-qualify `public.`** — a port cannot replay under a
  different `search_path`; it needs a scripted qualification rewrite (§9 K1).
- **Deep-read additions (2026-08-06, discovery.md §2.5)**: Kraken actually spans
  **two schemas** — `public` plus a non-PostgREST-exposed `internal` schema
  holding the 10 projection objects behind scoped wrapper views (the tenant
  boundary for projections). **Supabase Vault** holds the cron secret and the
  Plaid access tokens (plaintext column dropped) — a dump does not carry Vault.
  A fixed-UUID **System service account** is how pg_cron calls guarded RPCs.
  Edge functions **are deployed** (seven, live-verified in Kraken's own docs);
  crons deliver via `invoke_edge_job` → pg_net with a Vault-held header secret.
  The **Plaid webhook** is registered on the live bank item against
  `app.seakingcapital.com/api/plaid-webhook`. Dev and prod share `ucfy`. All of
  these are runbook line-items below.

**Freeze posture (discovery.md §10a, clarified 2026-08-06):** the freeze is
suite-side. This workstream changes nothing on Netlify or `ucfy`, and does not
execute the two queued fixes. Kraken's own product development continues on its
normal cadence — seven commits landed 2026-08-06, including a production deploy.
Two workstreams, one production system, this one hands-off.

### 1.3 Plunder [LIVE — and the estate's one open door]

Nightly event-sourcing and scoring engine for BD. Repo `SKCAccount/PLUNDER`.
`apps/worker` (the nightly entrypoint), `apps/dashboard` (React/Vite, local
only), `packages/{core,db,ingest,config}`. Its DB client pins
`schema: 'plunder'` — it adopted the suite convention independently. 10
migrations tracked in `plunder._migrations`.

**The runner is GitHub Actions cron**, which means **GitHub repo secrets hold a
direct Postgres credential to `seaking`** — GitHub Actions is a credential
holder in §6.4's map.

Its authorization state is a hard gate on the entire suite. See §7.

### 1.4 MANIFEST [LIVE]

Derek's personal rolodex; deployed to `seaking` 2026-08-03, empty, password
sign-in working on localhost. Single-owner by deep design (first-person
semantics, global dedupe keys, private notes). It defined the membership pattern
(`app_owners`) and the per-system ledger convention the other systems adopt.

Phone-first, and **a real PWA** — `manifest.webmanifest` scoped to `/`, a
service worker registered at `/sw.js` claiming the whole origin, an offline
queue. That makes it the most mount-sensitive app in the estate (§8.5), and it
is also the app waiting on the shell decision (§10a(a): deploy held until the
URL picture settles). Its `vercel.json` declares two crons — gmail hourly at
:17, gcal every 4 hours at :42 — which bind it to Vercel unless rewritten
(§4.5).

### 1.5 Harpoon [LIVE, local]

Award-triggered govcon origination agent. Python, Docker compose; `harpoon-queue`
bound to **127.0.0.1:8010 deliberately** — *"This database holds lead PII; do
not expose it on the LAN."* SQLite in a Docker volume, not on Supabase at all.
A weekly Windows task runs `harpoon.cli warmup`. Holds Twilio, its own Gmail
OAuth, SAM.gov, and LLM credentials.

**[DECIDED]** it eventually joins the web surface — and its PII posture travels
with it. That posture is a design input, not an afterthought: whatever mounts
Harpoon inherits a lead-PII store. Nothing in this document blocks on it.

### 1.6 Deepwatch [LIVE, local]

Deterministic conditional document-assembly engine for deal documents (FOREACH,
draft gating, bounded enumeration). Python, venv-bound, filesystem-backed.
Remote at `SKCAccount/DEEPWATCH` since 2026-08-03 — the single-machine risk is
closed. Harpoon's `DOC_ENGINE_WEBHOOK_URL` probably points at it;
**[UNVERIFIED]**, on the discovery list.

### 1.7 The rest

`seakingcapital.com` marketing site on GoDaddy cPanel — **and GoDaddy is where
DNS for the whole estate lives**, so every hosting change routes through it.
`seaking-accountingevent-crm` and `sea-king-app`: **graveyarded** 2026-08-03.

---

## 2. Goals and non-goals

**Goals**

1. Sign in once, at one address; each tool decides what you see by its own
   permissioning.
2. External users — Kraken's clients today, investors/creditors later — live in
   the same auth realm with no possibility of reaching another system.
3. Kraken moves onto the combined project with production continuity: parallel
   build, verified cutover, rollback available at every step until retirement.
4. Conventions that let five systems share one database without stepping on each
   other: schemas, ledgers, naming, secrets, mounts.
5. MANIFEST stays personal (D11).

**Non-goals**

- **A central ACL or global role table.** Authorization stays per-system on
  purpose: one tool's permissioning mistake must not open another, and a bad
  policy's blast radius stays inside its schema. The shell (§4) is a *client* of
  five independent authorization systems, never an authority over them.
- An external IdP / SSO product. Supabase auth is the realm; revisit only if a
  third party ever requires SAML/OIDC.
- Cross-system data integration (Kraken client ↔ MANIFEST person). If ever
  wanted, it happens by explicit exchange, not shared tables.
- Merging rolodexes (D11).

---

## 3. The pivot, stated plainly

The draft proposed a subdomain per tool (`manager.`, `manifest.`, `plunder.`)
with sign-in-once achieved by widening the session cookie to
`.seakingcapital.com`. Derek's direction replaces that with **one origin**: the
suite is `app.seakingcapital.com`, a shell at the root, tools under paths.

Three things follow, and the third is the reason this is the better design:

1. **Simpler.** Same-origin cookies are shared by default. The cookie-widening
   mechanism, its configuration in every app, and its "every subdomain must be
   first-party" caveat all disappear — there is nothing to configure.
2. **One address.** `app.seakingcapital.com` is the whole suite. No subdomain
   sprawl, no DNS entry per tool at GoDaddy, no certificate per tool.
3. **Safer, concretely.** Under the draft, the cookie domain
   `.seakingcapital.com` would have covered `portal.seakingcapital.com` — a
   client portal user's session credential would have been presented to the
   manager, MANIFEST, and every other suite app on every request. Deny-by-default
   meant they could *do* nothing with it, but the credential travelled, and one
   session-handling bug anywhere in the suite would have been reachable by an
   external user's browser. Under one origin, `portal.` is a **separate origin
   with a separate cookie jar**: a client's session never reaches the shell at
   all. The isolation is enforced by the browser, not by our policies.

That third point converts D9 (portal stays outside) from an organizational
preference into a security boundary. It should not be given up later for
convenience.

**The cost, stated honestly:** one origin means one front door, and a front door
is a shared dependency. §12 treats that as a first-class risk, and §4.5's
recommendation is driven by it.

---

## 4. The shell

### 4.1 What it is [DECIDED in shape, PROPOSED in detail]

A small application at the root of `app.seakingcapital.com`. It owns exactly
four things:

1. **Sign-in** — one login page for the suite.
2. **The launcher** — tiles for the tools you hold membership in, and only those.
3. **Account administration** — the per-system yes/no toggles (D10).
4. **Sign-out** — which, being same-origin, signs you out of everything. Correct
   for a suite.

It is deliberately small. It holds no business data, no system's tables, and no
authorization state of its own.

### 4.2 What it does not own

**Authorization.** Each tool's RLS remains the sole authority on what that tool
will hand out. The shell never decides access; it reads and writes membership
through interfaces each system controls (§4.3, §5.3).

This is the non-goal in §2 made concrete. A launcher that hides a tile is
**convenience, not security** — exactly Kraken's house rule applied one level
up. If someone types `/plunder` directly with no membership row, Plunder's own
policies are what stop them, and they must be sufficient on their own. That
requirement is what §7 exists to satisfy.

### 4.3 The launcher read [PROPOSED]

Each system's membership table carries one additional policy: **a user may
SELECT their own row.** The shell then does one cheap read per system —
`manifest.app_owners`, `kraken.users`, `plunder.members`, later Harpoon and
Deepwatch — under **the signed-in user's own session with the publishable key**.
Rows that come back become tiles.

Properties worth noticing:

- The shell holds **no secret key** for this. It cannot see more than the user
  can.
- Deny-by-default does the work twice, independently: no membership row means
  no tile *and* no data.
- Adding a system to the launcher is adding a policy and a read, not extending a
  central registry.

### 4.4 Account administration — the toggles [PROPOSED mechanism for DECIDED D10]

Derek's decision: creating an account is answering "Kraken access? Plunder
access? MANIFEST?" as yes/no toggles, admin-driven. Those toggles are membership
rows in five different schemas. The design question is who writes them.

**Rejected: the shell holds a secret key and writes directly.** That makes the
shell the one application whose compromise grants write access to every system's
membership surface — i.e. the ability to grant oneself everything. It
concentrates precisely the residual risk §6.5 is trying to keep diffuse.

**Proposed: each system exposes its own admin RPC.**
`kraken.admin_set_membership(...)`, `plunder.admin_set_membership(...)`, and so
on — SECURITY DEFINER, pinned `search_path`, each one checking *by its own
system's rules* that the caller is entitled to grant access to it. The shell
calls them under the admin's own session.

- The shell needs **no secret key at all**.
- A compromised shell can do exactly what the signed-in admin could already do.
  No privilege amplification.
- Each system stays the authority on who may grant access to it — the non-goal
  holds.

**Two wrinkles, named rather than hidden:**

- *Bootstrapping.* The first admin of each system cannot be created through the
  toggle, because nobody is entitled yet. That is a one-time direct-connection
  insert per system, exactly how MANIFEST seeds `app_owners`. Fine, but it must
  be written down per system rather than discovered later.
- *Creating the person.* Adding a row to `auth.users` is a realm-level act
  needing the admin API, not a per-system membership write. **Recommendation:
  keep user creation as an operator script** (MANIFEST already has
  `npm run auth:set-password`) and give the shell only the toggles. The shell
  stays secret-key-free, and account creation is rare enough — this is a handful
  of people — that a script is not a burden. Revisit if the cadence ever
  justifies it.

### 4.5 How tools mount [DECIDED 2026-08-06 — D15: option (b)]

Derek's originally proposed shape was multi-zone. Having looked at what actually
has to be served, this document recommended differently — availability being the
reason — and **Derek approved (b) on 2026-08-06**, with the platform
consolidation onto Netlify and the interim-origin arrangement travelling with
it. The options as analyzed:

| Option | Shape | Assessment |
|---|---|---|
| **(a) Next.js multi-zone** | The shell app owns the root and `rewrites` `/kraken/*` and `/manifest/*` to each tool's own deployment | Works, keeps repos independent — but **every Kraken request then passes through the shell app's server.** The shell becomes a runtime dependency of a production financing system. It also cannot cleanly host Harpoon, which is Python. |
| **(b) Platform-level path routing** ✅ | Routing rules on the `app.seakingcapital.com` site proxy `/kraken/*`, `/manifest/*`, … to each deployment at the CDN edge; the shell app merely serves `/` | Same URLs, same cookie jar, same user experience — but the shell is **out of the critical path**. If the shell is broken, `/kraken` is unaffected. Framework-agnostic, so Harpoon can join later without a rewrite. |
| **(c) One monolith** | Absorb every tool into a single application | Rejected. Merges deploy cadence and blast radius, and each system's independence is the point. |

**Decided: (b).** Kraken is a system of record with a real external client on
it; putting a new, young application in front of every one of its requests
trades a real availability property for nothing. Edge routing gets the same
one-origin result and keeps failures independent.

**Decided with it:** the shell and mounted tools consolidate onto **one
platform — Netlify**, where Kraken already lives. (Routing across two vendors
works, but it puts a second host in the request path of every MANIFEST page.)
The cost is concrete and small: MANIFEST's two Vercel crons (`vercel.json` —
gmail `17 * * * *`, gcal `42 */4 * * *`) become Netlify scheduled functions,
done at S2. The S-track's interim origin is a Netlify subdomain, named at S1;
a `suite.seakingcapital.com` CNAME at GoDaddy is optional polish.

---

## 5. Identity and authorization

### 5.1 One realm, four user classes [LIVE]

| Class | Examples | Provisioned by | May hold membership in |
|---|---|---|---|
| Partners | Derek, Austin | each other | any |
| Staff | Kraken operators / admin managers | partners | Kraken only, unless deliberately added |
| External — client | Kraken portal users | admin managers (grant-scoped) | Kraken only, bound to `client_id` |
| External — investor / creditor | future | partners | Kraken only (stub tables) |

**Invariant: a row in `auth.users` means "may attempt sign-in" and nothing
more.** Every capability comes from a per-system membership row. There is
deliberately no "suite member" concept — not even now that there is a suite.

### 5.2 Sign-in mechanics

- Email + password primary; magic link retained as recovery. **Signup disabled
  at the realm level** (D4), with `shouldCreateUser: false` on every OTP call as
  belt-and-braces.
- Self-service password reset stays available to portal users — it is
  customer-facing and must keep working. Partners and staff use it too.
- **Email delivery becomes production-critical the day Kraken's portal moves.**
  Free-tier SMTP cannot serve customer password resets. Custom SMTP on `seaking`
  is a hard gate of the cutover (§9 K4). Independently, the same deficiency
  exists on `ucfy` **today** — approved, queued behind the freeze, and not this
  workstream's to execute.

### 5.3 The universal authorization pattern

Each system owns, inside its own schema:

1. **A membership surface** — `manifest.app_owners`, `kraken.users` (+
   `user_client_access`), `plunder.members` (§7), and so on.
2. **SECURITY DEFINER helpers with pinned `search_path`** — so policies read
   cleanly and the definer-function shadowing attack is closed. Kraken's helpers
   live unqualified in `public` today and get moved and pinned at K1.
3. **RLS on every table, deny-by-default** — a table without a policy is
   unreachable, not public. MANIFEST enforces this by looping over `pg_tables`
   at migration time; Kraken states it as the house rule; Plunder currently
   violates it (§7).
4. **Its own migration ledger** `{system}.schema_migrations` — RLS on, zero
   policies, zero grants: invisible to every API role, touched only by deploy
   tooling on a direct connection.
5. **A self-row SELECT policy** on the membership surface, so the launcher can
   read it (§4.3).
6. **An admin grant function**, self-defending, so the toggles can write it
   (§4.4).

Items 5 and 6 are what the shell adds to the pattern. Both are additions to each
system's own schema, under that system's own control — the shell gains no
authority from either.

**The suite-wide test, unchanged and now more important:** *for every system
schema, a signed-in user with no membership row reads zero rows and writes
nothing under the publishable key.* One origin means every signed-in person's
browser can reach every mounted tool's URL, so this test is the thing standing
between a MANIFEST-only user and Kraken's ledger. It runs per schema, as a probe
suite, before the shell serves anyone but Derek.

### 5.4 Per-system role vocabularies (D6)

| System | Roles | Meaning |
|---|---|---|
| Kraken | `admin_manager`, `operator`, `client`, `investor` (stub), `creditor` (stub) | as today — unchanged by the port |
| MANIFEST | owner (a membership row, no enum) | exactly one row per instance |
| Plunder | `partner` (proposed) | full access; arrives with §7 |
| Harpoon / Deepwatch | `partner` (proposed) | same |

"Partner" deliberately does not exist as a Kraken role. Derek and Austin appear
in Kraken as `admin_manager` rows like anyone else — what makes them partners is
which *other* systems they hold membership in. This keeps Kraken's role enum
meaning exactly what its whole migration lineage already assumes.

### 5.5 Kraken manager scoping (D14) — DECIDED 2026-08-07: option (a)

Verified behavior today: **all manager-tier users, including admin managers, see
and write only clients they hold `user_client_access` grants for.** Derek's
stated intent was "a Manager sees assigned clients; an admin still sees it all."

- **(a) Keep universal grant-scoping** and make "admin sees all" true
  operationally: partners and admins get a grant row per client, auto-created by
  a trigger on client creation. No schema change, every read stays
  grant-auditable, no new tier to reason about. "All" is maintained rather than
  intrinsic.
- **(b) Introduce an unscoped tier** whose policies skip the grant predicate.
  Matches the mental model literally — and reopens exactly the class of unscoped
  policy the 2026-07-17 hardening spent a migration closing. Every future policy
  must handle the bypass correctly, forever.

**Decided: (a)** (Derek, 2026-08-07). The hardening migration is an argument
from experience: unscoped tiers are where Kraken's own review found its gaps.
And the posture has now been arrived at twice independently — the 2026-07-17
hardening closed the write side, and the 2026-08-06 `clients_write` split made
admin *visibility* grant-driven too (Kraken pitfall #19), verified against
Derek's own grants before shipping. Option (b) would have unwound both.

Implementation, at the K-session: a trigger auto-granting designated
partner/admin users on client creation, so "all" stays true without a policy
bypass. Every read remains grant-auditable.

### 5.6 External users, stated as tests

- A `client` user's session presented to Plunder, MANIFEST, Harpoon, Deepwatch:
  zero rows, zero writes — by the absence of membership rows plus
  deny-by-default. **And under D9 they cannot even present it**: the portal is a
  separate origin, so the session never leaves it (§3).
- A `client` user inside Kraken: bound to their `client_id` exactly as today.
  The port changes their world by one thing only — a re-login.

---

## 6. Platform conventions

### 6.1 Schemas and naming

One schema per system: `kraken`, `plunder`, `manifest`, later `harpoon`,
`deepwatch`. `public` holds shared extensions only. Enums are schema-scoped —
`kraken.user_role` and a future `plunder.user_role` cannot collide, which is the
original reason for the whole convention.

**Project-global namespaces need prefixes**, because schemas don't cover them:

| Namespace | Convention | Note |
|---|---|---|
| Storage buckets | `kraken-po-uploads`, `kraken-invoice-uploads`, `kraken-payment-uploads`, `kraken-advance-request-attachments` | **Four buckets, not one** — the draft undercounted; renamed at port |
| Edge functions | `kraken-plaid-sync`, `kraken-gl-audit`, … | slugs are project-wide |
| Cron jobs | `kraken-…` | all 8 (§9 K3) |
| Secrets | `KRAKEN_PLAID_CLIENT_ID`, … | |
| **URL paths** | `/kraken`, `/manifest`, `/plunder`, … | new under D7; the path *is* the namespace users see |

### 6.2 Migrations and deploys (D12)

**Nobody runs `supabase db push` against `seaking`, ever.** The CLI's single
ledger belongs to Plunder's frozen history. Each repo applies its own migrations
over a direct connection and appends to `{system}.schema_migrations`. MANIFEST's
runner is the reference implementation; Kraken writes an equivalent at K1.
Forward-only everywhere.

### 6.3 Keys and the shared blast radius

One project means **one set of service-tier credentials spans every schema**.
RLS guards the user path; nothing guards a leaked secret key. The real price of
consolidation, written down rather than waved at:

- Secret keys never leave server-side env. No `NEXT_PUBLIC_` spelling exists for
  them in any repo.
- **Mint one named secret key per app** (`manifest-app`, `kraken-manager`,
  `kraken-portal`) — a suspected leak revokes one app's key without a suite-wide
  rotation, and access logs attribute by key.
- **The shell holds no secret key** under §4.3–§4.4. That is the single most
  valuable property of the proposed shell design: the app every person touches
  first is the one with nothing to steal.
- Accepted residual risk: a compromised server environment of any *other* app
  exposes all schemas. Separate projects would kill sign-in-once; schema-scoped
  keys don't exist. Revisit if Supabase ships finer-grained keys.
- The publishable key is public by design; RLS is its entire security model —
  which is why §5.3's probe suite is an invariant and not a preference.

### 6.4 Where credentials live

Netlify site env ×2 (`ucfy` URL + anon + service_role, production Plaid, Resend)
· **GitHub Actions secrets — a direct Postgres URL to `seaking`** · local
`.env.local` files on Derek's machine · Harpoon's Docker compose env (Twilio,
Gmail OAuth, SAM, LLM keys) · Supabase `ucfy` secrets store. Enumeration of the
Netlify and Supabase stores is outstanding (§13).

### 6.5 Free-tier reality

Current usage fits comfortably. The port adds Kraken's data and storage —
inventory sizes at K0 against 500 MB DB / 1 GB storage / 5 GB egress. Custom
SMTP is required regardless of tier. If a ceiling approaches, one Pro project
($25/mo) is the entire fix and the design doesn't change.

---

## 7. The Plunder gate ⛔

**The estate's one live deny-by-default violation, and a hard gate on
everything else.**

Verified on `seaking` 2026-08-03: `anon` has zero grants on `plunder.*` ✓ — but
`authenticated` has **ALL privileges**, and every data table's single policy is
`FOR ALL TO authenticated USING (true) WITH CHECK (true)`.

**Any signed-in user of the `seaking` realm has full read/write on all Plunder
data.** Today the realm holds exactly one user, so there is no live exposure.
It was invisible to code review — the policies live in migrations applied long
ago — and surfaced only by inspecting the live database.

**The gate:** `plunder.members` plus membership-checked policies replacing the
`USING (true)` blanket must land **before a second user exists in the `seaking`
auth realm.**

The one-origin pivot makes this gate bind *earlier* than the draft assumed. The
draft tied it to Kraken's K2, on the reasoning that the port is what brings
other people into the realm. Under D7 that is no longer true: **the shell is
what brings the second user in**, and that could be Austin getting a MANIFEST
instance or a staff member getting Kraken access — either of which can precede
K2 by weeks. The trigger is the second realm user, whatever creates them.

Work required, in Plunder's own repo: a migration adding `plunder.members`
(with the §5.3 self-row SELECT policy and admin grant function), policies
rewritten from `USING (true)` to membership-checked, and grants narrowed from
ALL. The nightly worker is unaffected — it connects directly, not as
`authenticated`. The local dashboard needs Derek's membership row, which is the
bootstrap insert of §4.4.

**How it ships** (discovery.md §3, found 2026-08-06): Plunder's deploy runner
*is* its nightly GitHub Actions workflow — `worker migrate` runs at 06:30 UTC
every night. The gate migration lands by merging to Plunder's main; it applies
on the next nightly, or same-day via `workflow_dispatch`. No direct-connection
ceremony needed — but nothing else should apply `plunder.*` migrations, ever.

---

## 8. Mount mechanics [PROPOSED]

One origin makes several previously-irrelevant app details load-bearing. All are
config, none are architecture — but all must be handled before a tool mounts.
Evidence for each: discovery.md §8.5.

### 8.1 basePath

No app sets `basePath` today. Each mounted tool sets `basePath` and
`assetPrefix` to its mount point so its own links and static assets resolve.

### 8.2 The manager's URL changes

`app.seakingcapital.com` is the manager *today*; under D7 the manager becomes
`app.seakingcapital.com/kraken` and the root becomes the shell. That is a URL
change for a live application with real users and real bookmarks. It needs
redirects from the old paths and a note to whoever uses it. Handled in K4.

### 8.3 MANIFEST's service worker must be re-scoped

MANIFEST registers `/sw.js` and sends `Service-Worker-Allowed: /` — **a service
worker scoped to `/` claims the entire origin**, so as written it would
intercept `/kraken/*`. At a path mount everything re-scopes to `/manifest/`: the
SW path, the `Service-Worker-Allowed` header, `start_url`, `scope`, both
shortcut URLs (`/?capture=1`, `/watchlist`), and icon paths. Derek re-installs
the phone PWA after the move — worth doing before he depends on it daily, which
is an argument for mounting MANIFEST early (§11).

### 8.4 No iframes

MANIFEST sends `X-Frame-Options: DENY`. The shell routes by path and must not
embed tools in frames. That is the correct design anyway; the header forecloses
the wrong one.

### 8.5 The shared cookie jar — the one thing to test first

Every app on the origin talks to the same project ref, so they all read and
write **the same auth cookie**. That shared cookie *is* the sign-in-once
mechanism — and it means the apps must agree on how it is encoded and chunked.
They currently do not obviously agree: **Kraken pins `@supabase/ssr` ^0.5.2
(manager, portal, `packages/auth`); MANIFEST pins ^0.7.0.**

Whether those two interoperate on one cookie is **[UNVERIFIED] and must be
tested, not assumed** — it is the first experiment of the shell build, and its
answer decides whether a version pin is a prerequisite or a cleanup.
**Recommendation regardless: one `@supabase/ssr` version suite-wide**, ideally
behind a shared client package, so this never becomes an emergent property of
independent upgrade schedules. Next.js versions may drift freely between mounts;
only the cookie contract has to be common.

---

## 9. Kraken port runbook [runbook detail PROPOSED; timing DECIDED]

**The whole arc runs as one extended session at the end (D13).** Kraken stays
in daily production use on `ucfy` until that session, and — Derek, 2026-08-06 —
*"we cannot have that tool exist in two places — there needs to be a clean
cutover."* The phases below keep their gates; what the decision changes is that
they execute **consecutively in one compressed arc**, not spread over weeks.
Operationally: data is copied at session start (K2), and K5's cutover includes a
**final delta sync inside a brief prod write-freeze**, so the `seaking` copy is
exact at the moment of the swap and no drift window ever exists. The session
ends in cutover or in full rollback — never in coexistence.

Rollback before the K5 swap is always "flip env back"; `ucfy` is untouched
throughout.

**Prerequisites, all outside this runbook:** the S-track complete (§11), §7's
Plunder gate closed, and Derek's green light for the session — which is also
the moment the suite-side freeze on `ucfy`/Netlify lifts. Read-only pre-work
(the outstanding `ucfy` discovery in §13) can and should happen earlier; it
shortens the session.

**K0 — inventory.** Full dump of `ucfy` (schema, data, `auth.users` +
identities, storage objects). Written inventory: the 8 `cron.job` rows with
their `command` bodies, `invoke_edge_job`'s definition, whether edge functions
are deployed at all (the platform endpoint returned empty against 7 repo dirs —
unresolved), how the `-email` crons actually deliver, SMTP config, project
secret names, both Netlify sites' env vars, storage object count and size per
bucket, DB size, Plaid environment and credential locations.
**Gate:** dump restores cleanly into a scratch database; inventory reviewed by
Derek. *Netlify enumeration needs Derek's session (§13).*

**K1 — schema transform.** Rewrite `public` → `kraken` **and `internal` →
`kraken_internal`** (two schemas, discovery.md §2.5 #1 — the second stays
non-exposed; the scoped wrapper views' definer bodies and every pinned
`search_path`, including `refresh_po_projections`'s `internal,public`, rewrite
in lockstep) across the full migration lineage *as of the session* (166 at the
2026-08-03 count; re-counted at K0). Because at least 17 migrations
hard-qualify `public.` (recount at K0 too), the transform is scripted —
qualification rewrite, replay into a scratch schema — then **validated by
structural diff** against the `ucfy` original: tables, columns, constraints,
indexes, functions, triggers, policies, count and definition parity. Kraken's
own DB pitfalls #1/#2/#3/#14/#18/#20 are part of the transform spec (enum
ADD VALUE isolation; pinned paths on MV-inlined functions and SECURITY DEFINER
triggers; projection-object exposure; CRLF-preserving function bodies).
Helpers move into `kraken` with pinned `search_path`. Create
`kraken.schema_migrations` seeded with every ported version, and Kraken's own
migration runner (§6.2).
**Gate:** structural diff clean; Kraken's test suite passes against the scratch.

**K2 — data and auth port.** Restore data into `kraken.*` on `seaking`. Copy
`auth.users` + `auth.identities` preserving UUIDs and password hashes — except
Derek (and Austin if present), whose rows already exist: their old IDs are
remapped by scripted FK rewrite driven by **the FK graph, not grep**. **The
System service account ports at its exact fixed UUID** (every pg_cron wrapper
impersonates it — discovery.md §2.5 #3). **Vault contents migrate explicitly**
(a dump doesn't carry them): regenerate `cron_secret` on `seaking` + re-`secrets
set` it; re-store the Plaid access token(s) through the store RPC (§2.5 #2).
All sessions invalidate; everyone re-logs-in once.
**Gate:** row-count parity per table; projection rebuild produces identical
balances on both sides; login works for a partner, an operator, and a test
client user; `get_plaid_access_token` decrypts on `seaking`.

**K3 — storage, functions, crons.** All **four** buckets recreated with
prefixed names, objects copied, storage policies ported. Edge functions deployed
under prefixed slugs with secrets re-provisioned — **Plaid is production, so
credential handling is choreography, not a copy-paste.** All **8** cron jobs
recreated with prefixed names and their exact schedules (`daily-fee-accrual`
06:00, `projection-drift-check` 07:30, `gl-audit` 07:45, `plaid-sync` 08:00,
`aged-out-warning-email` 11:30, `insurance-claim-deadlines` 12:00,
`state-of-default-reminder` monthly, `weekly-digest-email` Mon 12:00).
**Gate:** an upload round-trips from a portal build pointed at `seaking`; each
cron function runs once manually and succeeds; a Plaid sync completes against
the production item.

**K4 — realm config and the mount.** Custom SMTP live on `seaking`. The full
auth-config checklist from Kraken's own burn history (discovery.md §2.5 #5):
Site URL set (it silently doubles as the fallback for any non-allowlisted
redirect); redirect allowlist as **one wildcard entry per origin** (bare
`/auth/callback` entries don't match the `?next=` variants resets actually
send); the **customized token_hash Reset Password template** replicated
verbatim (the default PKCE template dies cross-device; template ↔ app `?next=`
coupling is load-bearing); invite templates left default; **no localhost
entries on the production realm, ever**. Verified with Kraken's own
`verify-auth-redirects.mjs` against `seaking`. Manager gains
`basePath: '/kraken'` + `assetPrefix` behind env, with redirects from its
current root paths (§8.2). The portal changes **not at all** — it keeps its own
origin (D9).
**Gates:** password reset delivers to an external address in seconds, not
hours — **opened cross-device** (request on one machine, click on another);
the manager serves correctly under `/kraken` on a staging origin with assets,
links, and server actions intact.

**K5 — parallel verification and cutover.** Staging manager + portal pointed at
`seaking` run alongside production — *within the session only*: this is the one
deliberate, hours-scale overlap, and it exists to verify, not to operate. §5.3's
probe suite runs per schema. D14 is implemented and probed. Then the cutover
sequence: **brief prod write-freeze → final delta sync** (tables changed since
K2's copy, re-verified by the same parity and projection checks) **→ env swap on
the production apps + the `app.` routing flip** (the shell takes the root, the
manager takes `/kraken` — §8.2's redirects go live; legacy env names carry
new-format key values without code changes) **→ Plaid webhook re-registration**
(the manager's `/api/plaid-webhook` route moves with the basePath; one
`itemWebhookUpdate` call + the `PLAID_WEBHOOK_URL` env — discovery.md §2.5 #4).
The `ucfy` project stays untouched.
**Gate:** Derek completes a real working session on staging-manager; a real
client completes a portal session; sign-in-once verified across the shell,
`/manifest`, and `/kraken`; **a MANIFEST-only user is verified to get nothing
from `/kraken`**; post-swap parity confirmed before the write-freeze lifts.

**K6 — retirement.** After an agreed soak (suggest 2–4 weeks), final dump of
`ucfy`, archive offline, delete the project.

Plunder is untouched by all of this — §7 happens on its own schedule and
earlier. MANIFEST is untouched except that it is already mounted (§11).

---

## 10. MANIFEST, Harpoon, Deepwatch in the suite

**MANIFEST** is already conformant — it defined half these conventions. Suite
work it needs: the §8.3 re-scope, the §4.3 self-row policy, and a decision on
its crons if the platform consolidates (§4.5). A second instance for Austin
stays deferred; when wanted, it is a fresh schema from the same lineage with its
own `app_owners` row. **Prerequisite regardless of timing:** sync's
`MANIFEST_OWN_DOMAINS` becomes own-*addresses*, because both partners share
`seakingcapital.com` and domain-grained direction reads Derek's outbound with
Austin cc'd as Austin's own. Tracked in MANIFEST; must land before instance two.
Fixtures can never reach `seaking` — the fixture provider refuses non-local
databases.

**Harpoon** joins the web surface eventually (D-level decision made). When it
does it gets a schema, a ledger, a membership table, the §5.3 additions, and a
path — and the PII posture that currently justifies binding to 127.0.0.1 has to
be re-established in a world where the queue UI is reachable from a browser
anywhere. That is a design conversation to have then, deliberately, not a
mechanical mount. Its data is SQLite in a Docker volume today; whether it moves
to Postgres is undecided and not urgent.

**Deepwatch** has no UI and no user surface. It joins if and when it grows one.
Confirming the Harpoon → Deepwatch webhook integration is on the discovery list.

---

## 11. Sequencing [DECIDED in shape — D13]

Derek's build order, 2026-08-06: **the suite is built in parallel, excluding
Kraken, while Kraken's own debugging continues on the side. Bringing Kraken in
is the last task** — one extended session, clean cutover, because Kraken is in
production use throughout and must never exist in two places.

That splits the work into two tracks.

### Track S — the suite, excluding Kraken (now)

Zero production surface anywhere in this track; it runs entirely under the
standing freeze, in parallel with Kraken's product workstream.

**One consequence to hold in mind throughout: the S-track lives at an interim
origin.** `app.seakingcapital.com` *is* the manager today — the shell cannot
occupy that root until the final session claims it. The suite builds and runs at
an interim host (naming folds into D15's platform decision), and the flip of
`app.` from "manager at root" to "shell at root, manager at `/kraken`" is part
of the K-session's cutover. Everything mounted during the S-track moves address
once, at cutover, by design.

1. **This document agreed** — done: D15 decided 2026-08-06 (§4.5); nothing
   blocks S1. D14 is *not* needed until the K-session.
2. **§7 — the Plunder gate.** First, and independent of everything else: its
   clock is "before the second realm user," and the S-track itself is what
   creates that user (Austin, or staff). Nothing else in the estate has a
   deadline.
3. **S1 — shell skeleton** at the interim origin: sign-in, launcher over §4.3
   reads, sign-out. Zero tools mounted. **First experiment: the §8.5 cookie
   test.**
4. **S2 — mount MANIFEST at `/manifest`.** The lowest-risk possible first
   mount: one user, no external users, no money. It proves the whole model —
   and it is where MANIFEST's deploy un-waits: Derek gets his phone-reachable
   URL at the interim origin and enters the thirty relationships against it.
   (One PWA re-install at cutover when the address changes — §8.3.)
5. **S3 — the toggles** (§4.4), once two systems exist to toggle between.
6. **S-track done** = shell, launcher, toggles, and MANIFEST running at the
   interim origin, probe suite green for every schema present, §7 closed.
   Harpoon and Deepwatch join later as they arrive (§10) — they are not gates.

### Track K — the finale (one extended session)

7. **K0–K6 as one compressed arc** (§9): inventory → schema transform → data +
   auth port → storage/functions/crons → realm config + mount → verification →
   write-freeze, final delta, cutover. The session's green light is also the
   freeze-lift. Read-only `ucfy` discovery beforehand shortens it.
8. Soak (2–4 weeks, §13) → **K6 retirement** of `ucfy`.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| **The shell becomes a single point of failure for a production financing system** | §4.5(b): route at the edge, keep the shell out of Kraken's request path. This is the reason for the recommendation. |
| Plunder's `USING (true)` policies meet a second realm user | §7 as a hard gate, sequenced first |
| Shared cookie jar, two `@supabase/ssr` versions | §8.5: test before building on it; pin one version suite-wide |
| MANIFEST's root-scoped service worker claims the whole origin | §8.3 re-scope, verified at S2 before Kraken mounts |
| A signed-in person can now reach every tool's URL by typing it | §5.3's probe suite per schema — this is what makes the launcher's tile-hiding safely cosmetic |
| Manager URL change breaks bookmarks and muscle memory | Redirects at K4; comms with the K5 re-login note |
| Shared service-tier credentials across schemas | Named key per app; shell holds none (§6.3); documented residual |
| Free-tier email vs. customer password resets | Custom SMTP as a K4 hard gate; separately a live `ucfy` deficiency today |
| Schema rewrite subtly diverges from `ucfy` | Structural diff gate + projection-parity gate (K1/K2) |
| ID remap misses an FK on partner rows | Remap driven by the FK graph, not grep; per-table parity counts |
| Plaid production credentials during K3 | Treated as choreography with a rollback, not a copy |
| Two workstreams, one production Kraken | **By design now (D13)**: suite builds in parallel excluding Kraken; suite work stays hands-off `ucfy`/Netlify; the port is one extended session at the end |
| Prod data changes between K2's copy and cutover | The extended session compresses the window; K5's write-freeze + final delta sync closes it exactly; parity gates re-run post-sync |
| Kraken's continuing development drifts from the K1 schema transform | The transform runs *inside* the session against that day's migration set — never against a weeks-old snapshot. Migration count re-checked at K0 (166 was the 2026-08-03 parity; it is already 167+) |
| Two repos, one database, human error in deploys | Per-system ledgers; `db push` ban documented in both repos; runners refuse when ledger and directory disagree |
| Dashboard project pages blank in Derek's Chrome | Known workaround (platform API via session); worth trying another browser |

---

## 13. Open questions

**Blocking the S-track:** *none.* D15 was decided 2026-08-06 (§4.5); the
S-track is unblocked. The interim origin's exact subdomain name is picked at S1
and isn't worth a decision cycle.

**Needed at the K-session, not before:**

1. **D14 — Kraken scoping** (§5.5): universal grant-scoping with auto-grants
   (recommended), or an unscoped admin tier?
2. Netlify account access to enumerate both sites' env vars — needs Derek's
   session. Read-only; doing it early shortens the K-session.
3. Client-comms preference for the K5 re-login: email, portal banner, or both?
4. Soak window before deleting `ucfy` (suggest 2–4 weeks).
5. ~~The two queued `ucfy` fixes (close signup, Resend SMTP)~~ **Resolved
   2026-08-07: handed to the Kraken workstream**, launch prompt at
   [`kraken-auth-handoff.md`](kraken-auth-handoff.md). Not suite work. K4's
   realm config should read whatever configuration that session records in
   Kraken's `CLAUDE.md` rather than re-deciding it.

**Timing-free:**

6. Does Austin review this document before build? (Recommended — D11 and §5.4
   concern him directly, and he is the likely second realm user, which trips
   §7 the moment the S-track would add him.)

**Outstanding discovery** (discovery.md §11 tail — the five repo passes all
closed 2026-08-06 into §2.5/§3/§4.1/§5): the §8.5 cookie test (S1's first
experiment) · `ucfy` live-state confirmation at K0 (now a checklist, not an
unknown) · Netlify env enumeration (Derek's session) · experiment repos'
GitHub archival (optional).

**Design debts acknowledged, not blocking:** MANIFEST own-addresses before
Austin's instance · JWT claims optimization only if per-request membership reads
ever show up in latency · `apps/jobs` is a stub; if it becomes real it gets a
named key and the same conventions · how a per-user system like MANIFEST mounts
at a single path when there are two owners (defer with §10, but don't foreclose
it).

---

## Appendix A — evidence index

| Claim | Where verified |
|---|---|
| Grant-scoping enforced, incl. admin writes | `KRAKEN/supabase/migrations/20260717120001_rls_admin_scope_hardening.sql` |
| "RLS is the authority" house rule | same file, header comment |
| Five roles incl. stubs; client_id CHECK | `20260423120002_reference_tables.sql`, `packages/auth/src/roles.ts` |
| Helpers unqualified in `public` | `20260423120007_rls_policies.sql` |
| 17 migrations hard-qualify `public.` | `grep -rl "public\." KRAKEN/supabase/migrations` |
| Netlify ×2, 4 buckets, 8 crons, production Plaid, open signup, no SMTP | live `ucfy` read 2026-08-03 — discovery.md §2.3 |
| Plunder `USING (true)` for `authenticated` | live `seaking` read 2026-08-03 — discovery.md §3.1 |
| Plunder runs on GitHub Actions cron | Plunder README M11 — discovery.md §3 |
| `@supabase/ssr` split 0.5.2 / 0.7.0; no `basePath` | the four `package.json` files; both `next.config.ts` — discovery.md §8.5 |
| MANIFEST PWA scoped to `/`; SW claims the origin | `public/manifest.webmanifest`, `src/lib/offline-queue.ts:130`, `next.config.ts` |
| MANIFEST's two crons | `manifest/vercel.json` |
| Kraken product work continued through the freeze | `sea-king-capital-servicing-engine` commits `6a1fe51`…`c076837`, 2026-08-06 |

## Appendix B — what this revision changed

| Draft (2026-08-03) | Now | Why |
|---|---|---|
| §3.3 sign-in-once by widening the cookie to `.seakingcapital.com` | **Deleted.** Same origin, cookies shared by default (§3, D8) | The pivot removes the mechanism entirely — and removes a real weakness: the widened cookie would have travelled to portal clients' browsers |
| §8 hosting table: a subdomain per tool | **Replaced** by the path map and mount mechanics (§4, §8) | D7 |
| Multi-zone assumed as the shape | **Reopened as D15** with edge routing recommended (§4.5) | Availability: multi-zone puts the shell in Kraken's request path |
| Kraken at `manager.`, hosting unknown | Netlify ×2, manager at `app.` | discovery.md §9(1) |
| Plunder gate binds before K2 | Binds before **the second realm user**, whatever creates them (§7) | Under D7 the shell creates that user, possibly long before K2 |
| Plunder "[LIVE data, unknown code]" | Repo, architecture, and GitHub Actions runner known (§1.3) | discovery.md §3 |
| Harpoon / Deepwatch "[UNKNOWN]" | Both documented (§1.5, §1.6, §10) | discovery.md §4, §5 |
| One storage bucket, unstated cron count | Four buckets, eight named crons with schedules (§6.1, K3) | discovery.md §9(3) |
| Account admin unspecified | Toggles via per-system admin RPCs; **shell holds no secret key** (§4.4) | D10, and keeping the non-goal in §2 honest |
| Launcher unspecified | Self-row SELECT policies read under the user's own session (§4.3) | same |
| SMTP framed as a K4 gate only | Also a live `ucfy` deficiency today (§5.2) | discovery.md §9(4) |
| MANIFEST deploy "do anytime" | Sequenced as **S2, the first mount**, at the interim origin (§11) | §10a(a) held it for the URL picture; this document settles it |
| K-phases interleaved with suite steps in one sequence | **Two tracks**: the S-track now, Kraken as one extended finale session with write-freeze + delta cutover (D13, §9, §11) | Derek 2026-08-06: Kraken must never exist in two places — clean cutover |
| Nothing about PWA scope, basePath, or cookie versions | §8 in full | Only became load-bearing under one origin |
| §11 open questions, 8 items | 7 answered by discovery and §10a; 2 blocking decisions remain (§13) | |
