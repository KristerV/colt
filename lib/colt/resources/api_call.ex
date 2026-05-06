defmodule Colt.Resources.ApiCall do
  @moduledoc """
  Cost log entry for any external paid API call (OpenRouter, Google CSE, ...).
  Every call to `Colt.Services.Ai.Complete` and `Colt.Services.Search.Google`
  ends with `Colt.Services.Costs.Track.run/1` inserting one row here.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "api_calls"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :nilify
    end
  end

  code_interface do
    define :record
    define :recent, args: [:limit]
    define :recent_by_provider, args: [:provider, :limit]
  end

  actions do
    defaults [:read]
    default_accept []

    create :record do
      accept [
        :provider,
        :model,
        :status,
        :input_tokens,
        :output_tokens,
        :cost_usd,
        :latency_ms,
        :cached,
        :query,
        :results_count,
        :error,
        :campaign_id
      ]
    end

    read :recent do
      argument :limit, :integer, allow_nil?: false
      prepare build(sort: [inserted_at: :desc])
      prepare fn query, _ -> Ash.Query.limit(query, query.arguments.limit) end
    end

    read :recent_by_provider do
      argument :provider, :atom, allow_nil?: false
      argument :limit, :integer, allow_nil?: false
      filter expr(provider == ^arg(:provider))
      prepare build(sort: [inserted_at: :desc])
      prepare fn query, _ -> Ash.Query.limit(query, query.arguments.limit) end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom,
      constraints: [one_of: [:openrouter, :google_cse]],
      allow_nil?: false,
      public?: true

    attribute :model, :string, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:ok, :error]],
      allow_nil?: false,
      default: :ok,
      public?: true

    attribute :input_tokens, :integer, public?: true
    attribute :output_tokens, :integer, public?: true
    attribute :cost_usd, :decimal, public?: true
    attribute :latency_ms, :integer, public?: true
    attribute :cached, :boolean, default: false, public?: true

    # Search-specific
    attribute :query, :string, public?: true
    attribute :results_count, :integer, public?: true

    attribute :error, :string, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, public?: true, allow_nil?: true
  end
end
