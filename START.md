# Session-launch prompt

Copy everything below the line into a fresh Claude Code session opened at
`C:\Users\stink\Claude Projects\`. Keep it current: when the state of the world
changes, this file changes in the same commit.

---

You are working on the Sea King software suite for Derek (derek@seakingcapital.com), principal of Sea King Capital LLC. This session is opened at `C:\Users\stink\Claude Projects\`, where every system's repo sits side by side.

**Read these before doing anything else, in order:**
1. `SEAKING-SUITE/README.md` — the estate in one page and the standing constraints.
2. `SEAKING-SUITE/discovery.md` — the master process file: every fact with its evidence, every decision (§10, §10a), the dated log (§11 — read the newest entries; the tail lists what discovery still owes).
3. `SEAKING-SUITE/suite-design.md` — the design draft; its banner lists which parts Derek's one-origin pivot has superseded.

**Non-negotiable ground rules:**
- ⛔ **Production Kraken is frozen.** No changes of any kind to the Netlify sites (`app.` / `portal.seakingcapital.com`) or the `ucfyfnwkxzryywuomool` Supabase project until Derek lifts the freeze explicitly. Reading is fine; writing is not. Two approved fixes (disable signup; custom SMTP via Resend) are queued behind the freeze — do not execute them early.
- Never run `supabase db push` against the `seaking` project (`oznvdznekexdgblmxwqr`). Each system applies its own migrations over a direct connection and records them in its own `{schema}.schema_migrations` ledger. Never load MANIFEST fixtures into `seaking`.
- **Discovery before build.** Nothing is built from assumption. New facts go into `discovery.md` with evidence and a dated log entry. Decisions get recorded there before code depends on them. When something is ambiguous, ask Derek — he has said explicitly to keep asking.
- Log adjustments and decisions in `discovery.md` as they happen, not at the end.

**Where things stand (verify against discovery.md rather than trusting this summary):**
- **MANIFEST** (`manifest/` — its README is the deep context): deployed to `seaking`, empty, password sign-in works on localhost. Next: Derek hand-enters his thirty most important relationships locally. Its Vercel deploy is deliberately **waiting** on the shell/URL decision. Google sync stays unconfigured until after the thirty.
- **Suite architecture** (decided, not built): one origin — `app.seakingcapital.com` becomes a shell/launcher; sign in once; per-system membership decides which tools even appear; tools mount under paths as separate apps. Account setup is admin-driven per-system yes/no toggles; self-signup exists nowhere. MANIFEST is the only per-user system. The client portal stays at `portal.seakingcapital.com`, permanently outside the shell.
- **Plunder** hard gate: its tables carry `USING (true)` policies for `authenticated` — membership-checked policies must land before any second user exists in the `seaking` auth realm.
- **Kraken** port runbook (K0–K6) is drafted in suite-design.md; the freeze gates all of it.
- **Harpoon** is local Docker (eventually web); **Deepwatch** is local with a fresh remote at `SKCAccount/DEEPWATCH`.

**The likely near-term queue (confirm with Derek before starting any):**
1. Revise `suite-design.md` fully for the one-origin model (fold in §10a; close the banner).
2. Remaining discovery passes — the tail of `discovery.md` §11 (Kraken CLAUDE.md locked-decisions read; Plunder's GitHub Actions workflow; Harpoon docs + Deepwatch webhook confirmation; `ucfy` cron bodies + `invoke_edge_job`; Netlify env enumeration needs Derek's session).
3. Plunder membership-gate design (`plunder.members` + policies — design in the suite doc, build in Plunder's repo).
4. MANIFEST first-use support, and its deploy when Derek un-waits it.

House style, learned over this project: evidence over assumption; state what was found before what it means; when Derek gives a constraint mid-action, stop immediately and record it; decisions get logged the day they're made.
