defmodule Colt.Resources.IcpLearning do
  @moduledoc """
  A campaign-scoped exclusion rule, derived from a user's "not a good fit"
  feedback on a specific company. Appended to the ICP prompt at classify-time
  without rewriting the user's original `campaign.icp_description`.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "icp_learnings"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
      reference :source_company, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :create, args: [:campaign_id, :body, :source_company_id]
    define :list_for_campaign, args: [:campaign_id]
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    create :create do
      accept [:campaign_id, :body, :source_company_id]
    end

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :source_company, Colt.Resources.Company, allow_nil?: true, public?: true
  end
end
