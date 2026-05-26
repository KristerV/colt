defmodule Colt.Resources.Pitch do
  @moduledoc """
  Per-campaign "what we sell" context, fed into EmailWriter so cold-outreach
  drafts know what the user actually offers.

  Lifecycle:
  - User types a domain → `set_domain` flips `fetching? = true`, stores a
    fresh `fetch_ref`, kicks off `Colt.Services.Sending.PitchSummary`.
  - That service fetches the landing + a couple of product/about pages and
    asks Claude to summarize the offer. On finish it calls `finish_fetch`,
    which only writes if `fetch_ref` still matches (latest input wins —
    older in-flight task results are discarded).
  - The user can edit `user_summary` on top of `ai_summary`. Effective
    summary = `user_summary || ai_summary`.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "pitches"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :get_for_campaign, args: [:campaign_id]
    define :upsert_for_campaign, args: [:campaign_id]
    define :set_domain, args: [:domain, :fetch_ref]
    define :set_user_summary, args: [:user_summary]
    define :finish_fetch, args: [:ai_summary, :fetch_ref]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    read :get_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      get? true
    end

    create :upsert_for_campaign do
      description "Idempotent — returns the existing Pitch or creates a blank one."
      accept [:campaign_id]
      upsert? true
      upsert_identity :one_per_campaign
    end

    update :set_domain do
      description """
      User typed a domain. Stamp `fetching? = true`, store the new
      `fetch_ref`, clear the AI summary so the user sees the lock take
      effect immediately. Caller is responsible for starting the task.
      """

      accept [:domain]
      argument :fetch_ref, :string, allow_nil?: false
      require_atomic? false

      change set_attribute(:fetching?, true)
      change set_attribute(:ai_summary, nil)
      change set_attribute(:user_summary, nil)

      change fn changeset, _ ->
        ref = Ash.Changeset.get_argument(changeset, :fetch_ref)
        Ash.Changeset.change_attribute(changeset, :fetch_ref, ref)
      end
    end

    update :set_user_summary do
      accept [:user_summary]
      require_atomic? false
    end

    update :finish_fetch do
      description """
      Called by `PitchSummary` when the task finishes. Only writes if the
      `fetch_ref` argument matches the currently-stored ref — otherwise
      this is a stale result and we drop it.
      """

      accept [:ai_summary]
      argument :fetch_ref, :string, allow_nil?: false
      require_atomic? false

      change fn changeset, _ ->
        ref = Ash.Changeset.get_argument(changeset, :fetch_ref)
        current = Ash.Changeset.get_data(changeset, :fetch_ref)

        if ref == current do
          changeset
          |> Ash.Changeset.change_attribute(:fetching?, false)
          |> Ash.Changeset.change_attribute(:fetched_at, DateTime.utc_now())
        else
          # Stale result — leave attributes alone so the in-flight task wins.
          changeset
          |> Ash.Changeset.change_attribute(
            :ai_summary,
            Ash.Changeset.get_data(changeset, :ai_summary)
          )
        end
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

    attribute :domain, :string, public?: true
    attribute :ai_summary, :string, public?: true
    attribute :user_summary, :string, public?: true

    attribute :fetching?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :fetch_ref, :string, public?: true
    attribute :fetched_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
  end

  identities do
    identity :one_per_campaign, [:campaign_id]
  end
end
