defmodule Colt.Resources.SuppressedDomain do
  @moduledoc """
  A campaign-scoped "already contacted" domain. Built from a CSV of emails the
  user has already sent (uploaded on the campaign's Exclude step). Enrichment
  short-circuits any company whose website domain matches one of these to
  `:excluded` before spending scrape/AI budget.

  Domains are stored normalized: lowercase, `www.` stripped. The
  `[:campaign_id, :domain]` identity makes re-uploads idempotent.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "suppressed_domains"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :create, args: [:campaign_id, :domain]
    define :list_for_campaign, args: [:campaign_id]
    define :match, args: [:campaign_id, :domain]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    create :create do
      accept [:campaign_id, :domain]
      upsert? true
      upsert_identity :campaign_domain
      # No-op on conflict: the row already exists with this exact domain. A
      # field must be named for bulk upserts; re-writing :domain to itself is
      # harmless and keeps re-uploads idempotent.
      upsert_fields [:domain]
    end

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
      prepare build(sort: [domain: :asc])
    end

    read :match do
      argument :campaign_id, :uuid, allow_nil?: false
      argument :domain, :string, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id) and domain == ^arg(:domain))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :domain, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
  end

  identities do
    identity :campaign_domain, [:campaign_id, :domain]
  end
end
