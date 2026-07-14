defmodule Colt.Resources.Company do
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  use Memoize

  postgres do
    table "companies"
    repo Colt.Repo

    # View 3 (FiltersLive) runs market-scoped aggregates over the full registry.
    # All of them restrict to status = :registered, so these are partial indexes
    # on that predicate to keep them small and turn full scans into index scans.
    # Built concurrently so the index build doesn't take an ACCESS EXCLUSIVE lock
    # on the (large) registry table and block traffic during the migration.
    custom_indexes do
      index [:market, :industry_code],
        where: "status = 'registered'",
        concurrently: true,
        name: "companies_market_industry_registered_index"

      index [:market, :revenue_growth_bucket],
        where: "status = 'registered'",
        concurrently: true,
        name: "companies_market_growth_registered_index"

      index [:market, :employees_latest],
        where: "status = 'registered'",
        concurrently: true,
        name: "companies_market_employees_registered_index"

      index [:market, :revenue_latest],
        where: "status = 'registered'",
        concurrently: true,
        name: "companies_market_revenue_registered_index"
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :upsert_basic
    define :update_basic
    define :upsert_full
    define :patch_details
    define :list_by_market, args: [:market]
    define :ids_by_codes, args: [:market, :codes]
    define :with_annual_report
    define :with_employees
    define :by_market, args: [:market]
    define :active
    define :filtered
    define :top_categories
    define :market_totals
    define :market_stats
    define :set_website, args: [:website_url, :website_source]
    define :set_generic_email, args: [:generic_email]
    define :set_ai_summary, args: [:ai_summary]
    define :touch_enriched
    define :touch_website_searched
    define :reset_enrichment
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_by_market do
      argument :market, :atom, allow_nil?: false
      filter expr(market == ^arg(:market))
    end

    read :ids_by_codes do
      description "Resolve {registry_code → id} for a batch of codes within one market. Used by ingest pipelines that need to join external filings to local company ids without holding the whole company list in memory."
      argument :market, :atom, allow_nil?: false
      argument :codes, {:array, :string}, allow_nil?: false
      filter expr(market == ^arg(:market) and registry_code in ^arg(:codes))
      prepare build(select: [:id, :registry_code])
    end

    read :with_annual_report do
      filter expr(exists(annual_reports, true))
    end

    read :with_employees do
      filter expr(not is_nil(employees_latest))
    end

    read :with_nace_code do
      filter expr(not is_nil(industry_code))
    end

    read :by_market do
      argument :market, :atom, allow_nil?: false
      filter expr(market == ^arg(:market))
    end

    read :active do
      filter expr(status == :registered)
    end

    create :upsert_basic do
      description "Insert or update the registry-side fields (lihtandmed)."
      accept [:registry_code, :market, :name, :region, :status]
      upsert? true
      upsert_identity :registry_code_market
      upsert_fields [:name, :region, :status]
    end

    create :upsert_full do
      description "Upsert all registry fields in one shot. Used by sources (e.g. PRH/FI) where industry, website, and basics arrive together."

      accept [
        :registry_code,
        :market,
        :name,
        :region,
        :status,
        :industry_code,
        :website_url,
        :website_source
      ]

      upsert? true
      upsert_identity :registry_code_market
      upsert_fields [:name, :region, :status, :industry_code, :website_url, :website_source]
    end

    create :upsert_details do
      description "Bulk-upserts the yldandmed-sourced fields (website, industry, generic email)."

      accept [
        :registry_code,
        :market,
        :name,
        :status,
        :industry_code,
        :website_url,
        :website_source,
        :generic_email
      ]

      upsert? true
      upsert_identity :registry_code_market
      upsert_fields [:industry_code, :website_url, :website_source, :generic_email]
    end

    update :update_basic do
      description "Edit the manually-entered company basics (name, region, reg. code, market, website) from the sales contact edit form."
      accept [:name, :region, :registry_code, :market, :website_url, :website_source]
      require_atomic? false
    end

    update :patch_details do
      description "Patch fields sourced from yldandmed (website, industry, generic email)."
      accept [:industry_code, :website_url, :website_source, :generic_email]
      require_atomic? false
    end

    update :set_website do
      description "Persist a website URL discovered or confirmed during enrichment."
      accept [:website_url, :website_source]
      argument :website_url, :string, allow_nil?: false
      argument :website_source, :atom, allow_nil?: false
      change set_attribute(:website_url, arg(:website_url))
      change set_attribute(:website_source, arg(:website_source))
      require_atomic? false
    end

    update :set_generic_email do
      accept [:generic_email]
      argument :generic_email, :string, allow_nil?: true
      change set_attribute(:generic_email, arg(:generic_email))
      require_atomic? false
    end

    update :set_ai_summary do
      accept [:ai_summary]
      argument :ai_summary, :string, allow_nil?: false
      change set_attribute(:ai_summary, arg(:ai_summary))
      require_atomic? false
    end

    update :reset_enrichment do
      description "Admin retry — clear all enrichment-derived fields so the pipeline can run from scratch."

      change set_attribute(:website_url, nil)
      change set_attribute(:website_source, nil)
      change set_attribute(:website_search_attempted_at, nil)
      change set_attribute(:ai_summary, nil)
      change set_attribute(:generic_email, nil)
      change set_attribute(:last_enriched_at, nil)

      require_atomic? false
    end

    update :touch_website_searched do
      description "Stamp when a Google search has been attempted (hit or miss) so overlapping campaigns don't re-spend on the same fruitless lookup within the freshness window."

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(
          changeset,
          :website_search_attempted_at,
          DateTime.utc_now()
        )
      end

      require_atomic? false
    end

    update :touch_enriched do
      description "Stamp last_enriched_at when the full pipeline completes."

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :last_enriched_at, DateTime.utc_now())
      end

      require_atomic? false
    end

    read :filtered do
      description """
      View 3 — companies matching the user-selected filter set, in a market.
      Always sorted randomly so the same action serves count, preview (limit 100),
      and top-up sample (capped by `:topup_max_sample`). Pass
      `query: [limit: n]` to bound the read. Pass `exclude_campaign_id:` to
      omit companies already attached to that campaign.
      """

      argument :markets, {:array, :atom}, default: []
      # NACE Rev. 2.1 4-digit prefixes (e.g. "6210"). EMTAK is 5-digit; the 5th
      # digit is a national subclass that doesn't change the wording, so we filter
      # on the NACE class via LEFT(industry_code, 4). Every market's codes are
      # normalised to Rev. 2.1 at import by Colt.Filters.NaceMigration, so this
      # never has to match two vocabularies.
      argument :industries, {:array, :string}, default: []
      argument :industries_exclude, {:array, :string}, default: []
      argument :growth_buckets, {:array, :atom}, default: []
      argument :employees_min, :integer
      argument :employees_max, :integer
      argument :revenue_min, :integer
      argument :revenue_max, :integer
      argument :exclude_campaign_id, :uuid

      filter expr(
               market in ^arg(:markets) and
                 status == :registered and
                 (^arg(:industries) == [] or
                    fragment("LEFT(?, 4) = ANY(?)", industry_code, ^arg(:industries))) and
                 (^arg(:industries_exclude) == [] or
                    not fragment("LEFT(?, 4) = ANY(?)", industry_code, ^arg(:industries_exclude))) and
                 (^arg(:growth_buckets) == [] or
                    revenue_growth_bucket in ^arg(:growth_buckets)) and
                 (is_nil(^arg(:employees_min)) or
                    employees_latest >= ^arg(:employees_min)) and
                 (is_nil(^arg(:employees_max)) or
                    employees_latest <= ^arg(:employees_max)) and
                 (is_nil(^arg(:revenue_min)) or revenue_latest >= ^arg(:revenue_min)) and
                 (is_nil(^arg(:revenue_max)) or revenue_latest <= ^arg(:revenue_max)) and
                 (is_nil(^arg(:exclude_campaign_id)) or
                    not exists(campaign_companies, campaign_id == ^arg(:exclude_campaign_id)))
             )

      prepare build(sort: [random_seed: :asc])
    end

    action :top_categories, {:array, :map} do
      description """
      Top industry categories (4-digit NACE) across the full filtered set,
      ordered by company count desc. Mirrors :filtered's arguments and reuses
      its filter; independent of the preview's random ordering.
      Returns [%{code: "6210", count: 1240}, ...].
      """

      argument :markets, {:array, :atom}, default: []
      argument :industries, {:array, :string}, default: []
      argument :industries_exclude, {:array, :string}, default: []
      argument :growth_buckets, {:array, :atom}, default: []
      argument :employees_min, :integer
      argument :employees_max, :integer
      argument :revenue_min, :integer
      argument :revenue_max, :integer
      argument :limit, :integer, default: 10

      run fn input, context ->
        import Ecto.Query

        filter_args =
          Map.take(input.arguments, [
            :markets,
            :industries,
            :industries_exclude,
            :growth_buckets,
            :employees_min,
            :employees_max,
            :revenue_min,
            :revenue_max
          ])

        with {:ok, base} <-
               __MODULE__
               |> Ash.Query.for_read(:filtered, filter_args, actor: context.actor)
               |> Ash.Query.unset(:sort)
               |> Ash.Query.data_layer_query() do
          rows =
            Colt.Repo.all(
              from c in subquery(base),
                where: not is_nil(c.industry_code),
                group_by: fragment("LEFT(?, 4)", c.industry_code),
                order_by: [desc: count(c.id)],
                limit: ^input.arguments.limit,
                select: %{code: fragment("LEFT(?, 4)", c.industry_code), count: count(c.id)}
            )

          {:ok, rows}
        end
      end
    end

    action :market_totals, :map do
      description """
      Registered-company count per market, keyed by market atom:
      %{ee: 10891, fi: 13853, ...}. A `GROUP BY market` — Ash has no group-by, so
      raw Ecto is the honest tool (deliberate, documented exception). Memoized 24h
      (see market_totals_cached/0) — totals only move on the monthly registry ingest.
      """

      run fn _input, _context -> {:ok, market_totals_cached()} end
    end

    action :market_stats, {:array, :map} do
      description """
      Per-market registry breakdown for the admin dashboard: one row per market
      with counts for active (registered), with ≥1 annual report, with employee
      count, and with NACE code. A single `GROUP BY market` over the full registry
      (Ash has no group-by, so raw Ecto — same documented exception as
      :market_totals). The annual-report figure joins the distinct set of company
      ids from annual_reports rather than a per-row EXISTS. Even so, the query
      full-scans the (large, update-heavy) companies heap and takes minutes, so it
      is memoized 24h (see market_stats_cached/0) — figures only move on ingest /
      enrichment. Call Colt.Resources.Company.refresh_market_stats/0 to recompute.
      Returns [%{market: :ee, active: n, with_annual_report: n, with_employees: n,
      with_nace_code: n}, ...].
      """

      run fn _input, _context -> {:ok, market_stats_cached()} end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :registry_code, :string, allow_nil?: false, public?: true

    attribute :market, :atom,
      constraints: [one_of: Colt.Markets.atoms()],
      allow_nil?: false,
      public?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :region, :string, public?: true
    attribute :industry_code, :string, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:registered, :liquidation, :deleted, :other]],
      allow_nil?: false,
      default: :registered,
      public?: true

    attribute :website_url, :string, public?: true

    attribute :website_source, :atom,
      constraints: [one_of: [:registry, :google, :manual]],
      public?: true

    attribute :generic_email, :string, public?: true
    attribute :ai_summary, :string, public?: true
    attribute :last_enriched_at, :utc_datetime_usec, public?: true
    attribute :website_search_attempted_at, :utc_datetime_usec, public?: true

    attribute :revenue_latest, :decimal, public?: true
    attribute :employees_latest, :integer, public?: true

    attribute :revenue_growth_bucket, :atom,
      constraints: [one_of: [:declining, :stagnant, :slow, :growing_2x, :growing_10x]],
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :annual_reports, Colt.Resources.AnnualReport
    has_many :persons, Colt.Resources.Person
    has_many :pages, Colt.Resources.Page
    has_many :campaign_companies, Colt.Resources.CampaignCompany
  end

  calculations do
    calculate :random_seed, :float, expr(fragment("random()"))
  end

  identities do
    identity :registry_code_market, [:registry_code, :market]
  end

  defmemop market_totals_cached, expires_in: 24 * 60 * 60 * 1000 do
    import Ecto.Query

    Colt.Repo.all(
      from c in __MODULE__,
        where: c.status == :registered,
        group_by: c.market,
        select: {c.market, count(c.id)}
    )
    |> Map.new()
  end

  defmemop market_stats_cached, expires_in: 24 * 60 * 60 * 1000 do
    import Ecto.Query

    has_reports =
      from ar in Colt.Resources.AnnualReport,
        group_by: ar.company_id,
        select: %{company_id: ar.company_id}

    Colt.Repo.all(
      from c in __MODULE__,
        left_join: r in subquery(has_reports),
        on: r.company_id == c.id,
        group_by: c.market,
        order_by: c.market,
        select: %{
          market: c.market,
          active: filter(count(c.id), c.status == :registered),
          with_annual_report: filter(count(c.id), not is_nil(r.company_id)),
          with_employees: filter(count(c.id), not is_nil(c.employees_latest)),
          with_nace_code: filter(count(c.id), not is_nil(c.industry_code))
        }
    )
  end

  @doc "Bust the 24h market_stats memo so the next read recomputes. Call after an ingest/enrichment run."
  def refresh_market_stats, do: Memoize.invalidate(__MODULE__, :market_stats_cached)

  @doc """
  Planner's estimated row count from pg_class.reltuples — instant, no scan.
  Approximate (refreshed by (auto)vacuum/analyze, not per-insert), which is fine
  for a headline tile where an exact `count(*)` would full-scan a multi-hundred-MB
  heap. Callers should format it as an approximation (e.g. "~2.7M").
  """
  def estimated_count do
    %Postgrex.Result{rows: [[n]]} =
      Colt.Repo.query!("SELECT reltuples::bigint FROM pg_class WHERE relname = 'companies'", [])

    max(n, 0)
  end

  @doc """
  Refresh pg_class.reltuples for the companies tile by sampling the table (ANALYZE).
  Seconds, not a full scan. Use after an ingest when estimated_count/0 must reflect
  reality instead of waiting for autovacuum.
  """
  def analyze do
    Colt.Repo.query!("ANALYZE companies", [])
    :ok
  end
end
