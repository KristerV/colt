defmodule Colt.Resources.Page do
  @moduledoc """
  A scraped page belonging to a Company. Identity on `[:company_id, :path]` so
  re-scraping is idempotent. `markdown` is filled by the markdown step;
  `in_navigation` is set by ExtractNavigation in Phase 4b.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "pages"
    repo Colt.Repo

    references do
      reference :company, on_delete: :delete
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :upsert
    define :update_markdown, args: [:markdown, :fetcher]
    define :for_company, args: [:company_id]
  end

  actions do
    defaults [:read]
    default_accept []

    create :upsert do
      accept [:company_id, :path, :title, :in_navigation, :markdown, :fetched_at, :fetcher]
      upsert? true
      upsert_identity :company_path
      upsert_fields [:title, :in_navigation, :markdown, :fetched_at, :fetcher]
    end

    update :update_markdown do
      accept [:markdown, :fetcher]
      argument :markdown, :string, allow_nil?: false
      argument :fetcher, :atom, allow_nil?: false

      change set_attribute(:markdown, arg(:markdown))
      change set_attribute(:fetcher, arg(:fetcher))

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :fetched_at, DateTime.utc_now())
      end

      require_atomic? false
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :path, :string, allow_nil?: false, public?: true
    attribute :title, :string, public?: true
    attribute :in_navigation, :boolean, default: false, public?: true
    attribute :markdown, :string, public?: true
    attribute :fetched_at, :utc_datetime_usec, public?: true

    attribute :fetcher, :atom,
      constraints: [one_of: [:static, :wallaby]],
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
  end

  identities do
    identity :company_path, [:company_id, :path]
  end
end
