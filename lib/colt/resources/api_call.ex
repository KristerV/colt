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
    define :get_by_id, action: :read, get_by: [:id]
    define :recent, args: [:limit]
    define :recent_by_provider, args: [:provider, :limit]
    define :list_for_subject, args: [:subject_type, :subject_id]
    define :client_spending, args: [:months_back]
  end

  actions do
    defaults [:read]
    default_accept []

    create :record do
      accept [
        :provider,
        :model,
        :task,
        :status,
        :input_tokens,
        :output_tokens,
        :cost_usd,
        :latency_ms,
        :cached,
        :query,
        :results_count,
        :error,
        :campaign_id,
        :prompt,
        :response,
        :subject_type,
        :subject_id
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

    read :list_for_subject do
      argument :subject_type, :atom, allow_nil?: false
      argument :subject_id, :uuid, allow_nil?: false

      filter expr(subject_type == ^arg(:subject_type) and subject_id == ^arg(:subject_id))
      prepare build(sort: [inserted_at: :desc])
    end

    # Per-client (campaign owner) spend grouped by month. Grouped aggregation with
    # multiple measures doesn't fit a read action, so this generic action runs one
    # focused Ecto query — kept inside the resource so no query leaks into views.
    action :client_spending, {:array, :map} do
      argument :months_back, :integer, default: 12

      run fn input, _ctx ->
        client_spending_rows(input.arguments.months_back)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom,
      constraints: [one_of: [:openrouter, :google_cse]],
      allow_nil?: false,
      public?: true

    attribute :model, :string, public?: true
    attribute :task, :string, public?: true

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

    # Full prompt sent to the model (concatenated system + user messages).
    # Capped per-message at 50KB with middle-truncation.
    attribute :prompt, :string, public?: true
    # Raw model response (stringified — JSON responses are encoded back).
    attribute :response, :string, public?: true

    # Polymorphic link to the record this call was made for. No FK.
    attribute :subject_type, :atom, public?: true
    attribute :subject_id, :uuid, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, public?: true, allow_nil?: true
  end

  @doc false
  # Sum cost_usd + call count per campaign-owner per month over the last
  # `months_back` months. Calls with no campaign (unattributable to a user) are
  # excluded by the inner joins. Returns {:ok, [%{user_id, email, month, cost_usd, calls}]}.
  def client_spending_rows(months_back) when is_integer(months_back) and months_back > 0 do
    import Ecto.Query

    cutoff = DateTime.add(DateTime.utc_now(), -months_back * 31 * 86_400, :second)

    rows =
      from(c in "api_calls",
        join: camp in "campaigns",
        on: camp.id == c.campaign_id,
        join: u in "users",
        on: u.id == camp.owner_id,
        where: c.inserted_at >= ^cutoff,
        group_by: [u.id, u.email, fragment("to_char(?, 'YYYY-MM')", c.inserted_at)],
        order_by: [desc: fragment("to_char(?, 'YYYY-MM')", c.inserted_at)],
        select: %{
          user_id: u.id,
          email: u.email,
          month: fragment("to_char(?, 'YYYY-MM')", c.inserted_at),
          cost_usd: coalesce(sum(c.cost_usd), 0),
          calls: count(c.id)
        }
      )
      |> Colt.Repo.all()

    {:ok, rows}
  end
end
