defmodule Colt.Resources.Note do
  @moduledoc """
  Free-form note attached to a Thread. Plaintext, single author.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notes"
    repo Colt.Repo

    references do
      reference :thread, on_delete: :delete
      reference :author, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_thread, args: [:thread_id]
    define :create, args: [:thread_id, :body]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :list_for_thread do
      argument :thread_id, :uuid, allow_nil?: false
      filter expr(thread_id == ^arg(:thread_id))
      prepare build(sort: [inserted_at: :asc])
    end

    create :create do
      accept [:thread_id, :body]
      change relate_actor(:author)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(thread.campaign_contact.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:destroy) do
      authorize_if expr(author_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :thread, Colt.Resources.Thread, allow_nil?: false, public?: true
    belongs_to :author, Colt.Accounts.User, allow_nil?: true, public?: true
  end
end
