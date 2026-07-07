defmodule Colt.Resources.SalesStage do
  @moduledoc """
  A customizable stage in a campaign's sales funnel. Stages are data, not an
  enum — per campaign, reorderable. `kind` splits the board into the active
  funnel (`:active`) and its two exits (`:won` / `:lost`), so a real
  conversion rate (won ÷ entered) is computable.

  Positions are managed by the app (no unique DB index) so adjacent-swap
  reorders don't trip a constraint mid-transaction. `Colt.Services.Sales`
  seeds the starter set on first visit.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sales_stages"
    repo Colt.Repo

    custom_indexes do
      index [:campaign_id]
    end

    references do
      reference :campaign, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_campaign, args: [:campaign_id]
    define :create, args: [:campaign_id, :name, :position]
    define :rename, args: [:name]
    define :reposition, args: [:position]
    define :set_kind, args: [:kind]
    define :destroy
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [position: :asc])
    end

    create :create do
      accept [:campaign_id, :name, :position, :kind, :color]
    end

    update :rename do
      accept [:name]
      require_atomic? false
    end

    update :reposition do
      accept [:position]
      require_atomic? false
    end

    update :set_kind do
      accept [:kind]
      require_atomic? false
    end

    destroy :destroy do
      require_atomic? false
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

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :position, :integer, allow_nil?: false, default: 0, public?: true

    attribute :kind, :atom,
      constraints: [one_of: [:active, :won, :lost]],
      allow_nil?: false,
      default: :active,
      public?: true

    attribute :color, :string, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
  end
end
