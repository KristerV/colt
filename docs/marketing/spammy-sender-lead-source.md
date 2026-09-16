# Lead source: single-sender bulk-blast domains as prospects

> **Status: idea, validated on a 800-domain sample 2026-09-16. Not built into the product.**
> Captured so the finding isn't lost. Nothing here is wired into ingest/enrichment yet.

## The idea

We want to find companies whose email sending setup is weak — no real deliverability
infra, no personalization, no multi-inbox warmup — because that's a warm pitch for
"we'll fix/replace how you send." Started from "can we find .ee domains that are
blacklisted for spammy marketing," which turned out to be the wrong signal.

## What didn't work

- **Public blacklists** (Spamhaus DBL, SURBL) — checked all 800 `market = :ee` companies
  in prod that have both a `website_url` and a `persons.email` (i.e. we already have a
  contact). **Zero hits.** Blacklists catch domains that got caught sending literal spam
  or hosting abuse — that bar is much higher than "annoying marketing," so this dataset
  never trips it in practice.
- **Google Postmaster Tools** — not usable at all without the domain owner's cooperation
  (needs DNS/HTML verification). No public lookup exists for a third party's Gmail-side
  reputation.
- **Honeypot email seeded into Apollo/other lead-gen platforms** — would work (you'd see
  who buys the data and mails it) but too slow/low-volume to be worth the effort: weeks of
  passive collection for a small sample, not a scannable list.
- **Root-domain SPF for dedicated cold-outreach tools** (Instantly, Smartlead, Lemlist,
  Apollo, Reply.io, Outreach, Salesloft, etc.) — **zero hits** across all 800 domains.
  This isn't absence of cold outreach — serious cold-email senders deliberately keep
  those tools off the root domain's SPF, sending instead from a dedicated subdomain
  (`mail.`, `hello.`, `go.`) or a separate throwaway domain, specifically to protect the
  main domain if it gets burned. Root-domain SPF misses exactly the senders doing this
  properly. A subdomain-probe pass (`mail.`, `hello.`, `outreach.`, `go.` + likely
  variants) would be needed to catch that segment — not done yet.

## What did work — SPF-visible bulk marketing tools

Checked SPF TXT `include:` entries across the same 800-domain `.ee` sample for known
bulk/marketing ESPs (as opposed to cold-outreach sequencers):

| Platform | Hits (of 800) |
|---|---|
| Smaily | 116 |
| Mailchimp (`mcsv.net`) | 28 |
| Mailchimp Mandrill (`mandrillapp`) | 15 |
| Mailjet | 13 |
| HubSpot (`hubspotemail.net`) | 9 |
| Sendinblue/Brevo | 4 |
| GetResponse, Mailigen, Pardot, Scoro, Emarketeer | 1–2 each |
| **Total distinct domains hit** | **~140** |

**Why this is the actual signal:** all of these platforms share the same shape as
Smaily — single/few sending IPs or a shared pool, one "from" identity per campaign,
blast-style sending, no per-rep warmed-up inbox rotation. None of them give a domain
real multi-inbox cold-outreach infrastructure. (HubSpot is the one partial exception:
its Sales Hub *sequences* send through the rep's own connected Gmail/Outlook inbox, not
through `hubspotemail.net` — so a HubSpot SPF hit only tells us about their marketing-
blast side, not sales-rep-level outreach. Still counts as the same weak-infra signal.)

So: **any of these ~140 domains is a company doing non-personalized bulk email from a
single sender identity** — a plausible pitch target both because that setup is more
exposed to reputation risk over time, and because it's a legible "you're doing this the
old way, here's the better way" story.

Caveat: this reasoning is from general knowledge of how these ESPs work, not verified
against current vendor docs. Worth a quick doc check before this goes into a pitch deck
or an automated scoring pipeline.

## Also checked, weaker/orthogonal signal

**SPF/DMARC posture** (same 800-domain sample) — a proxy for "fragile setup" generally,
not specifically "doing sales marketing":

| Signal | Count | % |
|---|---|---|
| No SPF record | 47 | 6% |
| No DMARC record at all | 294 | 37% |
| Neither SPF nor DMARC | 44 | 5.5% |
| DMARC `p=none` (monitor only) | 235 | 29% |
| DMARC `p=quarantine` | 170 | 21% |
| DMARC `p=reject` | 100 | 12.5% |

~66% (no DMARC + `p=none`) have no real enforcement — useful as a secondary qualifier
layered on top of the ESP-hit list, not a standalone lead source.

## Next steps (not started)

- Widen beyond the 800-domain sample (drop the "has a contact" requirement, pull the
  full `.ee` registry) to size the real opportunity.
- Subdomain probe (`mail.`, `hello.`, `go.`, etc.) to catch domains running cold-outreach
  tools properly off-root — currently invisible to this method.
- Decide whether this becomes an actual enrichment signal (a company attribute / ICP
  filter) or stays a one-off prospecting list.
