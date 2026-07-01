defmodule Colt.Resources.SequenceStep do
  @moduledoc """
  One row per step in a Sequence. The list always ends with exactly one
  `:terminal` step; the editor enforces that. Delays are relative to the
  prior step (or, for the terminal step, days after the final email).

  Admin-only exception: a `:ooo` "welcome-back" step lives at the reserved
  position `-1` (see `ooo_position/0`). It is authored like any step but sits
  outside the linear 0..N follow-up flow, so the lazy scheduler's
  `position == current + 1` lookup can never select it. It is injected only
  when an out-of-office auto-reply is detected.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @doc "Reserved position of the admin-only OOO welcome-back step."
  def ooo_position, do: -1

  postgres do
    table "sequence_steps"
    repo Colt.Repo

    references do
      reference :sequence, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :list_for_sequence, args: [:sequence_id]
    define :create, args: [:sequence_id, :position, :kind, :delay_days]
    define :set_delay, args: [:delay_days]
    define :set_terminal_action, args: [:terminal_action]
    define :set_position, args: [:position]
    define :delete_step
  end

  actions do
    defaults [:read]
    default_accept []

    read :list_for_sequence do
      argument :sequence_id, :uuid, allow_nil?: false
      filter expr(sequence_id == ^arg(:sequence_id))
      prepare build(sort: [position: :asc])
    end

    create :create do
      accept [:sequence_id, :position, :kind, :delay_days, :terminal_action]
    end

    update :set_delay do
      accept [:delay_days]
      require_atomic? false
    end

    update :set_terminal_action do
      accept [:terminal_action]
      require_atomic? false
    end

    update :set_position do
      accept [:position]
      require_atomic? false
    end

    destroy :delete_step do
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(sequence.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:update) do
      authorize_if expr(sequence.campaign.owner_id == ^actor(:id))
    end

    policy action_type(:destroy) do
      authorize_if expr(sequence.campaign.owner_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer, allow_nil?: false, public?: true

    attribute :kind, :atom,
      constraints: [one_of: [:email, :terminal, :ooo]],
      allow_nil?: false,
      default: :email,
      public?: true

    attribute :delay_days, :integer,
      allow_nil?: false,
      default: 2,
      public?: true,
      constraints: [min: 0]

    attribute :terminal_action, :atom,
      constraints: [one_of: [:no_reply, :call_ready]],
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sequence, Colt.Resources.Sequence, allow_nil?: false, public?: true
  end

  identities do
    identity :position_per_sequence, [:sequence_id, :position]
  end
end
