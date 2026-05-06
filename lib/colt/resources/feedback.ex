defmodule Colt.Resources.Feedback do
  @moduledoc """
  User-submitted feedback ticket. Status toggles between :open and :done.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "feedback"
    repo Colt.Repo

    references do
      reference :user, on_delete: :nilify
    end
  end

  code_interface do
    define :submit, args: [:body, :user_id]
    define :list
    define :get, action: :read, get_by: [:id]
    define :toggle
    define :count_open
  end

  actions do
    defaults [:read]
    default_accept []

    create :submit do
      accept [:body, :user_id]
      argument :body, :string, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: true

      change set_attribute(:body, arg(:body))
      change set_attribute(:user_id, arg(:user_id))
      change set_attribute(:status, :open)
    end

    read :list do
      prepare build(sort: [inserted_at: :desc], load: [:user])
    end

    read :count_open do
      filter expr(status == :open)
    end

    update :toggle do
      require_atomic? false

      change fn changeset, _ ->
        next =
          case changeset.data.status do
            :open -> :done
            :done -> :open
          end

        Ash.Changeset.change_attribute(changeset, :status, next)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:open, :done]],
      allow_nil?: false,
      default: :open,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Colt.Accounts.User, public?: true, allow_nil?: true
  end
end
