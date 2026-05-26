defmodule Colt.Resources.Sequence do
  @moduledoc """
  One Sequence per Campaign. Holds language + version + tracking toggles.
  Step list lives on `SequenceStep` rows.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sequences"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :get_for_campaign, args: [:campaign_id]
    define :create_default, args: [:campaign_id]
    define :set_language, args: [:language]
    define :bump_version
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :get_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      get? true
    end

    create :create_default do
      description "Create the default starter sequence for a campaign (3 email steps + terminal)."
      accept [:campaign_id]

      change fn changeset, _ ->
        Ash.Changeset.after_action(changeset, fn _cs, sequence ->
          steps = [
            %{position: 0, kind: :email, delay_days: 0},
            %{position: 1, kind: :email, delay_days: 2},
            %{position: 2, kind: :email, delay_days: 2},
            %{position: 3, kind: :terminal, delay_days: 7, terminal_action: :no_reply}
          ]

          Enum.each(steps, fn step ->
            Colt.Resources.SequenceStep.create!(
              Map.put(step, :sequence_id, sequence.id),
              authorize?: false
            )
          end)

          {:ok, sequence}
        end)
      end
    end

    update :set_language do
      accept [:language]
      require_atomic? false
    end

    update :bump_version do
      accept []
      require_atomic? false

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(
          changeset,
          :version,
          (Ash.Changeset.get_data(changeset, :version) || 1) + 1
        )
      end
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

    attribute :language, :string,
      allow_nil?: false,
      default: "en",
      public?: true

    attribute :version, :integer,
      allow_nil?: false,
      default: 1,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true

    has_many :sequence_steps, Colt.Resources.SequenceStep do
      sort position: :asc
    end
  end

  identities do
    identity :one_per_campaign, [:campaign_id]
  end
end
