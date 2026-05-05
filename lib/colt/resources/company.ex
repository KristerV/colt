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
    define :upsert_basic
    define :patch_details
    define :list_by_market, args: [:market]
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_by_market do
      argument :market, :atom, allow_nil?: false
      filter expr(market == ^arg(:market))
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
  end

  identities do
    identity :registry_code_market, [:registry_code, :market]
  end
end
