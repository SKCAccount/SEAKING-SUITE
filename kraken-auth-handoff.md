# Handoff → Kraken session: close signup, custom SMTP

Two fixes were approved during suite discovery on 2026-08-03 and parked behind
the suite-side freeze. On 2026-08-07 Derek moved them to the Kraken workstream
so the suite session stays hands-off production. **This file is the launch
prompt.** Copy everything below the line into a fresh Claude Code session
opened at `C:\Users\stink\Claude Projects\sea-king-capital-servicing-engine`.

Suite-side context this hands over: discovery.md §2.3 (the two findings, with
evidence), §2.5 (#5 — the auth-config checklist assembled from Kraken's own
burn history), §10a (the approvals). Whatever gets configured here must be
re-created on `seaking` at the port's K4 — so the record this session leaves
behind is load-bearing later.

---

You are working on Kraken — the Sea King Capital servicing engine, the
production PO-financing / AR-factoring system of record — for Derek
(derek@seakingcapital.com). This session has one job, described at the bottom.
Read everything above it first.

## Scope: exactly two changes, both in the Supabase dashboard

1. **Close signup.** `DISABLE_SIGNUP` is currently `false` on the production
   project (`ucfyfnwkxzryywuomool`) — a public financial system is accepting
   self-registration. Approved decision, Derek 2026-08-03: **accounts exist
   only when an admin creates them. Signup is never open, anywhere.**
2. **Custom SMTP for auth email.** `SMTP_HOST` is empty, so every auth email —
   including the real external Client's password resets — rides Supabase's
   built-in free-tier sender (a couple of messages an hour, frequently
   spam-filed). Approved: **Resend**, using the key already in the portal's
   env, sending as `no-reply@seakingcapital.com`.

Nothing else. No schema changes, no feature work, no refactors. If you find
something else broken, write it in `docs/BACKLOG.md` and keep going.

## Read before touching anything

Read in this order, and read *for these two changes* — not as a general
orientation pass:

1. **`CLAUDE.md`** — all of it, but stop and study **"Supabase dashboard
   configuration (NOT in code)"**. It documents the Site-URL fallback trap,
   the wildcard-per-origin redirect allowlist, and the customized Reset
   Password template, each written up because it caused a real
   Client-facing bug. Also read "Decisions already locked" and the DB/SQL
   pitfalls list — several bear on auth.
2. **`ARCHITECTURE.md` §2 (Authentication flow)** — the two email-link shapes,
   the end-to-end invite and password-reset walkthroughs, role resolution,
   and its own "Required Supabase Dashboard config" subsection. **Expect that
   subsection to be stale** (see "Docs" below) — read it as a thing to fix,
   not a source of truth.
3. **`packages/auth/README.md`** and **`packages/notifications/README.md`** —
   the session helpers and the app-layer Resend path. Auth-layer SMTP and
   app-layer Resend are different things sharing one vendor; know which is
   which before you change either.
4. **`apps/client-portal/`** — the forgot-password flow and the consent gate.
   The portal is customer-facing; its reset flow must keep working, and it is
   the surface where a mistake reaches an actual client.
5. **`apps/jobs/README.md`** and `supabase/functions/` — the deployed edge
   functions send via Resend REST with a function secret. Understand how that
   key is provisioned before you introduce a second use of the same vendor.
6. **`docs/BACKLOG.md`** — the canonical work list; check whether either fix
   is already tracked there.

Then read anything the above points at that touches auth, email, or user
provisioning. Prefer reading one more file to assuming.

## The traps, from Kraken's own history

These are documented in `CLAUDE.md` because they already cost real bugs.
Verify each still holds before and after your changes:

- **A non-allowlisted `redirectTo` does not error.** Supabase silently
  discards it and falls back to the **Site URL** — so a portal-side
  misconfiguration lands Clients on the *Manager* sign-in with no error
  anywhere. Matching is per-URL and scheme-exact: a bare
  `https://host/auth/callback` entry does **not** match
  `…/auth/callback?next=/auth/reset-password`, which is exactly what
  `resetPasswordForEmail` sends. Hence **one wildcard entry per origin**.
- **The Reset Password template is deliberately customized** to the
  `token_hash` / OTP flow. The default `{{ .ConfirmationURL }}` uses PKCE,
  which needs the code-verifier cookie from the browser that *requested* the
  reset — so it dies when the email is opened on a different device, which is
  the common case. The template and the `?next=` in
  `apps/*/src/app/forgot-password/forgot-password-form.tsx` are **load-bearing
  in both directions**: they change together or neither. Other templates
  (invite, etc.) use `{{ .ConfirmationURL }}` and work — leave them alone.
- **Never add `localhost` to the production project.** Dev and prod share one
  Supabase project, so a localhost redirect entry *is* a production entry: the
  anon key is public, so anyone could trigger a reset to any address with a
  localhost target and deliver a live recovery token to whatever is listening
  on the recipient's machine.
- **`node docs/diagnostics/verify-auth-redirects.mjs`** probes every origin ×
  bare / `?next=` / deep-path against the live project in about ten seconds.
  Run it before you change anything (to capture the baseline) and after.

## Downstream surface — check before changing, not after

Closing signup and swapping the mail sender both have reach beyond their own
toggle. At minimum, establish the answer to each of these from the code:

**For closing signup:**
- Does anything call `supabase.auth.signUp(...)`? Grep both apps and every
  package. If a real path depends on it, that path breaks the moment signup
  closes — find it first.
- The invite flow uses `inviteUserByEmail` (admin API, service role). Confirm
  from the code and from Supabase's behavior that it is unaffected by
  `DISABLE_SIGNUP` — the whole provisioning model depends on that being true.
- Any OTP / magic-link call sites: confirm `shouldCreateUser: false` is set
  (belt-and-braces) or that the call can't create a user.
- The **System service account** (fixed UUID `00000000-…-000000000001`) and the
  portal-test-user tooling (`docs/diagnostics/delete-portal-test-user.mjs`) —
  understand how those users get created so you know whether closing signup
  affects re-creating them.

**For custom SMTP:**
- Is `seakingcapital.com` already verified in Resend? The portal and the edge
  functions already send through it, so probably yes — confirm rather than
  assume, and confirm `no-reply@` specifically is a usable sender.
- One key or two? Decide deliberately whether auth-layer SMTP reuses the
  portal's existing Resend key or gets its own. A separate key means a leak or
  a rotation on one side doesn't take out the other; note the choice and why.
- **Supabase's own email rate limit is a separate setting from SMTP.** Enabling
  custom SMTP does not by itself lift the auth rate limit — check it and raise
  it to something sane, or you will have swapped a slow sender for a
  rate-limited one and think you fixed the problem.
- Every auth email changes sender at once: invite, recovery, magic link, email
  change. Make sure the sender name/address reads correctly to an external
  Client, not just to Derek.

## Execution order, with a gate after each step

Production has one real external Client on it. Do not batch these.

1. **Baseline.** Run `verify-auth-redirects.mjs`; record the current auth
   config (signup flag, SMTP fields, Site URL, allowlist, template bodies)
   verbatim into the session notes *before* editing. This is also the rollback
   card.
2. **Custom SMTP first**, signup second — SMTP is the one with a live risk
   attached, and doing it first means the reset path is already healthy when
   you start restricting account creation.
   **Gate:** send a real password reset to an external address and complete it
   **cross-device** — request it on the desktop, open it on the phone. That
   single test exercises the SMTP change, the template, the allowlist, and the
   PKCE trap at once. Delivery in seconds, not hours.
3. **Close signup.**
   **Gate:** a self-signup attempt is refused; then invite a throwaway user
   end-to-end (invite → email → set password → sign in) to prove provisioning
   still works, and clean the user up afterward.
4. **Re-run `verify-auth-redirects.mjs`** and confirm it matches the baseline
   except where you intended change.
5. **Confirm the real Client's path still works** — the portal forgot-password
   flow specifically, since that is the customer-facing surface.

Both changes are dashboard toggles, so rollback is flipping them back. Say so
plainly in your notes, with the exact prior values.

## Docs — update as you go, and delete what these changes make false

This is not a cleanup pass at the end. Update the docs in the same commit as
the change they describe.

**Update:**
- **`CLAUDE.md` → "Supabase dashboard configuration (NOT in code)"** — the
  authoritative home for this. Record the SMTP provider, sender address, which
  key, the rate-limit value, and that signup is closed. Keep the trap writeups;
  they stay true.
- **`ARCHITECTURE.md` §2** — its "Required Supabase Dashboard config"
  subsection currently tells the reader to allowlist
  `http://localhost:3000/auth/callback` and `http://localhost:3001/auth/callback`
  and to set Site URL to localhost for dev. That **directly contradicts**
  `CLAUDE.md`'s "Do NOT add localhost entries to the production project," which
  is the correct rule and explains why. Fix the contradiction — one rule, one
  home, cross-referenced from the other.
- **`docs/BACKLOG.md`** — close whatever these two fixes resolve.
- **`docs/NEXT_SESSION_PROMPT.md`** — the session-startup doc; refresh its
  state summary.
- **`docs/MANAGER_GUIDE.md`** — if the operator-visible behavior of invites or
  resets changes (sender identity, timing), say so there.
- **`packages/notifications/README.md`** — if auth SMTP now shares the vendor
  or the key with app-layer email, note the relationship and the boundary.

**Delete or strike, don't leave lying around:** any statement anywhere in the
repo that says or implies signup is open, that auth email is on the Supabase
built-in sender, that password resets are rate-limited by the free tier, or
that a Manager must create accounts some other way because signup exists. Grep
for `signup`, `SMTP`, `free tier`, `built-in`, and the Resend key names, and
read every hit. A stale doc that contradicts the system is worse than no doc —
if a line is now false, remove it rather than appending a correction beside it.

**And record it for the port.** The suite's Kraken port has to re-create this
exact configuration on the `seaking` project at K4 — the SMTP settings, the
sender, the rate limit, the signup flag, the allowlist shape, the template
bodies. Whatever you write in `CLAUDE.md` is what that future session will work
from, so write it as a configuration you could hand to someone rebuilding it
from scratch. If you learn anything that changes the picture for that port, add
it to `docs/BACKLOG.md` under a clear heading so it survives.

## Ground rules

- **This is production, with a real external Client on it.** Verify before and
  after each step; never batch the two changes; state plainly what you tested
  and what you did not.
- Ask before assuming — Derek would rather answer a question than unwind a
  production auth change.
- The house style holds: evidence over assumption, state what was found before
  what it means, small focused commits with detailed messages (Derek reads the
  log), and don't re-litigate the decisions in "Decisions already locked."
