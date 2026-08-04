# SEAKING-SUITE

The coordination repo for Sea King Capital's software suite — the documents that
span more than one system live here, because they describe nine systems and
belong to none of them.

| File | What it is |
|---|---|
| [discovery.md](discovery.md) | **The master process file.** Facts about every system in the estate, each with its evidence; decisions as they were made (§10, §10a); a dated log (§11). Nothing in the suite gets built from assumption — it gets built from this file. |
| [suite-design.md](suite-design.md) | The identity / authorization / consolidation design. Carries a revision-pending banner: Derek's one-origin pivot supersedes parts of the draft, and the rewrite lands after the remaining open items settle. |
| [START.md](START.md) | The prompt for launching a fresh Claude Code session on suite work, from the `Claude Projects` root. |

## Standing constraints (the short list every session must know)

1. **⛔ Production Kraken is frozen** — no changes to the Netlify sites
   (`app.` / `portal.seakingcapital.com`) or the `ucfy…` Supabase project until
   Derek lifts the freeze. Two approved fixes (close signup, custom SMTP) are
   deferred behind it.
2. **Never `supabase db push` against the `seaking` project.** Each system
   applies its own migrations and records them in its own
   `{schema}.schema_migrations` ledger.
3. **Never load fixtures into `seaking`.** Invented people must never touch
   real data.
4. **Discovery before build.** New facts go into discovery.md with evidence and
   a dated log entry; decisions get recorded before anything is built on them.

## The estate, in one line each

Kraken (production PO-financing/AR-factoring, Netlify + own Supabase project,
frozen) · Plunder (nightly event-scoring engine, GitHub Actions → `plunder`
schema on `seaking`) · MANIFEST (Derek's personal rolodex, `manifest` schema on
`seaking`, per-user by design) · Harpoon (govcon origination agent, local
Docker, eventually web) · Deepwatch (deal-document assembly, local +
`SKCAccount/DEEPWATCH`) · the `seaking` platform project · the GoDaddy marketing
site · two graveyarded experiments.

Full detail, always: [discovery.md](discovery.md).
