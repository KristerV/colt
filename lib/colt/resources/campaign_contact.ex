defmodule Colt.Resources.CampaignContact do
  @moduledoc """
  Join row between a Campaign and a Person (the picked contact for a
  CampaignCompany). Carries per-contact sending state: status, sticky
  inbox assignment, frozen sequence snapshot, reply category.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "campaign_contacts"
    repo Colt.Repo

    custom_indexes do
      index [:campaign_id, :next_action_at]
    end

    references do
      reference :campaign, on_delete: :delete
      reference :person, on_delete: :delete
      reference :assigned_email_account, on_delete: :nilify
      reference :sequence, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_campaign, args: [:campaign_id]
    define :any_committed_for_campaign, args: [:campaign_id]
    define :next_pending, args: [:campaign_id]
    define :promote, args: [:campaign_id, :person_id]
    define :assign_inbox, args: [:assigned_email_account_id]
    define :set_sender, args: [:assigned_email_account_id]

    define :approve,
      args: [:assigned_email_account_id, :sequence_id, :sequence_snapshot, :sequence_version]

    define :skip
    define :mark_replied, args: [:reply_category]
    define :mark_bounced
    define :mark_failed
    define :set_status, args: [:status]
    define :manual_override, args: [:override]
    define :stop_sequence
    define :enter_sales_funnel
    define :set_next_action, args: [:next_action_at]
    define :set_outcome
    define :set_funnels
    define :list_for_sales_funnel, args: [:campaign_id]
    define :count_assigned_today, args: [:email_account_id]
    define :find_active_in_inbox_by_domain, args: [:email_account_id, :domain_suffix]
    define :search, args: [:query]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_campaign do
      description """
      Contacts in the sending funnel (`in_funnel_sending?`). This is the
      send-machine's list — writer, approve, stats, bounce monitor — so
      sales-only manual contacts are excluded.
      """

      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id) and in_funnel_sending? == true)
      prepare build(sort: [inserted_at: :asc])
    end

    read :any_committed_for_campaign do
      description """
      Up to one contact past pending_approval — the unlock gate for
      auto-approve (a variant has been seeded). Sending-funnel only: a
      sales-only manual contact has never been sent to, so it must not
      count as evidence that a variant is seeded.
      """

      argument :campaign_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and status != :pending_approval and
                 in_funnel_sending? == true
             )

      prepare build(limit: 1)
    end

    read :next_pending do
      description """
      Oldest contact in :pending_approval for a campaign, in the sending
      funnel. The `in_funnel_sending?` clause is load-bearing: `status`
      defaults to `:pending_approval` for every row, including hand-entered
      sales-only leads who must never be mailed by the sequence.
      """

      argument :campaign_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and status == :pending_approval and
                 in_funnel_sending? == true
             )

      prepare build(sort: [inserted_at: :asc], limit: 1)
      get? true
    end

    create :promote do
      description """
      Insert a CampaignContact for the given (campaign, person). The single
      creation path: enrichment ingest calls it with just the ids (origin
      defaults to :enrichment, sending funnel on); the manual-contact form
      passes `origin: :manual` and, for a sales-only lead,
      `in_funnel_sending?: false`. Sales-funnel entry is a separate step
      (`AutoEnter`/`enter_sales_funnel`), same for both. Idempotent via the
      unique identity.
      """

      accept [
        :campaign_id,
        :person_id,
        :origin,
        :in_funnel_sending?,
        :assigned_email_account_id
      ]

      upsert? true
      upsert_identity :unique_per_campaign
    end

    update :set_sender do
      description """
      Set (or clear) the contact's sending inbox from the sales/edit UI. Seeds
      the very same sticky `assigned_email_account_id` the sending pipeline
      uses — one field, one send path, no manual-specific logic. Callers only
      seed it while it's still blank; once a conversation is under way the
      assignment sticks.
      """

      accept [:assigned_email_account_id]
      require_atomic? false
    end

    update :assign_inbox do
      description """
      Set the sticky sending inbox before the writer runs, without
      approving. Lets the writer compose in the actual sender's name;
      ApproveContact reuses this assignment instead of re-picking.
      """

      accept [:assigned_email_account_id]
      require_atomic? false
    end

    update :approve do
      description """
      Mark contact as approved. Stores the sequence snapshot + version
      and the sticky inbox. Sets approved_at = now. `auto_approved?` is
      true when the auto-approve worker drove this (no user editing).

      Resource-level guard: refuses to approve a contact whose thread
      has no outbound emails. Approving without drafts strands the
      contact in `:approved` forever — never reachable by the send loop.
      """

      accept [
        :assigned_email_account_id,
        :sequence_id,
        :sequence_snapshot,
        :sequence_version,
        :auto_approved?
      ]

      require_atomic? false

      change set_attribute(:status, :approved)

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :approved_at, DateTime.utc_now())
      end

      validate fn changeset, _ ->
        contact_id = Ash.Changeset.get_data(changeset, :id)

        case Colt.Resources.Thread.for_contact(contact_id, authorize?: false) do
          {:ok, %{id: thread_id}} ->
            case Colt.Resources.OutboundEmail.list_for_thread(thread_id, authorize?: false) do
              {:ok, [_ | _]} -> :ok
              _ -> {:error, field: :id, message: "contact has no drafted emails to approve"}
            end

          _ ->
            {:error, field: :id, message: "contact has no thread"}
        end
      end
    end

    update :skip do
      require_atomic? false
      change set_attribute(:status, :no_reply)

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end

    update :mark_replied do
      accept [:reply_category]
      require_atomic? false
      change set_attribute(:status, :replied)
    end

    update :mark_bounced do
      require_atomic? false
      change set_attribute(:status, :bounced)
    end

    update :mark_failed do
      require_atomic? false
      change set_attribute(:status, :failed)
    end

    update :set_status do
      accept [:status]
      require_atomic? false
    end

    update :manual_override do
      description """
      Manual status override from the thread view's "Mark as…" dropdown.
      Halts in-flight emails (caller invokes HaltSequence separately).

      Mapping:
        :interested / :not_interested / :ooo → status :replied + reply_category
        :call_ready                           → status :call_ready
        :no_reply                             → status :no_reply
      """

      argument :override, :atom,
        allow_nil?: false,
        constraints: [one_of: [:interested, :not_interested, :ooo, :call_ready, :no_reply]]

      require_atomic? false

      change fn changeset, _ ->
        override = Ash.Changeset.get_argument(changeset, :override)
        now = DateTime.utc_now()

        case override do
          o when o in [:interested, :not_interested, :ooo] ->
            changeset
            |> Ash.Changeset.change_attribute(:status, :replied)
            |> Ash.Changeset.change_attribute(:reply_category, o)
            |> Ash.Changeset.change_attribute(:completed_at, now)

          :call_ready ->
            changeset
            |> Ash.Changeset.change_attribute(:status, :call_ready)
            |> Ash.Changeset.change_attribute(:completed_at, now)

          :no_reply ->
            changeset
            |> Ash.Changeset.change_attribute(:status, :no_reply)
            |> Ash.Changeset.change_attribute(:completed_at, now)
        end
      end
    end

    update :stop_sequence do
      description "Manual 'Stop sequence' from the thread view. Sets :no_reply, stamps completed_at. Caller halts the thread's drafts/scheduleds."
      accept []
      require_atomic? false
      change set_attribute(:status, :no_reply)

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())
      end
    end

    update :enter_sales_funnel do
      description """
      Put the contact in the sales funnel. `Colt.Services.Sales.EnterSalesFunnel`
      owns the idempotency guard — it skips this action when the contact is
      already a member — so this action just flips the flag. The contact lands
      with no `next_action_at`, which puts them in the **Now** bucket: freshly
      entered means not yet triaged.
      """

      accept []
      require_atomic? false
      change set_attribute(:in_funnel_sales?, true)
    end

    update :set_next_action do
      description """
      Schedule (or clear) the next thing to do with this contact. A nil value
      drops them back into **Now** as untriaged. The caller
      (`Colt.Services.Sales.SetNextAction`) writes the StatusEvent.
      """

      accept [:next_action_at]
      require_atomic? false
    end

    update :set_outcome do
      description """
      Close the conversation as won or lost, or reopen it with a nil outcome.
      The caller (`Colt.Services.Sales.SetOutcome`) stamps `outcome_at`,
      clears `next_action_at`, and writes the StatusEvent.
      """

      accept [:outcome, :outcome_reason, :outcome_at, :next_action_at]
      require_atomic? false
    end

    update :set_funnels do
      description """
      Edit funnel membership from the sales contact edit form. Turning off
      sales membership also clears the next action and any outcome, so the
      contact comes back in clean if re-entered later via `AutoEnter`.
      """

      accept [:in_funnel_sending?, :in_funnel_sales?]
      require_atomic? false

      change fn changeset, _ ->
        if Ash.Changeset.get_attribute(changeset, :in_funnel_sales?) == false do
          changeset
          |> Ash.Changeset.force_change_attribute(:next_action_at, nil)
          |> Ash.Changeset.force_change_attribute(:outcome, nil)
          |> Ash.Changeset.force_change_attribute(:outcome_reason, nil)
          |> Ash.Changeset.force_change_attribute(:outcome_at, nil)
        else
          changeset
        end
      end
    end

    read :list_for_sales_funnel do
      description """
      Every contact in a campaign's sales funnel, in one query. The board
      groups these by the `sales_bucket` calculation — counts and lists both
      come off this single read, so there are no per-bucket round trips.
      """

      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id) and in_funnel_sales? == true)
      prepare build(sort: [next_action_at: :asc_nils_last])
    end

    read :find_active_in_inbox_by_domain do
      description """
      Cross-domain reply fallback (§1.9/§7.2.4). Latest in-flight contact
      assigned to this inbox whose person email ends in @domain_suffix.
      Excludes terminal statuses.
      """

      argument :email_account_id, :uuid, allow_nil?: false
      argument :domain_suffix, :string, allow_nil?: false

      filter expr(
               assigned_email_account_id == ^arg(:email_account_id) and
                 status in [:approved, :sending] and
                 fragment("lower(?) like '%@' || lower(?)", person.email, ^arg(:domain_suffix))
             )

      prepare build(sort: [updated_at: :desc], limit: 1)
      get? true
    end

    read :count_assigned_today do
      description """
      Number of CampaignContacts approved-and-assigned to the given inbox
      today (UTC date). Used by the sticky-inbox picker.
      """

      argument :email_account_id, :uuid, allow_nil?: false

      filter expr(
               assigned_email_account_id == ^arg(:email_account_id) and
                 fragment("(?)::date = (now() at time zone 'utc')::date", approved_at)
             )
    end

    read :search do
      description """
      Global contact lookup within the owner's campaigns. Matches the joined
      person's phone (digits-only contains-match), name, email, and company
      name. Owner-scoped via the resource read policy. Capped at 50, newest
      first.
      """

      argument :query, :string, allow_nil?: false

      prepare build(load: [:campaign, person: :company], limit: 50, sort: [updated_at: :desc])

      prepare fn query, _context ->
        raw = Ash.Query.get_argument(query, :query) || ""
        trimmed = String.trim(raw)
        digits = String.replace(raw, ~r/[^0-9]/, "")

        Ash.Query.filter(
          query,
          expr(
            (^trimmed != "" and
               (fragment("? ilike '%' || ? || '%'", person.name, ^trimmed) or
                  fragment("? ilike '%' || ? || '%'", person.email, ^trimmed) or
                  fragment("? ilike '%' || ? || '%'", person.company.name, ^trimmed))) or
              (^digits != "" and
                 fragment(
                   "regexp_replace(?, '[^0-9]', '', 'g') like '%' || ? || '%'",
                   person.phone,
                   ^digits
                 ))
          )
        )
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom,
      constraints: [
        one_of: [
          :pending_approval,
          :approved,
          :sending,
          :replied,
          :call_ready,
          :no_reply,
          :bounced,
          :failed
        ]
      ],
      allow_nil?: false,
      default: :pending_approval,
      public?: true

    attribute :sequence_snapshot, :map, public?: true
    attribute :sequence_version, :integer, public?: true

    attribute :reply_category, :atom,
      constraints: [one_of: [:ooo, :interested, :not_interested, :other]],
      public?: true

    attribute :auto_approved?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :completed_at, :utc_datetime_usec, public?: true

    # Which funnel(s) this contact participates in. Each funnel filters on its
    # own flag rather than inferring membership from status — a hand-entered
    # contact can live purely in sales without ever entering the send machine.
    attribute :in_funnel_sending?, :boolean, allow_nil?: false, default: true, public?: true
    attribute :in_funnel_sales?, :boolean, allow_nil?: false, default: false, public?: true

    # Sales funnel state. Between them these two decide the bucket (see the
    # :sales_bucket calculation) — nothing else does. A null next_action_at
    # means "never triaged", which is deliberately loud rather than invisible.
    attribute :next_action_at, :utc_datetime, public?: true

    attribute :outcome, :atom, constraints: [one_of: [:won, :lost]], public?: true
    attribute :outcome_reason, :string, public?: true
    attribute :outcome_at, :utc_datetime, public?: true

    # Provenance: enrichment (promoted from a CampaignCompany) vs manual (hand
    # entered / found on the street).
    attribute :origin, :atom,
      constraints: [one_of: [:enrichment, :manual]],
      allow_nil?: false,
      default: :enrichment,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :person, Colt.Resources.Person, allow_nil?: false, public?: true

    belongs_to :assigned_email_account, Colt.Resources.EmailAccount,
      allow_nil?: true,
      public?: true

    belongs_to :sequence, Colt.Resources.Sequence, allow_nil?: true, public?: true

    has_one :thread, Colt.Resources.Thread
    has_many :checklist_items, Colt.Resources.ContactChecklistItem
  end

  calculations do
    calculate :sales_bucket,
              :atom,
              Colt.Resources.CampaignContact.Calculations.SalesBucket do
      description "Which sales-funnel bucket this contact falls in: :now | :later | :won | :lost."
    end
  end

  identities do
    identity :unique_per_campaign, [:campaign_id, :person_id]
  end
end
