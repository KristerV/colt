defmodule Colt.Resources.Sequence do
  @moduledoc """
  One named outreach sequence under a Campaign. A campaign has many. Each
  carries its own structure (the `SequenceStep` rows), a `language`, and an
  `enabled` flag that opts it into auto-approve. The auto-approve job picks
  uniformly at random among enabled (and already-written) sequences.
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
    define :list_for_campaign, args: [:campaign_id]
    define :list_enabled_for_campaign, args: [:campaign_id]
    define :create_named, args: [:campaign_id, :name]
    define :create_bare, args: [:campaign_id, :name, :language]
    define :set_language, args: [:language]
    define :set_name, args: [:name]
    define :set_enabled, args: [:enabled]
    define :bump_version
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :get_for_campaign do
      description "The campaign's oldest template — a representative for summary displays."
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc], limit: 1)
      get? true
    end

    read :list_for_campaign do
      description "Every template in the campaign, oldest first."
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [inserted_at: :asc])
    end

    read :list_enabled_for_campaign do
      description "Active variants in the campaign — the A/B rotation the writer draws new contacts across."
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id) and enabled == true)
      prepare build(sort: [inserted_at: :asc])
    end

    create :create_named do
      description "Create a named variant with a default shape (initial + 2 followups + terminal). The user can add/remove followups while writing the seed."
      accept [:campaign_id, :name]

      change {__MODULE__.Changes.SeedSteps,
              steps: [
                {0, :email, 0, nil},
                {1, :email, 2, nil},
                {2, :email, 2, nil},
                {3, :terminal, 7, :no_reply}
              ]}
    end

    create :create_bare do
      description "Create a template with NO steps — caller copies the structure in (used when cloning a sequence)."
      accept [:campaign_id, :name, :language]
    end

    update :set_language do
      accept [:language]
      require_atomic? false
    end

    update :set_name do
      accept [:name]
      require_atomic? false
    end

    update :set_enabled do
      accept [:enabled]
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

    attribute :name, :string,
      allow_nil?: false,
      default: "Untitled",
      public?: true

    # "Active" — whether this variant is in the A/B rotation. The writer draws
    # new contacts across active variants; turn one off to retire a losing arm.
    # On by default so a freshly created variant immediately participates.
    attribute :enabled, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

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

  defmodule Changes.SeedSteps do
    @moduledoc false
    use Ash.Resource.Change

    @impl true
    def change(changeset, opts, _context) do
      steps = Keyword.fetch!(opts, :steps)

      Ash.Changeset.after_action(changeset, fn _cs, sequence ->
        Enum.each(steps, fn {pos, kind, delay, terminal_action} ->
          Colt.Resources.SequenceStep
          |> Ash.Changeset.for_create(
            :create,
            %{
              sequence_id: sequence.id,
              position: pos,
              kind: kind,
              delay_days: delay,
              terminal_action: terminal_action
            },
            authorize?: false
          )
          |> Ash.create!(authorize?: false)
        end)

        {:ok, sequence}
      end)
    end
  end
end
