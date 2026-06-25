defmodule Colt.Resources.RevenueEntry do
  @moduledoc """
  One revenue record for a client in a given month. Two sources feed it:

    * `:subscription` — synced from paid Stripe invoices (deduped on
      `stripe_invoice_id`), by `Colt.Services.Billing.RevenueSync`.
    * `:invoice` / `:manual` — entered by an admin for clients who pay outside
      Stripe (separate invoices, one-off arrangements).

  Paired against `ApiCall` cost, this is the revenue side of profit.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "revenue_entries"
    repo Colt.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :record_manual
    define :upsert_stripe
    define :update_entry, action: :update_entry
    define :delete, action: :destroy
    define :get_by_id, action: :read, get_by: [:id]
    define :list_for_user, args: [:user_id]
    define :monthly_totals, args: [:months_back]
    define :client_revenue, args: [:months_back]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    create :record_manual do
      description "Admin records revenue for a client that doesn't flow through Stripe."
      accept [:user_id, :month, :amount_usd, :source, :note]
    end

    # Idempotent upsert keyed on the Stripe invoice id — re-running the sync
    # refreshes amount/month without creating duplicates.
    create :upsert_stripe do
      accept [:user_id, :month, :amount_usd, :stripe_invoice_id, :note]
      change set_attribute(:source, :subscription)
      upsert? true
      upsert_identity :unique_stripe_invoice
      upsert_fields [:user_id, :month, :amount_usd]
    end

    update :update_entry do
      description "Edit a manually-entered revenue row."
      accept [:month, :amount_usd, :source, :note]
    end

    # Sum revenue per "YYYY-MM" month over the last `months_back` months —
    # feeds the cost-vs-revenue chart. Returns {:ok, [%{month, amount_usd}]}.
    action :monthly_totals, {:array, :map} do
      argument :months_back, :integer, default: 12

      run fn input, _ctx ->
        monthly_total_rows(input.arguments.months_back)
      end
    end

    # Sum revenue per client per month over the last `months_back` months —
    # the revenue side of the profit table. Returns
    # {:ok, [%{user_id, month, amount_usd}]}.
    action :client_revenue, {:array, :map} do
      argument :months_back, :integer, default: 12

      run fn input, _ctx ->
        client_revenue_rows(input.arguments.months_back)
      end
    end

    read :list_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [month: :desc, inserted_at: :desc])
    end
  end

  attributes do
    uuid_primary_key :id

    # "YYYY-MM" — the month the revenue is attributed to.
    attribute :month, :string, allow_nil?: false, public?: true
    attribute :amount_usd, :decimal, allow_nil?: false, public?: true

    attribute :source, :atom,
      constraints: [one_of: [:subscription, :invoice, :manual]],
      allow_nil?: false,
      default: :manual,
      public?: true

    attribute :note, :string, public?: true

    # Set only for :subscription rows synced from Stripe; nil for manual entries.
    attribute :stripe_invoice_id, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Colt.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_stripe_invoice, [:stripe_invoice_id], nils_distinct?: true
  end

  @doc false
  def monthly_total_rows(months_back) when is_integer(months_back) and months_back > 0 do
    import Ecto.Query

    cutoff = months_cutoff(months_back)

    rows =
      from(r in "revenue_entries",
        where: r.month >= ^cutoff,
        group_by: r.month,
        order_by: [asc: r.month],
        select: %{month: r.month, amount_usd: coalesce(sum(r.amount_usd), 0)}
      )
      |> Colt.Repo.all()

    {:ok, rows}
  end

  @doc false
  def client_revenue_rows(months_back) when is_integer(months_back) and months_back > 0 do
    import Ecto.Query

    cutoff = months_cutoff(months_back)

    rows =
      from(r in "revenue_entries",
        where: r.month >= ^cutoff,
        group_by: [r.user_id, r.month],
        select: %{
          user_id: fragment("?::text", r.user_id),
          month: r.month,
          amount_usd: coalesce(sum(r.amount_usd), 0)
        }
      )
      |> Colt.Repo.all()

    {:ok, rows}
  end

  # Lower-bound "YYYY-MM" string `months_back` months before the current month.
  # month is stored as a sortable string, so a string compare bounds the window.
  defp months_cutoff(months_back) do
    %{year: y, month: m} = DateTime.utc_now()
    total = y * 12 + (m - 1) - months_back
    yy = div(total, 12)
    mm = rem(total, 12) + 1
    "#{yy}-#{mm |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
