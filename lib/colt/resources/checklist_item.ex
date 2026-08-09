defmodule Colt.Resources.ChecklistItem do
  @moduledoc """
  One item on a campaign's sales checklist — the list of things you work
  through with every contact ("Intro call", "Demo booked", "Proposal sent").
  Items are data, not an enum: per campaign, reorderable, editable in the
  checklist setup view.

  These are *not* mutually exclusive states. A contact ticks them off
  independently via `Colt.Resources.ContactChecklistItem`; where a contact
  stands overall is decided by `next_action_at` / `outcome` on
  `CampaignContact`, not by this list.

  Positions are managed by the app (no unique DB index) so adjacent-swap
  reorders don't trip a constraint mid-transaction.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "checklist_items"
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
      accept [:campaign_id, :name, :position]
    end

    update :rename do
      accept [:name]
      require_atomic? false
    end

    update :reposition do
      accept [:position]
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

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
  end
end
