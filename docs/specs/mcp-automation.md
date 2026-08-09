# MCP automation — "run my whole campaign from Claude"

> **Status: RESEARCH / proposal (2026-08-09).** Not built. This doc answers: what
> stops Claude from setting up an entire campaign in one shot today, how to expose
> Liid over MCP, how Claude authenticates, and the "Claude creates the account, the
> user only clicks a card + inbox link" flow. Read alongside `docs/spec.md` §2 (auth),
> `docs/specs/contact-acquisition.md` (rungs), `docs/sending-jit-approval-plan.md`
> (the pull-based send loop), and `docs/sales-funnel.md`.

## 0. The goal in one line

> "Client logs in, enters a card. After that I tell my Claude *sell this to these
> people* and Claude does the rest — pulls contacts, sets filters, writes the
> sequences, connects sending — and the client comes back from vacation to replies."

Two things have to be true for that: (a) **every step must be callable by a machine**,
not just by a human clicking through LiveViews; and (b) **the steps must not hard-block
each other** so Claude can lay the whole thing down in one pass even before any contact
exists.

Good news up front: **the domain is already almost entirely built for this.** Nearly
every step is already an Ash *code-interface* function (see the inventory in §5). What's
missing is not domain logic — it's an **MCP surface**, a **machine auth path**, and the
removal of a couple of **ordering assumptions** baked into the LiveView wizard.

---

## 1. What actually stops "one-shot setup" today

The pipeline the user pictures is: `create campaign → ICP + rungs → market/filters →
target count → (pay) → enrich → contacts appear → pitch → variants/sequences → connect
inbox → auto-approve → send → replies → sales funnel`. Walking the code, here are the
real blockers, in order of how much they hurt.

### 1a. There is no programmatic surface at all (the big one)
Everything is a LiveView form. The router's `:api` pipeline exists but is **commented
out** (`router.ex:22-26`, `router.ex:168-170`), and there is **no JSON API, no MCP
endpoint, and no machine token**. `tidewave` is wired (`endpoint.ex:32`) but it's a
**dev-only** introspection MCP, not a product surface. So today Claude literally cannot
call anything — it would have to *drive a browser*. This is the thing to fix first, and
§2–§4 are how.

### 1b. Auth is magic-link only — no machine identity
`Colt.Accounts.User` has exactly one sign-in strategy: `magic_link` (`user.ex:25-35`).
Every request's actor comes from `load_from_session` / a browser cookie. There is **no
bearer/API-key path**, so even if we mounted an endpoint, an autonomous Claude has no
way to *be* a user. §3 adds the `api_key` strategy.

### 1c. Two unavoidable human-in-the-loop redirects
These are **external** and can't be fully automated away — but they *can* be reduced to
a single link the user clicks:
- **Payment.** Enrichment is paywalled: `filters_live.ex:177-178` redirects a non-`paid?`
  user to `/pricing`; `target_live.ex:137` and `write_live.ex:272` gate on
  `User.paid?/1`; `CapacityGuard` (`campaign/changes/capacity_guard.ex`) caps the target
  at the plan's remaining monthly capacity. Payment is **Stripe hosted Checkout**
  (`billing_controller.ex` → `CheckoutCreate`), i.e. a redirect to Stripe. Claude can
  *generate* that link but the human must enter the card. This is the "credit card is
  just a link they fill out" the user described — and it already works that way.
- **Sending mailbox.** All sending is per-inbox through the **user's own Nylas grant**
  (there is *no* app-level Mailgun send path — Mailgun is only magic-link/auth mail). Two
  connect flavors: (a) **Nylas hosted-OAuth** (`email_account_controller.ex`,
  `/email-accounts/connect/:provider` → Google/M365 consent → callback persists an
  `EmailAccount`) — consent is the user's own password screen, so Claude can hand over the
  link but can't click it; and (b) a **manual IMAP/SMTP CSV import**
  (`services/email_account/import_mailboxes.ex` → `ConnectImapMailbox.run` →
  `Nylas.create_imap_grant`) that takes host/user/app-password. Flavor (b) is far more
  automatable — Claude *can* connect an IMAP mailbox given credentials, no browser click.
  Beyond connecting, an inbox must also be **enrolled into the campaign**
  (`CampaignEmailAccount.enroll`) and be `:healthy` before `AssignInbox` will pick it
  (`assign_inbox.ex:22-35`); connecting alone isn't enough.

Everything *between* payment and inbox-consent is automatable.

### 1d. The one real ordering block: "no contacts → can't write emails"
This is exactly the friction the user named. The AI email writer drafts **against a
concrete `CampaignContact`** (person + company), so `WriteLive` shows an **empty state**
when the enriched pool is exhausted — `load_next_contact/next_or_mint` mints the next
contact from the pool and, if there is none, `state: :empty`
(`write_live.ex:411-459`). You cannot open the writer and compose a real draft with zero
contacts, because there is no person to personalize for.

But note what is **not** blocked:
- **Sequences / variants (the templates) are contact-independent.** `Sequence.create_named`
  / `create_bare` and `SequenceStep.create` (`sequence.ex:28-29`, `sequence_step.ex:34`)
  take only `campaign_id` / `sequence_id` — no contact. `create_named` even seeds a default
  4-step shape (email → +2d → +2d → terminal +7d). A variant with no contacts is simply
  "unseeded" (`write_live.ex:547`), meaning its shape is still editable. So Claude can lay
  down the full template structure at t=0.
- **Auto-approve is the "set and forget" engine.** `docs/sending-jit-approval-plan.md`: the
  enriched pool *is* the queue; `AutoApproveCampaign` pulls one contact per open send slot,
  drafts + sends it, follow-ups schedule themselves. Once variants exist, an inbox is
  enrolled + healthy, and `auto_approve_on?` is flipped, **contacts get drafted and sent as
  enrichment produces them** — no one sits in `WriteLive`.

**Three real "needs contacts first" constraints (all downstream of enrichment):**
1. **Manual drafting** needs a concrete contact (above).
2. **`approve` has a DB-level guard**: it refuses a contact whose thread has no
   `OutboundEmail` drafts (`campaign_contact.ex:188-201`) — you can't approve nothing.
3. **Auto-approve won't start until a variant is *seeded*** — i.e. that variant has been
   sent to at least one contact (`auto_approve_campaign.ex:43-46`, `auto_draft_and_approve.ex:72-91`,
   "never send blanks"). Seeding a variant itself needs a contact + drafts + a send. So
   **enrichment producing at least one `picked_person_id` is a hard upstream dependency**
   for the whole send machine to turn over — there is no zero-contact cold start today.

The fix (see §6) tackles all three: author/preview templates against a **sample contact**,
and **auto-seed** each variant off the *first* enriched contact (or relax the seeded gate
for MCP campaigns) so the machine turns over on its own. That converts the wizard from
"forward-only, each step waits on the last" into "declare the whole campaign at t=0, then
let enrichment + auto-approve run it."

### 1e. Minor: the wizard is forward-only and status-gated
`Campaign.status` walks `draft → collecting → enriching` and several LiveViews `mount`
with a redirect if the campaign isn't at the expected stage (e.g.
`funnel_live.ex:55` bounces to `/target` until finalized). None of these are *logic*
blockers — the underlying actions (`update_filters`, `finalize`, …) can be called in any
order by a tool — they're just UI guardrails. MCP tools call the actions directly and
sidestep the wizard, so this mostly evaporates; we only need the actions to be robust to
being called "out of wizard order" (they already mostly are — `AdvanceStatus` never
downgrades, `finalize` is idempotent on `finalized_at`).

---

## 2. How to expose Liid over MCP — yes, Ash supports this directly

Use **`ash_ai`** (`{:ash_ai, "~> 0.8"}`), Ash's official tool-calling + MCP package. It
turns any Ash action into an MCP tool from a declarative block, and ships a Phoenix MCP
router that speaks the **Streamable HTTP** transport (what remote MCP clients, incl.
Claude, use). This is the *easiest way to "reveal everything"* the user asked about: you
don't hand-write an API, you list the actions you want exposed.

### 2a. Declare the tools (one block on the domain)
Add the extension to `Colt.Domain` and enumerate the actions to expose. Each `tool` is
`name, Resource, :action` and inherits the action's args + Ash policies automatically:

```elixir
defmodule Colt.Domain do
  use Ash.Domain, otp_app: :colt, extensions: [AshAi]

  tools do
    # Campaign shape
    tool :create_campaign,   Colt.Resources.Campaign, :create_draft
    tool :set_icp,           Colt.Resources.Campaign, :set_icp
    tool :set_filters,       Colt.Resources.Campaign, :update_filters
    tool :set_target,        Colt.Resources.Campaign, :update_target
    tool :start_enrichment,  Colt.Resources.Campaign, :finalize
    tool :set_auto_approve,  Colt.Resources.Campaign, :set_auto_approve_on
    tool :list_my_campaigns, Colt.Resources.Campaign, :list_for_user

    # Pitch (what we sell)
    tool :set_pitch_domain,  Colt.Resources.Pitch, :set_domain
    tool :set_pitch_summary, Colt.Resources.Pitch, :set_user_summary

    # Templates / sequences — the part that DOESN'T need contacts
    tool :create_sequence,   Colt.Resources.Sequence, :create_named
    tool :add_step,          Colt.Resources.SequenceStep, :create
    tool :enable_sequence,   Colt.Resources.Sequence, :set_enabled

    # Sending inboxes + funnel
    tool :list_inboxes,      Colt.Resources.EmailAccount, :list_for_user
    tool :set_inbox_quota,   Colt.Resources.EmailAccount, :set_quota
    tool :list_contacts,     Colt.Resources.CampaignContact, :list_for_campaign

    # Sales funnel
    tool :move_contact_stage, Colt.Resources.CampaignContact, :move_to_stage
  end
end
```

Every one of those actions **already exists** (see §5). Exposing the workflow is mostly
this list, not new code.

### 2b. Mount the MCP endpoint (production, authenticated)
```elixir
# router.ex
pipeline :mcp do
  plug :accepts, ["json"]
  plug AshAuthentication.Strategy.ApiKey.Plug,
    resource: Colt.Accounts.User,
    required?: true            # every MCP call must carry a key → an actor
end

scope "/mcp" do
  pipe_through :mcp
  forward "/", AshAi.Mcp.Router,
    tools: :all,               # or an explicit list
    protocol_version_statement: "2024-11-05",
    otp_app: :colt
end
```

The dev-only `AshAi.Mcp.Dev` plug (mounted in the endpoint behind `code_reloading?`) is
handy for local testing; the production surface is the router above. Because tools run
through Ash actions, **every existing policy still applies** — a user's key only ever
sees/edits that user's campaigns (`campaign.ex` policies scope on
`owner_id == actor(:id)`), so multi-tenant isolation is free.

### 2c. What the client points at
The user adds a remote MCP server in their Claude client:
`https://app.liid.<tld>/mcp`, header `Authorization: Bearer liid_<key>`. From then on
"Claude, sell X to Y" resolves to a sequence of the tool calls above.

---

## 3. How authentication works for Claude — API keys

MCP calls are stateless HTTP; magic-link cookies don't apply. Add
`ash_authentication`'s **`api_key` strategy** so a long-lived, hashed key maps to a user
and becomes the Ash actor.

### 3a. An `ApiKey` resource (hashed at rest)
```elixir
defmodule Colt.Accounts.ApiKey do
  use Ash.Resource, domain: Colt.Accounts,
    data_layer: AshPostgres.DataLayer, authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults [:read, :destroy]
    create :create do
      accept [:user_id, :expires_at]
      change {AshAuthentication.Strategy.ApiKey.GenerateApiKey, prefix: :liid, hash: :key_hash}
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :key_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
  end

  relationships do
    belongs_to :user, Colt.Accounts.User, allow_nil?: false
  end

  calculations do
    calculate :valid, :boolean, expr(expires_at > now())
  end

  identities do
    identity :unique_key_hash, [:key_hash]
  end

  policies do
    bypass always() do
      authorize_if AshAuthentication.Checks.AshAuthenticationInteraction
    end
  end
end
```

### 3b. Wire the strategy onto `User`
```elixir
# in user.ex authentication/strategies
api_key do
  api_key_relationship :valid_api_keys
end

# relationships
has_many :valid_api_keys, Colt.Accounts.ApiKey do
  filter expr(valid)      # expired keys silently stop working
end

# actions
read :sign_in_with_api_key do
  argument :api_key, :string, allow_nil?: false
  prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
end
```

Only a **hash** is stored; the plaintext key is shown **once** at creation
(`api_key.__metadata__.plaintext_api_key`). The `prefix: :liid` makes keys look like
`liid_…` so they're catchable by secret scanners. The `:api` `Plug` strips
`Bearer ` and assigns `current_user`, which Ash uses as the actor — so the key is
**scoped to exactly one user** and inherits all their policies. Revocation = destroy the
row (or let `expires_at` lapse). A small `/settings/api-keys` LiveView (create / list /
revoke, plaintext shown once) is the only UI needed.

**Security note:** an API key is a bearer of the user's full account power. Keep the
default the *narrow* set of tools in §2 (no destroy of campaigns, no billing mutation),
short-ish `expires_at`, and log tool calls (the `ApiCall`/telemetry infra already exists).

---

## 4. "Claude creates the account; the user only clicks a card link"

The user's inversion — *Claude* onboards, the human just pays — works cleanly because the
two human steps (§1c) are already **links**, not in-app forms.

Proposed flow:

1. **Claude provisions the user headlessly.** Add a small `User.provision_for_agent`
   create action (email in, no magic-link send) — mirrors the existing `:seed` action
   (`user.ex:133-140`) which already upserts by email and applies the first-admin rule.
   It mints an `ApiKey` and returns it to the operator's Claude. (Bootstrapping: the
   operator's Claude holds one **org-level provisioning key**; per-client keys are minted
   under it. Or expose provisioning only to an admin key.)
2. **Claude builds the whole campaign** via the §2 tools: create → ICP + rungs → filters →
   pitch → sequences/variants → target. All contact-independent, all in one pass (after
   §6 lands, the variants can be fully authored against a sample contact).
3. **Claude returns two links for the human:**
   - **Pay:** a Stripe Checkout URL. `CheckoutCreate.run/4` already produces one; wrap it
     as a tool `create_checkout_link` returning `{url}`. The user clicks, enters the card
     on Stripe, the webhook (`/webhooks/stripe`) flips `monthly_contact_capacity` +
     `subscription_status`, and `paid?` becomes true. **This is exactly "just a link they
     fill out."**
   - **Connect inbox:** the `/email-accounts/connect/:provider` URL (Nylas OAuth). One
     click, Google/M365 consent, done. (Or, for an IMAP mailbox, Claude connects it
     directly from credentials via the CSV/`ConnectImapMailbox` path — no user click.)
     Then Claude **enrolls** the inbox into the campaign (`CampaignEmailAccount.enroll`)
     and sets its `daily_quota`.
4. **Claude flips `auto_approve_on?`** (`set_auto_approve` tool). From here the
   pull-based loop in `docs/sending-jit-approval-plan.md` runs the campaign: enrichment
   fills the pool, each open send slot drafts+sends one contact, replies get categorized,
   interested contacts auto-drop into the sales funnel (`docs/sales-funnel.md` S4). **The
   user comes back to replies.**

The only two moments a human is required are the card and the inbox consent — both
irreducible (PCI + OAuth), both a single clicked link. Everything else is Claude.

> **Onboarding sequencing:** payment can come *before or after* Claude builds the
> campaign — `finalize`/enrichment is what's gated on `paid?`, not campaign creation or
> template authoring. So Claude can design the entire campaign first, then send the pay
> link; enrichment kicks off the moment the webhook lands. Good UX: the client sees a
> ready-to-go campaign behind the paywall, which is a stronger "enter card" prompt than a
> blank account.

---

## 5. Inventory — the workflow is already code-interface functions

This is why the lift is small. Existing `code_interface` entry points that become tools
almost 1:1:

- **Campaign** (`campaign.ex:17-34`): `create_draft`, `set_icp`, `update_filters`,
  `save_draft_filters`, `update_target`, `finalize`, `set_auto_approve_on`, `set_panic`,
  `set_tracking`, `rename`, `list_for_user`, `list_recent_for_user`.
- **Pitch** (`pitch.ex:31-37`): `upsert_for_campaign`, `set_domain`, `set_user_summary`,
  `finish_fetch`, `get_for_campaign`.
- **Sequence** (`sequence.ex:24-33`): `create_named`, `create_bare`, `set_name`,
  `set_language`, `set_enabled`, `bump_version`, `list_for_campaign`,
  `list_enabled_for_campaign`. *(contact-independent)*
- **SequenceStep** (`sequence_step.ex:32-38`): `create`, `set_delay`,
  `set_terminal_action`, `set_position`, `delete_step`, `list_for_sequence`.
  *(contact-independent)*
- **CampaignContact** (`campaign_contact.ex:33-58`): `list_for_campaign`, `promote`,
  `next_pending`, `assign_inbox`, `approve`, `skip`, `mark_replied`, `manual_override`,
  `stop_sequence`, `move_to_stage`, `enter_sales_funnel`, `search`, …
- **EmailAccount** (`email_account.ex:22-38`): `list_for_user`, `list_healthy_for_user`,
  `create_from_nylas`, `set_quota`, `mark_status`, `disconnect`, `update_details`.
- **CampaignEmailAccount** (`campaign_email_account.ex:22-30`): `enroll`, `remove`,
  `pause`, `unpause`, `list_for_campaign` — the enroll-inbox-into-campaign step.
- **Billing** (`Colt.Services.Billing.CheckoutCreate` / `PortalCreate`): wrap as generic
  actions returning `{url}`.
- **Send orchestrators** (`lib/colt/services/sending/`, if we want higher-level tools):
  `PromoteOne.run`, `EmailWriter.run`, `ApproveContact.run`, `AutoDraftAndApprove.run`,
  `AssignInbox.run` — these compose the primitives above and could back coarser tools like
  `draft_and_approve_next`.

Gaps to add (small):
- `User.provision_for_agent` (headless create + first key). Model on `:seed`.
- `ApiKey` resource + `api_key` strategy (§3).
- Thin action wrappers around the two `Billing` services so they're tool-callable.
- MCP endpoint + `tools` block (§2).
- Sample-contact drafting so templates author with zero contacts (§6).

---

## 6. Fix the "no contacts → can't write" block: sample-contact drafting

**Problem** (§1d): `WriteLive`/`EmailWriter` need a concrete `CampaignContact` to
personalize, so with an empty pool the writer is dead and a user (or Claude) can't author
the sequence up front.

**Fix:** let a variant be authored/previewed against a **sample contact**, so template
shape is decided on day zero and auto-approve does the per-contact fill later.

Options, cheapest first:
1. **Borrow a real enriched person** from anywhere in the DB (companies/persons are
   globally shared per `spec.md` §2) as a read-only preview subject. Zero new schema; the
   writer just needs a "preview person" path that doesn't create a `CampaignContact` or
   send. Good enough for "see how it reads."
2. **Synthetic sample contact** — a fixed fixture (`Näidis OÜ`, a plausible owner) used
   purely for preview when no real person is available. Deterministic, always present,
   never sent.
3. **Explicit "template mode"** on `Sequence`/variant: subject + body with the merge
   variables (`{{first_name}}`, `{{company}}`, `{{snippet}}`) shown literally, no draft
   render at all. Most honest for pure authoring; render happens per-contact at send.

Recommendation: ship **(2) synthetic sample** for the writer preview *and* make sure the
MCP `create_sequence`/`add_step` tools require none of it — Claude authors the sequence
structurally (subject + body templates), and the sample is only for a *human* who wants a
visual preview. That decouples template *authoring* from contact existence.

**Also fix the seed gate (§1d.3), or the machine still won't turn over.** Authoring a
template isn't enough — `AutoApproveCampaign` refuses to run until the variant is *seeded*
(sent to one real contact). Two ways to make a zero-touch cold start work:
- **Auto-seed off the first enriched contact.** When enrichment produces the campaign's
  first `picked_person_id` and auto-approve is on, treat that first contact as the seed:
  draft + (auto-)approve + send it, which flips the variant to seeded and unblocks the
  rest. No human hand-send required — the "never send blanks" guard is still honored
  because a real draft against a real contact exists.
- **Relax the seed requirement for MCP/auto campaigns** to "variant has ≥1 enabled step
  with non-empty body," so a Claude-authored template counts as seeded without a prior
  send. Slightly riskier (the current gate exists to force a human eyeball once); pair it
  with a low starting `daily_quota` and the panic switch.

With sample-contact authoring **and** auto-seed, a campaign goes from "created" to
"sending on its own as contacts arrive" with **no** contacts-first step — the last thing
standing between the user's ask and reality.

---

## 7. Suggested build order

1. **`ash_ai` dep + `tools` block on the domain + `AshAi.Mcp.Dev`** — exposes read-only
   tools (`list_my_campaigns`, `list_contacts`) to a local MCP client. Prove the pipe.
2. **`api_key` strategy + `ApiKey` resource + `/settings/api-keys` UI** — machine auth.
3. **Production `/mcp` route** behind the api-key plug; add the *write* tools (create /
   set_icp / filters / target / sequences / pitch). Now Claude can build a campaign for an
   existing paid user.
4. **Billing + inbox link tools** (`create_checkout_link`, `connect_inbox_link`) — Claude
   hands the human the two clicks.
5. **`User.provision_for_agent`** — Claude creates the account too (§4).
6. **Sample-contact drafting + auto-seed** (§6) — removes the last ordering blocks
   (manual-draft-needs-contact and seeded-variant gate); full one-shot setup and a
   zero-touch cold start before any contact exists.

After 1–4 the user's core ask works for a user who signs in once. After 5–6 it works with
Claude doing the whole onboarding and the human only touching the card + inbox links.

## 8. Open questions / risks
- **Key blast radius.** An api key = full account power. Decide the default tool
  allow-list (exclude destroys + billing mutation), key TTL, and per-key tool scoping if
  we want "read-only" vs "operator" keys.
- **Provisioning trust.** Who can call `provision_for_agent`? Gate behind an admin/org
  key; don't expose open headless signup or it's an abuse vector.
- **Spend safety.** MCP-driven `finalize` spends real enrichment + AI money under the
  `CapacityGuard` cap. Keep the cap authoritative; consider a per-key daily spend ceiling.
- **Nylas + Stripe stay human.** OAuth consent and card entry can't be automated; the
  design leans into that (links), don't try to proxy credentials.
- **Sending safety.** `panic_switch_on` and inbox health/quota gates
  (`docs/sending-jit-approval-plan.md`) must remain in force for MCP-started campaigns —
  auto-approve already respects them; make sure the tool path can't bypass them.
