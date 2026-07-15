defmodule Colt.Resources.CampaignCompany do
  @moduledoc """
  Per-campaign decisions on a Company. Scaffolded in Phase 2; populated in Phase 3
  when the user confirms filters.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "campaign_companies"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
      reference :company, on_delete: :delete
      reference :picked_person, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :mark_scraping
    define :mark_enriched
    define :mark_no_website
    define :mark_excluded, args: [:reason]
    define :mark_rejected, args: [:rejection_reason]
    define :mark_failed
    define :mark_no_contacts
    define :mark_verify_failed, args: [:reason]
    define :set_icp_reason, args: [:icp_reason]
    define :mark_website_skipped
    define :set_picked_person, args: [:picked_person_id, :picked_email]
    define :picked_with_email, args: [:campaign_id, :picked_email]
    define :list_for_campaign, args: [:campaign_id]
    define :next_unpromoted, args: [:campaign_id], not_found_error?: false
    define :page_for_funnel, args: [:campaign_id, :statuses]
    define :list_for_export, args: [:campaign_id]
    define :reset
    define :reset_for_icp_recheck
    define :clear_failure
    define :enriched_by_month, args: [:months_back]
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      accept [:campaign_id, :company_id]
    end

    # Enriched-company (credit) count per campaign-owner per month, last
    # `months_back` months — the per-month credit usage for the admin profit
    # view. Returns {:ok, [%{user_id, month, count}]}.
    action :enriched_by_month, {:array, :map} do
      argument :months_back, :integer, default: 12

      run fn input, _ctx ->
        enriched_by_month_rows(input.arguments.months_back)
      end
    end

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
    end

    read :next_unpromoted do
      description """
      Oldest enriched pick (non-null picked_person_id) in this campaign that
      has no CampaignContact yet — the next candidate the pull model promotes.
      The pool minus already-promoted person_ids, fetched one at a time.
      """

      argument :campaign_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 status == :enriched and
                 not is_nil(picked_person_id) and
                 not exists(
                   Colt.Resources.CampaignContact,
                   campaign_id == parent(campaign_id) and
                     person_id == parent(picked_person_id)
                 )
             )

      prepare build(sort: [inserted_at: :asc], limit: 1)
      get? true
    end

    read :page_for_funnel do
      description """
      Keyset-paginated rows for one funnel bucket. The funnel only ever shows
      one status group at a time, so paging per-bucket keeps the LiveView from
      loading thousands of companies (and their pages/persons) into memory.
      """

      argument :campaign_id, :uuid, allow_nil?: false
      argument :statuses, {:array, :atom}, allow_nil?: false

      filter expr(campaign_id == ^arg(:campaign_id) and status in ^arg(:statuses))
      prepare build(sort: [inserted_at: :asc, id: :asc])

      pagination offset?: true, default_limit: 100, required?: false
    end

    read :list_for_export do
      argument :campaign_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 status == :enriched and
                 included_in_export == true
             )
    end

    update :mark_scraping do
      change set_attribute(:status, :scraping)
    end

    update :mark_enriched do
      # Full success — scrub any fall-out/failure markers from an earlier
      # attempt (e.g. an infra `:failed` this row recovered from).
      change set_attribute(:status, :enriched)
      change set_attribute(:failed_stage, nil)
      change set_attribute(:failure_detail, nil)
    end

    update :mark_no_website do
      change set_attribute(:status, :no_website)
      change set_attribute(:failure_detail, nil)
    end

    update :mark_excluded do
      argument :reason, :string, allow_nil?: true

      change set_attribute(:status, :excluded)
      change set_attribute(:rejection_reason, arg(:reason))
      change set_attribute(:failure_detail, nil)
    end

    update :mark_rejected do
      argument :rejection_reason, :string, allow_nil?: true

      change set_attribute(:status, :rejected)
      change set_attribute(:rejection_reason, arg(:rejection_reason))
      change set_attribute(:icp_reason, arg(:rejection_reason))
      change set_attribute(:failure_detail, nil)
    end

    update :set_icp_reason do
      argument :icp_reason, :string, allow_nil?: true
      change set_attribute(:icp_reason, arg(:icp_reason))
    end

    update :mark_website_skipped do
      description "Record that this company stayed in the funnel without a website, so the pills stay honest across a reload."
      change set_attribute(:skipped_website?, true)
    end

    update :mark_failed do
      argument :failed_stage, :atom,
        constraints: [one_of: [:website, :icp, :contact, :verify]],
        allow_nil?: true

      argument :reason, :string, allow_nil?: true
      argument :detail, :string, allow_nil?: true

      change set_attribute(:status, :failed)
      change set_attribute(:failed_stage, arg(:failed_stage))
      change set_attribute(:rejection_reason, arg(:reason))
      change set_attribute(:failure_detail, arg(:detail))
    end

    update :clear_failure do
      description """
      Restart-safe entry. Drops a terminal `:failed` back to in-flight
      (`:scraping`) and clears stale failure fields so a re-run of a discarded
      job recovers cleanly and downstream stages aren't blocked. Workers call
      this on entry; it's a no-op for any non-failed status.
      """

      change set_attribute(:status, :scraping)
      change set_attribute(:failed_stage, nil)
      change set_attribute(:rejection_reason, nil)
      change set_attribute(:failure_detail, nil)

      require_atomic? false
    end

    update :reset do
      description "Admin retry — set status back to pending and clear all failure/outcome fields."

      change set_attribute(:status, :pending)
      change set_attribute(:failed_stage, nil)
      change set_attribute(:rejection_reason, nil)
      change set_attribute(:icp_reason, nil)
      change set_attribute(:failure_detail, nil)

      require_atomic? false
    end

    update :reset_for_icp_recheck do
      description """
      Light reset before re-running MatchICP. Leaves company-level data
      (ai_summary, pages, persons) untouched so other campaigns sharing
      the same Company aren't affected.
      """

      change set_attribute(:status, :scraping)
      change set_attribute(:failed_stage, nil)
      change set_attribute(:rejection_reason, nil)
      change set_attribute(:icp_reason, nil)
      change set_attribute(:failure_detail, nil)
      change set_attribute(:picked_person_id, nil)

      require_atomic? false
    end

    update :set_picked_person do
      description "Pick (or clear) this company's contact. :picked_email travels with the pick so the campaign-wide uniqueness index can see it — pass the person's email, lowercased."
      accept [:picked_person_id, :picked_email]
      argument :picked_person_id, :uuid, allow_nil?: true
      argument :picked_email, :string, allow_nil?: true
      change set_attribute(:picked_person_id, arg(:picked_person_id))
      change set_attribute(:picked_email, arg(:picked_email))
      require_atomic? false
    end

    read :picked_with_email do
      description "Rows in this campaign already pointing at this address. Backs the duplicate-contact check."
      argument :campaign_id, :uuid, allow_nil?: false
      argument :picked_email, :string, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 picked_email == ^arg(:picked_email)
             )
    end

    update :mark_no_contacts do
      argument :reason, :string, allow_nil?: true

      change set_attribute(:status, :no_contacts)
      change set_attribute(:failed_stage, :contact)
      change set_attribute(:rejection_reason, arg(:reason))
      change set_attribute(:failure_detail, nil)
    end

    update :mark_verify_failed do
      argument :reason, :string, allow_nil?: true

      change set_attribute(:status, :verify_failed)
      change set_attribute(:failed_stage, :verify)
      change set_attribute(:rejection_reason, arg(:reason))
      change set_attribute(:failure_detail, nil)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom,
      constraints: [
        one_of: [
          :pending,
          :scraping,
          :rejected,
          :excluded,
          :no_website,
          :no_contacts,
          :verify_failed,
          :enriched,
          :failed
        ]
      ],
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :rejection_reason, :string, public?: true
    attribute :icp_reason, :string, public?: true
    attribute :failure_detail, :string, public?: true

    attribute :failed_stage, :atom,
      constraints: [one_of: [:website, :icp, :contact, :verify]],
      public?: true

    attribute :skipped_website?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true,
      description:
        "Kept in the funnel with no website (campaign has require_website? off). The website and ICP stages never ran, so the pills must render :skip — without this the reload path would derive them as :done and claim checks we never made."

    attribute :included_in_export, :boolean, allow_nil?: false, default: true, public?: true
    attribute :picked_person_id, :uuid, public?: true

    attribute :picked_email, :string,
      public?: true,
      description:
        "Lowercased email of the picked person, denormalised off Person purely so (campaign_id, picked_email) can carry a unique index. The same human is a separate Person row per company — aare.kulli@gmail.com exists on four — so picked_person_id cannot detect that we're about to email one person twice in a campaign."

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true

    belongs_to :picked_person, Colt.Resources.Person,
      allow_nil?: true,
      public?: true,
      define_attribute?: false
  end

  identities do
    identity :campaign_company, [:campaign_id, :company_id]

    # One human, one email, per campaign. Postgres treats NULLs as distinct, so
    # the many not-yet-picked rows don't collide with each other. This is the
    # actual guarantee — the pre-check in ContactDedup only saves churn; two
    # concurrent Oban jobs resolving the same owner both pass that check and one
    # of them lands here.
    identity :campaign_picked_email, [:campaign_id, :picked_email]
  end

  @doc false
  # Count of enriched companies per campaign-owner per "YYYY-MM" month over the
  # last `months_back` months. owner_id cast to text so it matches Ash User ids
  # (schemaless queries return uuid columns as raw binaries). Returns
  # {:ok, [%{user_id, month, count}]}.
  def enriched_by_month_rows(months_back) when is_integer(months_back) and months_back > 0 do
    import Ecto.Query

    cutoff = DateTime.add(DateTime.utc_now(), -months_back * 31 * 86_400, :second)

    rows =
      from(cc in "campaign_companies",
        join: camp in "campaigns",
        on: camp.id == cc.campaign_id,
        where: cc.status == "enriched" and cc.inserted_at >= ^cutoff,
        group_by: [
          fragment("?::text", camp.owner_id),
          fragment("to_char(?, 'YYYY-MM')", cc.inserted_at)
        ],
        select: %{
          user_id: fragment("?::text", camp.owner_id),
          month: fragment("to_char(?, 'YYYY-MM')", cc.inserted_at),
          count: count(cc.id)
        }
      )
      |> Colt.Repo.all()

    {:ok, rows}
  end
end
