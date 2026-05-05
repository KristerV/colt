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
    end
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      accept [:campaign_id, :company_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom,
      constraints: [
        one_of: [:pending, :scraping, :rejected, :no_website, :enriched, :failed]
      ],
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :rejection_reason, :string, public?: true
    attribute :included_in_export, :boolean, allow_nil?: false, default: true, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
  end

  identities do
    identity :campaign_company, [:campaign_id, :company_id]
  end
end
