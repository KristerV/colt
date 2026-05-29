defmodule Colt.Resources.AnnualReport do
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "annual_reports"
    repo Colt.Repo

    references do
      reference :company, on_delete: :delete
    end
  end

  code_interface do
    define :upsert
    define :for_company, args: [:company_id]
  end

  actions do
    defaults [:read]
    default_accept []

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
      prepare build(sort: [year: :desc])
    end

    create :upsert do
      accept [:company_id, :year, :revenue_eur, :employees, :source]
      upsert? true
      upsert_identity :company_year
      upsert_fields [:revenue_eur, :employees, :source]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :year, :integer, allow_nil?: false, public?: true
    attribute :revenue_eur, :decimal, public?: true
    attribute :employees, :integer, public?: true

    attribute :source, :atom,
      constraints: [
        one_of: [:rik, :prh_ixbrl, :brreg, :cvr, :ekrs, :rc, :sodra, :bolagsverket, :ur]
      ],
      default: :rik,
      allow_nil?: false,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
  end

  identities do
    identity :company_year, [:company_id, :year]
  end
end
