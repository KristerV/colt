defmodule Colt.Resources.ContactChecklistItem do
  @moduledoc """
  One contact's tick against a campaign's `ChecklistItem`.

  Rows are created **lazily** — only once an item is actually ticked. The
  thread view renders the campaign's checklist and looks up done-state by
  `checklist_item_id`, so editing the campaign checklist is reflected
  everywhere with no materialisation step and no backfill.

  `checklist_item_id` is nullable to leave room for ad-hoc, contact-specific
  todos (which carry their own `name`). Nothing creates those yet. Postgres
  treats NULLs as distinct in a unique index, so the identity below constrains
  template-derived rows without getting in their way.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "contact_checklist_items"
    repo Colt.Repo

    custom_indexes do
      index [:campaign_contact_id]
    end

    references do
      reference :campaign_contact, on_delete: :delete
      reference :checklist_item, on_delete: :delete
      reference :done_by, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_contact, args: [:campaign_contact_id]
    define :create, args: [:campaign_contact_id, :checklist_item_id]
    define :set_done, args: [:done_at]
    define :destroy
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_contact do
      argument :campaign_contact_id, :uuid, allow_nil?: false
      filter expr(campaign_contact_id == ^arg(:campaign_contact_id))
      prepare build(sort: [inserted_at: :asc])
    end

    create :create do
      accept [:campaign_contact_id, :checklist_item_id, :name, :done_at]
      change relate_actor(:done_by, allow_nil?: true)
    end

    update :set_done do
      description "Tick (done_at set) or untick (done_at nil) an item."
      accept [:done_at]
      require_atomic? false
      change relate_actor(:done_by, allow_nil?: true)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(campaign_contact.campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string,
      public?: true,
      description: "Only set for ad-hoc items, which have no checklist_item_id."

    attribute :done_at, :utc_datetime, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign_contact, Colt.Resources.CampaignContact,
      allow_nil?: false,
      public?: true

    belongs_to :checklist_item, Colt.Resources.ChecklistItem, allow_nil?: true, public?: true
    belongs_to :done_by, Colt.Accounts.User, allow_nil?: true, public?: true
  end

  identities do
    identity :unique_per_contact_item, [:campaign_contact_id, :checklist_item_id]
  end
end
