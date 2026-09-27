# Broker / ISO referral program

**Status: SHELVED 2026-09-14.** The intake page shipped and was revised the
same day, then Derek decided not to proceed; the `seakingcapital-website`
working tree was rolled back to its pre-2026-09-14 state (nothing had been
committed or pushed, so GitHub never changed). The commission-agreement
template ([`broker-commission-agreement.docx`](broker-commission-agreement.docx))
still exists here as reference. This file is kept as the record of the design
in case the program is revisited — everything below describes what *was*
built and intended, not anything currently live.

## What the program is

Referral partners (MCA-style ISOs and brokers) sign up with Sea King, sign a
simple commission agreement, and hand off PO-financing and factoring deal
opportunities. **The submission is a handoff point**: from the moment a deal
lands, Sea King runs all diligence requests and all client conversations —
the broker never packages a file or chases documents. The broker is paid if
the deal funds; if it dies, nobody owes anybody anything.

Target flow (Derek, 2026-09-14): sign up as partner → sign the commission
agreement → submit deals through the broker portal → the submitted company
appears in their broker portal, where they track deal status and commissions
earned.

## What exists today (2026-09-14)

- **`seakingcapital.com/brokers/`** on the GoDaddy marketing site (repo
  `seakingcapital-website`, folder `brokers/`). Content: handoff-model pitch,
  commission terms, an FAQ, and a combined **deal-submission /
  partner-sign-up form**. *The client document checklists that shipped in the
  first cut were removed the same day at Derek's direction — diligence is
  Sea King's job, so the page no longer asks brokers about documents at all.*
- **Form → Pabbly**: posts JSON to the *same* Pabbly webhook as the main
  funding form, tagged `form: "broker"` + `submission_type: "deal" |
  "registration"`. A dedicated Pabbly workflow can be swapped in at
  `brokers/brokers.js` → `WEBHOOK_URL`. Deal fields: client legal name,
  industry, financing need, estimated amount, optional monthly revenue /
  client contact / summary, and a required broker authorization checkbox.
- **Commission agreement template**:
  [`broker-commission-agreement.docx`](broker-commission-agreement.docx),
  adapted from a third-party sample Derek supplied (a United Capital ↔
  ThinkBOC factoring commission agreement). Structure kept: protected-list
  mechanics, funder-owns-all-diligence, non-exclusive, prevailing-party fees,
  1-year auto-renew with 30-day no-cause termination, commissions survive
  termination + 180-day post-termination tail. Adapted: Sea King as funder
  (PO financing + factoring), rate as a fill-in **capped at 15% of Net
  Revenue**, explicit "nothing due on deals that don't close and fund",
  broker-side quirks removed (the sample's broker-consent-for-PO-financing
  clause), typos fixed. Fill-in blanks: Sea King's state of organization and
  principal office, governing law / venue, broker details, per-broker rate,
  Derek's title. **Not yet reviewed by counsel.**
- **QR code** (`brokers/qr-brokers.svg` / `.png`, error-correction H) encoding
  `https://seakingcapital.com/brokers/` for Derek's business card.
- **No accounts on the static site.** "Sign up" is a form submission; Derek
  sends the agreement to countersign and provisions the Kraken-portal broker
  profile by hand.

## Commission model (revised 2026-09-14, second round)

- **No signing / upfront commission.** The first cut's "2% of initial funding
  at signing" was removed at Derek's direction the same day it shipped.
- **Up to 15% of profits**, with each broker's actual rate set in their
  commission agreement (the template caps at 15%). Paid as collected, within
  30 days of Sea King's receipt of the underlying revenue.
- **Funded deals only**: deal dies → no commission, and the broker owes
  nothing either way.
- Every partner signs the same simple agreement at sign-up; a per-broker rate
  (≤15%) replaces the earlier "master rules unless broker-specific agreement"
  framing.

**[ASK] before the first agreement is signed:**

1. **"Profits" vs "Net Revenue"** — Derek's words say *profits*; the sample
   agreement (and therefore the template) defines the base as *all earned and
   collected revenue net of chargebacks and losses*, which is a revenue
   measure, not a profit measure. Decide the intended base and align the
   template §4 and the page copy. (The page currently says "profits.")
2. The fill-in blanks: Sea King's state of organization + principal office,
   governing law and venue, Derek's signing title.
3. Default rate to offer a new broker (the template is a blank ≤15%).
4. No time limit on the commission tail exists in the template (it pays for as
   long as revenue is received, like the sample) — the earlier 12-month
   framing is gone. Confirm that is intended.
5. Attorney review of the template before first use.

## The Kraken weave-in (future; not suite work while the freeze holds)

Derek's stated plan: a **'broker' profile type in the Kraken client portal**
(`portal.seakingcapital.com`). Target behavior, in his words: brokers submit
customer info via the portal; the company shows in their broker portal; they
track deal status and commissions earned. None of this existed in Kraken as of
the 2026-08-06 discovery pass. What the portal side will need:

- **Broker entity** distinct from Client, with its own portal role (Kraken's
  five-role model and grant-scoped authorization are in discovery §2; a broker
  must never see client financials — only their own submissions' status and
  their own ledger).
- **Portal deal submission** by brokers — the handoff form as a portal
  feature, creating a prospect record attributed to `broker_id`. Until then,
  the static page's form is the intake and attribution starts as a manual
  entry from the Pabbly notification.
- **Deal status surface**: the submitted company visible in the broker's
  portal from handoff through funded/dead.
- **Commission terms per broker**: rate (≤15%) from their signed agreement, on
  the agreed base (see [ASK] #1).
- **Commission ledger**: accruals as revenue/profit is collected on referred
  accounts, payable/paid states — what the broker actually logs in to see.
  Depends on where account-level profit lives (today Kraken's GL; under Arc A,
  the accounting service — see discovery 2026-08-12).

Until then the operating loop is manual: Pabbly notification → Derek sends the
agreement / provisions the portal profile → enters and tracks the deal in
Kraken → pays commissions per the agreement.
