defmodule Colt.Resources.AppSetting do
  @moduledoc """
  Generic key/value store for site-wide singletons set by admins. v1 use:
  the global tracking domain (one CNAME used by every campaign that flips
  open/click tracking on). Future: any other instance-level toggle that
  doesn't justify its own table.

  Access goes through `Colt.AppSettings` rather than this resource
  directly — keeps callers from threading `authorize?: false` everywhere.
  """

  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "app_settings"
    repo Colt.Repo
  end

  code_interface do
    define :get_by_key, args: [:key]
    define :upsert, args: [:key, :value]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :get_by_key do
      argument :key, :string, allow_nil?: false
      filter expr(key == ^arg(:key))
      get? true
    end

    create :upsert do
      accept [:key, :value]
      upsert? true
      upsert_identity :unique_key
      upsert_fields [:value]
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :key, :string, allow_nil?: false, public?: true
    attribute :value, :string, public?: true
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
  end
end
