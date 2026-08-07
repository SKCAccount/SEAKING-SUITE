# Per-tool context session — the prompt

Run this **once per tool, in its own session**, opened at that tool's repo:
`plunder/`, `harpoon/`, `deepwatch/`, `manifest/`. One tool at a time; do not
try to do two in one session.

**Why this exists.** Kraken carries a 278 KB `CLAUDE.md` — purpose, invariants,
locked decisions, a root-caused pitfall log, verification records. The other
four repos have **no `CLAUDE.md` at all**, so every session in them begins with
no statement of what the tool is for, what has already been decided, or how to
work here. Derek's read (2026-08-07): Plunder and Harpoon sessions "often miss
the point of an update, or make changes that only halfway address the root
issue," and his own prompts run short because the finished picture isn't fully
formed yet. This session is the fix for the repo half of that.

**Suggested order:** MANIFEST first (smallest, and Derek is about to use it
daily — cheapest place to find out what this prompt gets wrong), then Plunder,
then Harpoon, then Deepwatch. If you'd rather attack the pain directly, start
with Plunder. Expect to refine the prompt after the first run either way.

Copy everything below the line.

---

You are working on **<TOOL>** for Derek (derek@seakingcapital.com), principal
of Sea King Capital LLC. This session has one job: **make this repo one that a
future session can be dropped into and immediately understand what the tool is
for, what is already settled, where it stands, and what to do next.**

You are not building features today.

## The problem you are solving

Derek's sessions here sometimes produce changes that satisfy the literal words
of his prompt while leaving the actual problem in place. Two causes, and both
are addressable in this repo:

1. **His prompts are short**, partly because the finished shape of the tool
   isn't fully formed in his head yet. A short prompt read literally produces a
   narrow change.
2. **Nothing in the repo says what the tool is for**, so there is no goal for
   an ambiguous request to be resolved *against*. Absent that, the literal
   reading is the only reading available.

You cannot fix (1) from inside the repo. You can make it stop mattering as
much, by fixing (2) — and by writing the working agreement that turns a short
prompt into a good question instead of a narrow diff.

Be calibrated: Kraken got where it is through months of debugging under real
use, not through one documentation session. Modest, honest improvement is the
target. **A confident-sounding context file full of things you inferred but
did not verify would be worse than no file at all.**

## Phase 1 — Reconstruct, from evidence

Read before you write anything. Read for *purpose and decisions*, not for a
feature inventory:

- Every `README.md`, spec, build log, backlog, and doc in this repo. For most
  of these tools the real record is not the README — see "Known starting
  points" below for where your tool actually keeps its history.
- The code, enough to know what genuinely runs versus what is stubbed,
  half-built, or dead.
- **`git log` in depth.** This is the richest source you have and the one most
  likely to be skipped. Bug-fix commits contain root causes; reverts and
  re-dos contain decisions that were made, unmade, and remade. Mine it.
- The tool's entry in the suite's `discovery.md` (in `../SEAKING-SUITE/`) —
  it records this tool's place in the estate, with evidence. Read the suite's
  `README.md` too, for the one-origin plan this tool eventually mounts into.
  **Read those; do not edit them.** If you find something that contradicts
  them, write it down for Derek to carry back to a suite session.
- Any uncommitted or untracked work in the tree (see your tool's row below).

Then form an actual view. You should be able to answer, in your own words:
what is this for, who uses it, what does it do well, where is it fragile, what
has been tried and abandoned, and what is obviously next.

## Phase 2 — Interview Derek

**This is the most valuable part of the session. Do not skip it, and do not
turn it into a blank-page questionnaire.**

Derek has said he doesn't have the full picture of what the finished tool looks
like. So don't ask him to supply it. **Draft it yourself from Phase 1, show him
your draft, and let him correct it.** Reacting to a concrete proposal is far
easier than authoring from nothing, and it is where he is sharpest.

Ask in batches, as multiple choice with your recommendation attached — that is
how he answers best. Cover at least:

- **The purpose, in two or three sentences.** Not the feature list — the
  outcome. What is different in his business or his week because this tool
  exists? Propose your version; ask him to correct it.
- **What "finished enough" looks like.** Not a roadmap — a description of the
  state at which he'd stop actively building and just use it. If he doesn't
  know, that is a legitimate answer: write down that it is open, and what the
  candidate answers are.
- **Who and what it must never do.** Every one of these tools has at least one
  hard line (real people's PII, real money, real sending). Get them stated.
- **Decisions to lock.** Present the ones you found in the history that look
  settled, and confirm each. A decision he confirms is one no future session
  re-opens by accident.
- **What's actually in use versus built-but-unused.** He knows; the code
  doesn't say.
- **The half-fixes.** Ask him directly for one or two recent changes that
  missed the point. Then find them in the history and work out what the repo
  would have needed to say for that session to have gotten it right. Whatever
  that is — write exactly that into the file.

Record his answers as he gives them. Do not save them for the end.

## Phase 3 — Write `CLAUDE.md`

One new file at the repo root. **Target 200–400 lines. Not 278 KB.** Kraken's
file has grown past the point of comfortable use — over half of it is a
shipped-work changelog that belongs in git history. Copy its *categories*, not
its size. Anything that reads like a changelog goes in `CHANGELOG.md` or stays
in the git log.

Structure:

1. **What this is** — purpose and outcome, in Derek's confirmed words. First
   thing in the file, because it is what every ambiguous request gets resolved
   against. **Structure it the way Kraken's does** — see the template below.
2. **Where it stands today** — honest state. What runs in real use, what is
   half-built, what is stubbed, what is abandoned-but-still-present. This
   section is what lets a future session propose a sensible next step.
3. **Locked decisions** — confirmed in Phase 2. Each with a one-line *why*, so
   it can be revisited deliberately rather than re-argued from scratch. Mark
   superseded decisions as superseded with a date rather than deleting them.
4. **Hard invariants** — the things that must never break. Include the "never
   do" lines from Phase 2.
5. **How to work here** — the working agreement. It must contain, adapted to
   this tool in your own words:
   - *Derek's prompts run short.* Before implementing anything non-trivial,
     restate in one sentence the outcome he's after — not the change he
     described — and say what would make it **fully** addressed versus
     partly. **When those two differ, ask before building.**
   - *Name the root cause before the fix.* If you are patching where a symptom
     appears rather than where it originates, say so explicitly and say why
     (sometimes that's the right call — but it must be a stated choice).
   - *Report honestly what was verified.* Distinguish "tested end-to-end,"
     "typechecks and unit-tests pass," and "written but not exercised." Never
     let the third read like the first.
   - *Ambiguity is a question, not a coin flip.* He has said repeatedly he
     would rather answer than unwind.
   - *End every session by proposing the next one to three steps*, ranked,
     with reasoning. This is the explicit ask: he wants the repo and its
     context to be good enough that Claude can identify the next step when his
     prompt doesn't.
   - Anything tool-specific about how to run, test, and verify it.
6. **Pitfalls** — burned-once, documented forever. Mine these from git history:
   every bug worth a fix commit has a cause, and that cause is what future
   sessions need. Each entry: what broke, why, how to avoid it. **Only real
   ones you can trace.** Do not pad this section; three true entries beat ten
   speculative ones.
7. **Reading order and key references** — what to read first in a fresh
   session, and where the deep material lives.
8. **Open questions for Derek** — anything Phase 2 left unresolved. Keep it
   short and real.

Mark anything you believe but could not confirm as **[UNVERIFIED]**. That tag
is more useful than a confident sentence, because the next session knows to
check it rather than build on it.

### The purpose statement — structure it like Kraken's

Kraken's is the model, and it is worth studying because of how *short* it is.
Roughly 120 words, no feature list, no architecture, no roadmap — and it is
still enough to resolve most ambiguous requests. Here it is in full:

> **What this app is**
>
> Sea King Capital provides two forms of financing to CPG companies:
>
> - **PO financing** — advance capital against a retailer's purchase order
>   before fulfillment. The PO is collateral.
> - **AR factoring** — advance capital against an invoice. The invoice is
>   collateral; when the retailer pays, we collect.
>
> This monorepo is the system of record. It replaces Excel. Every PO, invoice,
> advance, fee, payment, and remittance flows through it. Users: Manager
> (Admin/Operator), Client (read-only portal + advance requests), and stubbed
> Investor/Creditor roles.
>
> Derek is the founder, primary user, and a beginner developer. Favor explicit
> clarity over cleverness. Complete updated files over snippets when
> refactoring.

Six moves. Reproduce all six for your tool:

1. **The real-world activity that creates the need** — start outside the
   software. Kraken opens with what the *company* does, not what the app does.
   For your tool: what is Derek actually trying to accomplish in his business
   or his week?
2. **The domain primitives, defined in one line each, with the thing that
   matters about each** — Kraken defines its two financing products and, for
   each, names the collateral. These are the nouns the whole system
   manipulates; a session that misreads them misreads everything downstream.
3. **What role the software plays, and what it replaces.** *"This monorepo is
   the system of record. It replaces Excel."* — **this is the most load-bearing
   sentence in the file**, because naming what it replaces implies the
   condition under which it is succeeding. Get this line right above all
   others. Candidates to test with Derek: does this tool replace a manual
   process he'd otherwise do by hand, a thing he'd otherwise pay for, or a
   thing he simply couldn't do at all before?
4. **Scope as a flow list** — *"Every PO, invoice, advance, fee, payment, and
   remittance flows through it."* This is a boundary in disguise: it says what
   belongs here, and by omission what does not. Write the equivalent sentence
   for your tool.
5. **Who uses it, by role**, including roles that exist but are stubbed. Some
   of these tools have exactly one user (Derek) — say so plainly; "single
   operator, no other humans" is a real and useful constraint.
6. **Who Derek is, and what that implies for how to work here.** Kraken's
   version draws a direct consequence: beginner developer → favor explicit
   clarity over cleverness, complete files over snippets. Draw the consequence
   that fits your tool rather than copying Kraken's verbatim.

**Also consider the adjacent section Kraken keeps right after it:
"Terminology conventions" — a table of words never to use and what to say
instead** (it never uses loan vocabulary: advance not loan, fees not interest,
Client not borrower, because the legal characterization depends on it). If your
tool has vocabulary that encodes a legal, compliance, or business reality —
Harpoon's pre-offer language rules are the obvious case — give it the same
treatment. Wrong words in generated output are a real defect there, not a style
preference.

Write your draft of all six, show it to Derek in Phase 2, and record the
version he corrects — not the version you drafted.

## Phase 4 — Clean the repo

- **Resolve uncommitted and untracked work first** (your tool's row below says
  what's sitting there). For each: finish it, commit it, `.gitignore` it, or
  delete it — decided with Derek, not silently. Half-finished work in a dirty
  tree is exactly the kind of thing a later session trips over.
- Delete or correct docs that are now false. A stale doc contradicting the
  system is worse than no doc. Where something is merely out of date rather
  than wrong, date it.
- Consolidate duplicated context. If three files describe setup, one should —
  the others point at it.
- Leave dead code alone unless it is actively misleading; if it is, say so in
  the backlog rather than ripping it out today. **This session does not
  refactor.**

## Phase 5 — One canonical backlog

One file, ranked, honest. If the repo already has one, adopt and rank it rather
than starting a competing list; if items live scattered in several docs, pull
them together and leave pointers.

Each item: what, why it matters, and roughly what "done" means. Include the
things Phase 1 found and Phase 2 confirmed — especially anything you suspect is
a lingering half-fix. Mark what is genuinely next versus someday.

## Phase 6 — Close

Commit with a real message (Derek reads the log). Then tell him, in a few
sentences: what you found that surprised you, what you wrote down, what you
could not verify, and the next one to three steps you would take — ranked, with
reasoning. That last part is the muscle this whole session is meant to build.

## Ground rules

- **No feature work.** If you find a bug, write it in the backlog. If it is
  dangerous, say so immediately and let Derek decide.
- **Nothing in production, nothing in another repo.** Read the suite docs;
  don't edit them.
- Evidence over assumption. State what you found before what it means.
- Ask when unsure. That instruction is the whole point of the session — model
  it while you are writing it down.

## Known starting points

Read your own tool's row. The rest are context for how the estate fits
together.

**MANIFEST** (`manifest/`) — Derek's personal rolodex; per-user by design, one
instance per person, never shared. Deployed to the `seaking` Supabase project,
schema deployed and empty, awaiting his first thirty relationships. `README.md`
is the deep context; also `SETUP.md`, `LOCAL.md`, `docs/`. Clean tree.
`npm run doctor` is the diagnostic and prints a fix line per failure — that
pattern is worth noting in the file. **Pitfall to record, it cost weeks:** the
local Supabase stack and the deployed `seaking` project are separate auth
realms; a password set on one does nothing on the other, and `.env.local`
carries both configs with one commented out. "Sign-in works" was recorded as
true while sign-in was impossible on the deployed project. Two deliberate
non-configurations: Google OAuth stays off until after the thirty relationships
are entered, and `ANTHROPIC_API_KEY` is unset (quick capture falls back to a
manual form).

**Plunder** (`plunder/`) — nightly event-sourcing and scoring engine for
business development. `README.md` carries M-numbered milestones; `Backlog.md`
already exists and is good — adopt it as canonical rather than replacing it;
`NewEventSources.md` holds candidate sources. **Untracked at root:**
`.review-complete`, `codebasereviewfeatures.md`, `overnight-review-prompt.md`,
`overnight-review.ps1` — decide each with Derek. **Write down loudly:** the
nightly GitHub Actions workflow runs `pnpm worker migrate`, so **CI
auto-applies migrations to the shared `seaking` database every night** — that
is this repo's deploy path, and it is not obvious from anywhere in the repo
except a workflow file. Also: GitHub repo secrets hold a direct Postgres
credential to `seaking`. The workflow files' inline comments are unusually good
and are a model for the tone this file should carry. **Incoming from the suite
side:** Plunder's tables currently grant everything to any authenticated user
of the shared project; a membership gate is being added before any second
person gets an account. Don't design against it.

**Harpoon** (`harpoon/`) — award-triggered govcon origination agent; local
Docker, deliberately bound to 127.0.0.1 because its database holds lead PII.
**The highest-consequence tool outside Kraken**: real PII, Twilio, its own
Gmail sending, compliance rules enforced in code. Docs are already rich —
`docs/WORKFLOWS.md` (read §5, the safety model), `docs/apis.md`,
`rubric_critique.md`, `design_capability_letter.md`, `docs/reviews/`. **Two
uncommitted modified files** (`harpoon/warmup.py`, `tests/test_warmup.py`) —
resolve these first; they may be half-finished work. The §5 safety model
(human gate, dry-run default, compliance-as-code, kill switch, permanent
suppression, PII tokenization before third-party LLM calls) should become
**locked decisions and hard invariants**, because those are exactly the things
a future session could quietly undo. Note also: the handoff to the document
engine is built on Harpoon's side, its webhook URL is unset, and the receiving
end doesn't exist yet — a real half-built seam worth writing down.

**Deepwatch** (`deepwatch/`) — deterministic conditional document-assembly
engine for deal documents. `README.md` is **one line**; the real record is
`BUILD_LOG.md` (dated, phase by phase, through a v5 rewrite) plus
`docs/SPEC.md`. Clean tree. Its own log calls the engine feature-complete. It
has a local single-page UI served by a stdlib HTTP server. Lowest external
risk of the four — no PII leaving, no production surface, no money. The README
is the obvious gap; the harder question for Derek is what "in use" would even
mean for this tool, since it is finished but not yet part of a daily workflow.
