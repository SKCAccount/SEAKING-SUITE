# Session-launch prompt

Copy everything below the line into a fresh Claude Code session opened at
`C:\Users\stink\Claude Projects\`. Keep it current: when the state of the world
changes, this file changes in the same commit.

---

You are working on the Sea King software suite for Derek (derek@seakingcapital.com), principal of Sea King Capital LLC. This session is opened at `C:\Users\stink\Claude Projects\`, where every system's repo sits side by side.

**Read these before doing anything else, in order:**
1. `SEAKING-SUITE/README.md` — the estate in one page and the standing constraints.
2. `SEAKING-SUITE/discovery.md` — the master process file: every fact with its evidence, every decision (§10, §10a), the dated log (§11 — read the newest entries; the tail lists what discovery still owes).
3. `SEAKING-SUITE/suite-design.md` — the design, revised 2026-08-06 for the one-origin model; its §13 lists the open decisions (D15 blocks the S-track).

**Non-negotiable ground rules:**
- ⛔ **The Kraken freeze is suite-side** (clarified 2026-08-06): suite sessions make no changes to the Netlify sites (`app.` / `portal.seakingcapital.com`) or the `ucfyfnwkxzryywuomool` Supabase project, and do not execute the two queued fixes (disable signup; Resend SMTP). Reading is fine. Derek's own Kraken product development continues on its normal cadence and is not this workstream's concern — do not "correct" it against the freeze.
- Never run `supabase db push` against the `seaking` project (`oznvdznekexdgblmxwqr`). Each system applies its own migrations over a direct connection and records them in its own `{schema}.schema_migrations` ledger. Never load MANIFEST fixtures into `seaking`.
- **Discovery before build.** Nothing is built from assumption. New facts go into `discovery.md` with evidence and a dated log entry. Decisions get recorded there before code depends on them. When something is ambiguous, ask Derek — he has said explicitly to keep asking.
- Log adjustments and decisions in `discovery.md` as they happen, not at the end.

**The build order (Derek, 2026-08-06 — D13):** the suite is built **in parallel, excluding Kraken**, while Derek continues debugging Kraken on the side. Bringing Kraken in is **the last task**: one extended session that ports and cuts over cleanly, because Kraken is in daily production use and must never exist in two places. The S-track (shell → MANIFEST mount → toggles) lives at an **interim origin** until that session claims `app.seakingcapital.com`.

**Where things stand (verify against discovery.md rather than trusting this summary):**
- **suite-design.md is revised** (2026-08-03 draft → 2026-08-06 one-origin revision; banner closed). Two blocking decisions remain: **D15** (mount mechanism — edge routing recommended over multi-zone; platform; interim origin name) blocks S1; **D14** (Kraken manager scoping) isn't needed until the K-session.
- **Plunder hard gate**: its tables carry `USING (true)` policies for `authenticated` — `plunder.members` + membership-checked policies must land **before any second user exists in the `seaking` auth realm**. The S-track itself creates that user, so this is sequenced first (§11 step 2). Realm still has exactly one user (verify before relying on this).
- **MANIFEST** (`manifest/` — its README is the deep context): deployed to `seaking`, empty, password sign-in works on localhost. Derek still to enter the thirty relationships (localhost now; the interim origin once S2 mounts it). Google sync stays unconfigured until after the thirty. Known mount work: re-scope the root-scoped PWA/service worker to `/manifest/` (design §8.3); the `@supabase/ssr` version split vs Kraken (0.7.0 / 0.5.2) needs the §8.5 cookie test at S1.
- **Kraken**: actively developed by Derek daily (Netlify deploys, new migrations — the 2026-08-03 "166 migrations" count is already stale). K-runbook (K0–K6) runs as one compressed session at the end, with write-freeze + final-delta cutover.
- **Harpoon** local Docker (PII, localhost-bound; eventually web); **Deepwatch** local with remote at `SKCAccount/DEEPWATCH`. Neither gates anything.

**The likely near-term queue (confirm with Derek before starting any):**
1. Get D15 decided (mount mechanism / platform / interim origin) — it blocks S1.
2. Plunder membership gate: design agreed in suite-design §7; build the migration in Plunder's repo.
3. S1 shell skeleton at the interim origin + the §8.5 cookie interop test.
4. Remaining discovery passes — the tail of `discovery.md` §11 (Kraken CLAUDE.md locked-decisions read; Plunder's GitHub Actions workflow; Harpoon docs + Deepwatch webhook confirmation; `ucfy` cron bodies + `invoke_edge_job`; Netlify env enumeration needs Derek's session).
5. MANIFEST first-use support (the thirty, against localhost until S2).

House style, learned over this project: evidence over assumption; state what was found before what it means; when Derek gives a constraint mid-action, stop immediately and record it; decisions get logged the day they're made.
