# Handoff → Kraken session: split the changelog out of `CLAUDE.md`

Copy everything below the line into a fresh Claude Code session opened at
`C:\Users\stink\Claude Projects\sea-king-capital-servicing-engine`.

**Measured 2026-08-07** (the numbers this session exists because of):

| | bytes | share |
|---|---|---|
| `CLAUDE.md` total | 278,604 (533 lines) | — |
| **"What's shipped" section** (lines 150–340) | **200,843** | **72%** |
| Everything else | 77,761 | 28% |

Roughly 50–60k tokens of changelog, loaded into every session in this repo,
growing with every arc. Run this **after** the auth-hardening session
(`kraken-auth-handoff.md`) if both are queued, so that session's entries are
written before the split rather than after.

---

You are working on Kraken — the Sea King Capital servicing engine, the
production PO-financing / AR-factoring system of record — for Derek
(derek@seakingcapital.com).

**This session moves the shipped-work changelog out of `CLAUDE.md` into a
dedicated `CHANGELOG.md`, and extracts everything durable out of it first.**
No code changes. No feature work. No production changes of any kind. This is
a documentation restructure and nothing else.

## Why, and the thing that makes it risky

`CLAUDE.md` is loaded into context at the start of every session in this repo.
Its "What's shipped" section is 72% of the file — call it 50–60k tokens of
history that a session reading a bug in one server action does not need. It has
grown monotonically since April and will keep growing. The file is already past
the point where standard tooling handles it comfortably.

**But the changelog is not inert, and this is the whole difficulty of the
task.** Those entries are where a great deal of durable, operational knowledge
actually lives — decisions locked mid-arc, semantics chosen after a browser
test, "keep these two sites in lockstep" warnings, notes about what was *not*
verified, and records of deliberate dev data left behind. Some of it is
duplicated into the permanent sections; much of it is not.

**A straight move would degrade every future session.** The value of this task
is almost entirely in the extraction that precedes the move. Budget your effort
accordingly: the `mv` is five minutes, the extraction is the session.

## Phase 1 — Read the whole changelog and classify every entry

Read "What's shipped" end to end. It is long; read it anyway, because the
judgment you need cannot be made from grep. For each entry, sort its contents
into four buckets:

**(A) Durable — must survive in `CLAUDE.md`.** Anything a session needs to
know *without* being told to go look for it:
- Decisions that are locked or that changed a locked one. Many entries contain
  phrases like "(locked)", "per Derek <date>", "SUPERSEDED", or "Derek's call"
  — check every one against the existing **"Decisions already locked"**
  section and add what is missing.
- Invariants and lockstep constraints — "keep both in lockstep," "change both
  in one migration," "LOCKSTEP file pair," "must stay formula-identical."
  These are the highest-value and easiest-to-lose items in the entire file. A
  future session that breaks one of these has caused a real bug.
- Pitfalls. The numbered **"DB / SQL pitfalls"** section exists, but entries
  reference pitfalls by number from inside the narrative ("spawns new pitfall
  #15", "pitfall #17"). Verify every referenced pitfall is actually present in
  the numbered list with its cause, and add any that only exist inside prose.
- Anything describing **current live state** rather than history — production
  configuration, what is registered with which vendor, what is deployed.

**(B) Live state that reads like history but isn't.** Two kinds, both of which
must move to a *state* home rather than a changelog:
- **"NOT yet verified" flags.** Several entries end by naming what was built
  but never exercised — needing Derek's authenticated session, an OAuth
  consent screen, a real wire. **These are open work items, not history.** They
  belong in `docs/BACKLOG.md`. Sweep for every one of them; a to-do buried in
  a changelog entry is a to-do that will never be done.
- **Deliberate dev data.** Entries record test artifacts left in the dev
  database on purpose (test advances that keep accruing, synthetic wires,
  policies, fee rows). A future session needs to know what is real and what is
  scaffolding. Collect these into one **"Dev data currently in the database"**
  section — either in `CLAUDE.md` if short, or a `docs/DEV_DATA.md` it points
  at. Verify against the database where you can; mark anything you cannot
  confirm as **[UNVERIFIED]**.

**(C) Genuine history.** The narrative of what shipped, when, and why —
valuable for archaeology, not needed at session start. This is what moves.

**(D) Superseded and now false.** Entries describing behavior that later
entries reversed (batches, write-offs, the old waterfall, the payment-split
model). These stay in the changelog as history — that is what a changelog is
for — but check that nothing in the *permanent* sections still asserts them as
current.

Show Derek your classification of the ambiguous cases before you act on them.

## Phase 2 — Extract, into the permanent sections

Write everything from (A) into its proper existing home in `CLAUDE.md`
— "Decisions already locked," the invariants list, "DB / SQL pitfalls,"
terminology, conventions. Write (B) into `docs/BACKLOG.md` and the dev-data
section.

Rules:
- **Compress ruthlessly.** A decision needs its statement, a one-line why, and
  a date. It does not need the paragraph of narrative around it.
- **Do not lose the why.** A decision without its reason gets re-litigated;
  that is the failure mode this repo has already avoided well, and the whole
  reason its "Decisions already locked" section works.
- Keep supersession visible. Mark superseded decisions as superseded with a
  date rather than deleting them — the existing file already does this and it
  is why the reasoning survives.

## Phase 3 — Move the rest

Create `CHANGELOG.md` at the repo root with the (C) material.

- **Reverse-chronological — newest first.** It is currently oldest-first, which
  buries the most relevant entries deepest. This matters for a file people will
  skim and search.
- Keep the entries verbatim. This is a move, not a rewrite; do not "improve"
  history.
- Give it a short header explaining what it is, that it is *not* loaded into
  session context, and when to consult it: to find out when and why something
  shipped, or whether a thing was ever built.

Then, in `CLAUDE.md`, replace the "What's shipped" section with **two** things:

1. **A "Where it stands today" section** — a *state* description, not a log.
   What runs in production, what phase the build is in, what is live versus
   stubbed. States do not grow with time; logs do. This is the section that
   answers the question the changelog was being used to answer.
2. **A pointer** to `CHANGELOG.md`, saying explicitly when to read it.

**Do not keep "the last N entries" in `CLAUDE.md`.** It seems reasonable and it
silently regrows the problem — in four months you are back here. The state
section plus the pointer covers the need.

## Phase 4 — Stop it regrowing

Add a short maintenance rule to `CLAUDE.md`, near the top where session
instructions live, saying roughly:

> New shipped work goes in `CHANGELOG.md`. `CLAUDE.md` changes only when a
> decision, an invariant, a pitfall, a convention, or the current-state
> description changes. If you find yourself appending a narrative of what you
> just built to this file, it belongs in the changelog instead.

Update the reading-order instruction at the top of `CLAUDE.md` so a fresh
session knows the changelog exists and when it is worth opening.

## Phase 5 — Verify the split didn't lose anything

Before committing, prove the extraction rather than trusting it:

- Every pitfall number referenced anywhere in the repo resolves to an entry in
  the numbered list.
- Every "(locked)" / "per Derek" / "SUPERSEDED" decision you found in Phase 1
  appears in "Decisions already locked."
- Every "NOT yet verified" item appears in `docs/BACKLOG.md`.
- Every dev-data note appears in the dev-data section.
- `CLAUDE.md` + `CHANGELOG.md` together still contain everything the original
  did — diff the old file against the concatenation if that helps.
- Report the new `CLAUDE.md` size. Target is meaningfully under 80k bytes;
  say what you actually achieved.

Also re-read the slimmed `CLAUDE.md` start to finish as if you were a fresh
session, and say honestly whether you could still work in this repo from it
alone. If something now feels missing, that is the extraction telling you it
missed something.

## Phase 6 — Close

Commit as one focused change with a real message (Derek reads the log). Tell
him: the before/after size, what you extracted and where it went, anything you
found buried in the changelog that surprised you — particularly any invariant,
unverified item, or dev-data note that existed *only* there — and anything you
were unsure how to classify.

## Ground rules

- Documentation only. No code, no migrations, no dashboard, no production.
- If you find a real bug while reading, write it in `docs/BACKLOG.md` and keep
  going. If it is dangerous, say so immediately.
- Preserve history exactly; extract meaning faithfully; do not invent tidiness
  that the record does not support.
