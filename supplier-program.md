# Supplier Partner Program

**Status: intake page built 2026-09-26** in `seakingcapital-website`: a new
`suppliers/` folder plus small homepage changes. **Merged to `main` on
2026-09-27 (`705e524`) and not yet deployed.** Derek publishes by cPanel upload
(upload set in that repo's README → "Deploying changes"). Partner requests have
had their own Pabbly workflow since 2026-09-27 (`3bb9640`). **Nothing Kraken-side was
touched; the freeze holds.** Site-level how-and-why lives in the website repo's
`README.md`. This file records the program, the decisions behind it, and what
the Kraken side will need.

## What the program is

Sea King's PO-financing clients are businesses that sell to reputable buyers.
Those buyers can be retailers, consumer brands, or industrial and healthcare
companies (Derek, 2026-09-26: e.g. a supplier to Grainger or P&G is as welcome
as one selling to a national retailer). The clients' **suppliers** (co-packers,
manufacturers, packaging and ingredient suppliers) are constantly asked by them
for net terms, or see orders trimmed to what the client can pay in cash. The
program turns suppliers into a referral channel:

1. **Refer.** The supplier mentions financing on quotes and during client
   onboarding, using their **unique sign-up link** ("Financing available for
   qualified orders through Sea King Capital: [unique link]"). Adding the link
   to customer emails is an optional extra to spread the word. Sea King does not
   send those emails.
2. **Customers apply directly** through the supplier's link.
3. **Get paid.** On qualified orders Sea King **pays the supplier directly for
   their work, including down payments**, and the customer repays Sea King.
4. **Earn commissions.** The supplier earns a **percentage of the profits on
   business they refer**, paid automatically every month, at no cost and with
   no work.

(Step names and wording are Derek's, 2026-09-26.)

Derek's pitch pillars (2026-09-26): it **boosts the supplier's sales**, adds a
**new line of income**, and **increases payment certainty while reducing the
need to offer net terms**, all with **zero effort**.

**Source material:** the one-pager series in Derek's Downloads,
`Sea_King_Capital_Supplier_Partner_Program_v02…v07.pptx` (2026-09-24; v07 also
exists as a PDF, and a `v01.docx` precedes them). How the claims evolved matters
for the web copy:

- **v04 → v06** removed the retailers' names (Walmart / Kroger / Costco) and
  restated the proof figures as amounts **paid to suppliers**: $1.47M, $948K
  and $66.5K. v04 had given total financed instead: $1.8M, $1.3M, $108K.
- **v06 → v07** replaced "You're paid up front" and "Get paid up front… No
  invoice to chase" with "We start paying you here" (at production) and "More
  certainty you get paid… **starting with your deposit**".
- **Web page, 2026-09-26 (Derek):** payment is now worded "for your work…
  including down payments", starting when the order is placed. The hero graphic
  was redrawn as two lanes: with Sea King the dot sits under **Order** (the down
  payment); on net terms it sits under **Invoice paid**, if on time. Derek found
  v07's "We start paying you here" (at Production) and the unanchored "On net
  terms, you're paid here" ambiguous.
- **v03** carried track-record stats ($53M+ funded since 2021 · 2,000+ POs
  financed · 50+ clients served) that later versions dropped. Derek confirmed
  them on 2026-09-26 as accurate and publishable.
- The v07 QR code encodes `https://www.seakingcapital.com` (decoded 2026-09-26),
  so supplier scans currently land on the **borrower** homepage.

## What exists today (2026-09-26)

- **`seakingcapital.com/suppliers/`** (repo `seakingcapital-website`, folder
  `suppliers/`). It is structured section-for-section on
  [rentwithcosign.com/landlords](https://www.rentwithcosign.com/landlords),
  Derek's reference. Sections, in order:
  1. Hero with a two-lane *when you get paid* chart.
  2. Four benefit cards plus a "Zero effort. Zero cost." band. They come
     first per Derek (2026-09-27), because they answer "why is this good for us?".
  3. An interactive *Challenges we solve → Solutions we provide* component.
  4. The four steps: Refer → Customers Apply Directly → Get Paid → Earn Commissions.
  5. Real orders.
  6. The v07 *when to send a customer our way* checklist, generalised from
     "retailer" to "buyer", ending "…we can help."
  7. The track record ("We have driven positive results with suppliers all
     over the country."), moved here from under the hero as closing proof.
  8. FAQ.
  9. Request-to-partner form and call CTA.
- **Request-to-partner form → its own Pabbly workflow**, "Supplier Partner
  Requests" (since 2026-09-27), tagged `form: "supplier_partner"`. Partner
  requests therefore never enter the funding workflow and its paid
  application steps. Fields:
  name, company, optional role, email, phone, optional supplier type, typical
  order size, "has Sea King already paid you on a customer's order?", website
  and notes. **No banking fields, by design.**
- **Homepage changes:**
  - A "For Suppliers" link in the nav and footer.
  - The funding form now sends `form: "funding"` and `partner_code`.
  - A partner-referral note appears when a visitor arrives on a partner link.
  - Both forms have a honeypot and a minimum-fill-time check.
  - `?v=` cache-busting on the CSS/JS links.
- **QR code** `suppliers/qr-suppliers.svg` / `.png` (error-correction H, brand
  navy on white) encoding `https://seakingcapital.com/suppliers/`, for the next
  one-pager version. Verified by decoding.
- **No accounts on the static site.** "Request to partner" is a form
  submission. Derek follows up, sends the quote wording, customer email and
  unique link, and provisions the Kraken supplier profile by hand.

## Partner codes and attribution

- **Link:** `https://seakingcapital.com/?partner=CODE#request-funding`.
- **Code:** 10 random characters from `0123456789ABCDEFGHJKMNPQRSTVWXYZ`
  (Crockford-style, no look-alikes), generated with Python `secrets`. The
  one-liner is in the website README. **Derek's requirement (2026-09-26): not
  guessable**, because a tagged application starts a process that costs money.
- **What the site does:** it checks the *format* only (`^[0-9A-Z]{8,16}$`,
  upper-cased), carries the code through the visit in `sessionStorage`, and
  sends it as `partner_code`.
  - **Why not a cookie or localStorage:** `privacy.html` §2 promises no
    tracking technologies. A longer attribution window needs a privacy-policy
    change first.
- **What it cannot do:** know whether a code was really issued. That lookup
  belongs in Pabbly (issued-codes list) now, and in Kraken later. An unknown
  code means untagged.
- **Codes are unguessable, not secret.** They are printed on quotes, so they
  are *attribution*, not access control.

## Spam and cost control

Derek asked (2026-09-26) whether there is a better way than random codes to
stop spammers, since applications carry cost. The answer given:

- **Random codes protect attribution integrity, not the form.** The funding form
  accepts submissions without any code. And the Pabbly webhook URL is public in
  the page's JavaScript, so a bot can POST directly and skip every browser-side
  check.
- **Built now (browser side, zero friction):** a honeypot field, and a
  3-second minimum from page load to submit. They stop simple bots only.
- **Recommended, in order** (none built):
  1. **Never let an unverified web submission trigger paid work.** Put a free
     gate first: human triage, or an email-confirmation step.
  2. **Cloudflare Turnstile verified inside Pabbly.** An HTTP step to
     `siteverify` plus a filter. It is server-side, so it holds against direct
     POSTs, and it needs a free Cloudflare account (DNS stays at GoDaddy).
  3. **Look up `partner_code` against issued codes in Pabbly.**

## The Kraken weave-in (Derek's build; not suite work while the freeze holds)

Derek, 2026-09-26: *"I will create a corresponding 'supplier' profile in the
Kraken client-side portal for them to view commissions and manage their bank
routing information."* Nothing like it existed in Kraken as of the 2026-08-06
discovery pass. What the portal side will need, as seen from the intake:

- **Supplier entity and portal role, distinct from Client.** A supplier sees
  only their own commissions and payout details, never a client's financials.
  Kraken's five-role, grant-scoped model is in discovery §2. This is the same
  shape as the shelved broker role ([broker-program.md](broker-program.md)).
- **Partner code on the supplier record:** unique, issued at provisioning. It
  is the source of truth for the Pabbly lookup and for any "Partner sign in"
  link added to the page later.
- **Attribution:** a funding request carrying `partner_code` should make the
  resulting client or deal record `referred_by` that supplier. Until then this
  is manual, from the Pabbly notification.
- **Commission ledger:** accrual per funded deal, then payable, then paid
  monthly, with a per-supplier rate. The base is an open question (see [ASK]
  #1). It depends on where deal-level revenue lives: Kraken's GL today, the
  accounting service under Arc A (discovery 2026-08-12).
- **Payout bank details, portal-only.** The page now publicly promises
  suppliers that Sea King **never asks for or changes bank details by email or
  phone**. The change protocol in Deepwatch's `docs/supplier-verification-spec.md`
  (Step 5: portal-only changes, verification re-run, callback to the
  previously verified phone, hold period) is a ready-made model.
- **One supplier record, two jobs.** The suppliers Sea King *pays* on funded
  POs, and verifies as payees per that spec, are often the same companies it
  now pays *commissions* to. Design the supplier profile once for both: payee
  verification and partner commissions.

## [ASK] before launch / first commission

1. **Commission terms.** The base is now stated on the page: *a percentage of
   the profits on business you refer*, paid monthly (Derek, 2026-09-26). Still
   open:
   - The default rate.
   - What "profits" means. The broker program hit the same question: profit
     vs. collected revenue net of chargebacks (see
     [broker-program.md](broker-program.md) [ASK] #1).
   - How profits are shown to the supplier in the portal.
   - Whether there is a written partner agreement. The broker program had a
     template ([broker-commission-agreement.docx](broker-commission-agreement.docx));
     there is nothing equivalent for suppliers.
2. **Counsel:** does the *customer* need to be told that the supplier is paid
   for the referral? Commercial-financing disclosure rules vary by state.
   Counsel should also review the page's public commitments, for example
   "never ask for or change bank details by email or phone".
3. **`partnerships@seakingcapital.com`.** It is published on the page and in
   v07. Its existence and routing were **not verified** this session.
4. **Pabbly.** The partner workflow exists (2026-09-27) and Derek is adding
   its email step. Still to do: map `partner_code` in the funding workflow
   before the first partner link goes out. Optionally, look up issued codes.
5. **Spam gate and Turnstile:** yes or no (above).
6. **Attribution window:** one visit today. Anything longer is a
   privacy-policy change.
7. **One-pager v08:** swap in the new QR code (`suppliers/qr-suppliers.svg`).
