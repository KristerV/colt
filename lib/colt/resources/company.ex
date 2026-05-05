defmodule Colt.Resources.Company do
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "companies"
    repo Colt.Repo
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :upsert_basic
    define :patch_details
    define :list_by_market, args: [:market]
    define :with_annual_report
    define :with_employees
    define :by_market, args: [:market]
    define :active
    define :filtered
    define :set_website, args: [:website_url, :website_source]
    define :set_generic_email, args: [:generic_email]
    define :set_ai_summary, args: [:ai_summary]
    define :touch_enriched
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_by_market do
      argument :market, :atom, allow_nil?: false
      filter expr(market == ^arg(:market))
    end

    read :with_annual_report do
      filter expr(exists(annual_reports, true))
    end

    read :with_employees do
      filter expr(not is_nil(employees_latest))
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
      and confirm-time sample (limit 1000). Pass `query: [limit: n]` to bound the read.
      """

      argument :market, :atom, allow_nil?: false
      # NACE 4-digit prefixes (e.g. "6201"). EMTAK is 5-digit; the 5th digit is
      # a national subclass that doesn't change the wording, so we filter on the
      # NACE class via LEFT(industry_code, 4).
      argument :industries, {:array, :string}, default: []
      argument :growth_buckets, {:array, :atom}, default: []
      argument :employees_min, :integer
      argument :employees_max, :integer
      argument :revenue_min, :integer
      argument :revenue_max, :integer

      filter expr(
               market == ^arg(:market) and
                 status == :registered and
                 (^arg(:industries) == [] or
                    fragment("LEFT(?, 4) = ANY(?)", industry_code, ^arg(:industries))) and
                 (^arg(:growth_buckets) == [] or
                    revenue_growth_bucket in ^arg(:growth_buckets)) and
                 (is_nil(^arg(:employees_min)) or
                    employees_latest >= ^arg(:employees_min)) and
                 (is_nil(^arg(:employees_max)) or
                    employees_latest <= ^arg(:employees_max)) and
                 (is_nil(^arg(:revenue_min)) or revenue_latest >= ^arg(:revenue_min)) and
                 (is_nil(^arg(:revenue_max)) or revenue_latest <= ^arg(:revenue_max))
             )

      prepare build(sort: [random_seed: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :registry_code, :string, allow_nil?: false, public?: true

    attribute :market, :atom,
      constraints: [one_of: [:ee, :fi, :lv, :lt, :se, :no]],
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
  end

  calculations do
    calculate :random_seed, :float, expr(fragment("random()"))
  end

  identities do
    identity :registry_code_market, [:registry_code, :market]
  end
end
