# SEAKING-SUITE

The coordination repo for Sea King Capital's software suite — the documents that
span more than one system live here, because they describe nine systems and
belong to none of them.

| File | What it is |
|---|---|
| [discovery.md](discovery.md) | **The master process file.** Facts about every system in the estate, each with its evidence; decisions as they were made (§10, §10a); a dated log (§11). Nothing in the suite gets built from assumption — it gets built from this file. |
| [suite-design.md](suite-design.md) | The identity / authorization / consolidation design, revised 2026-08-06 for the one-origin model. §11 holds the two-track build order (suite first at an interim origin; Kraken last as one extended cutover session); §13 the open decisions. |
| [START.md](START.md) | The prompt for launching a fresh Claude Code session on suite work, from the `Claude Projects` root. |
| [kraken-auth-handoff.md](kraken-auth-handoff.md) | Launch prompt for the Kraken-side session that closes signup and moves auth email to Resend — the two fixes the suite approved but does not execute. |
| [tool-context-prompt.md](tool-context-prompt.md) | Launch prompt, run once per tool, that gives Plunder / Harpoon / Deepwatch / MANIFEST the `CLAUDE.md` each currently lacks — purpose, locked decisions, honest state, pitfalls, and a working agreement. |

## Standing constraints (the short list every session must know)

1. **⛔ Production Kraken is frozen — suite-side** (scope clarified 2026-08-06):
   suite sessions make no changes to the Netlify sites (`app.` /
   `portal.seakingcapital.com`) or the `ucfy…` Supabase project. Derek's own
   Kraken product development continues unaffected — including the two approved
   auth fixes, **handed to that workstream 2026-08-07**
   ([handoff](kraken-auth-handoff.md)). The freeze lifts at the final Kraken
   port session (D13: Kraken comes last, one extended session, clean cutover).
2. **Never `supabase db push` against the `seaking` project.** Each system
   applies its own migrations and records them in its own
   `{schema}.schema_migrations` ledger.
3. **Never load fixtures into `seaking`.** Invented people must never touch
   real data.
4. **Discovery before build.** New facts go into discovery.md with evidence and
   a dated log entry; decisions get recorded before anything is built on them.

## Shorthand used throughout these docs

| Term | What it means |
|---|---|
| **`ucfy`** | Kraken's own Supabase project, ref `ucfyfnwkxzryywuomool` — the database, auth realm, storage, and cron behind production Kraken today. Referred to by the first four characters of its ref because that is how the dashboard and CLI identify it. |
| **`seaking`** | The combined Supabase project, ref `oznvdznekexdgblmxwqr` — hosts MANIFEST and Plunder now, Kraken after the port. Named, not ref-shorthanded, because it was renamed to `seaking` on 2026-08-03. |
| **The port / K0–K6** | Moving Kraken off `ucfy` onto `seaking`. Phased runbook in suite-design §9. |
| **Soak** | The wait between cutover and deleting the old project — Kraken runs on `seaking` while `ucfy` sits untouched as a rollback, until enough of a full business cycle has passed to trust it. |
| **S-track / K-session** | The two-track build order (D13): everything except Kraken now; Kraken last, in one extended cutover session. |

## The estate, in one line each

Kraken (production PO-financing/AR-factoring, Netlify + own Supabase project,
frozen) · Plunder (nightly event-scoring engine, GitHub Actions → `plunder`
schema on `seaking`) · MANIFEST (Derek's personal rolodex, `manifest` schema on
`seaking`, per-user by design) · Harpoon (govcon origination agent, local
Docker, eventually web) · Deepwatch (deal-document assembly, local +
`SKCAccount/DEEPWATCH`) · the `seaking` platform project · the GoDaddy marketing
site · two graveyarded experiments.

Full detail, always: [discovery.md](discovery.md).
