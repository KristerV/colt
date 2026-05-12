defmodule Colt.Resources.Person do
  @moduledoc """
  An extracted human contact. Globally shared (no campaign_id) — the
  per-campaign `matches_target_title` flag is recomputed in Phase 4b's
  ExtractContacts step using the campaign's target title, so it's stored
  here as the latest computed value.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "persons"
    repo Colt.Repo

    references do
      reference :company, on_delete: :delete
      reference :source_page, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :create_validated
    define :for_company, args: [:company_id]
    define :set_target_match, args: [:matches_target_title]
  end

  actions do
    defaults [:read, :destroy]
    default_accept []

    create :create_validated do
      accept [
        :company_id,
        :source_page_id,
        :name,
        :title,
        :email,
        :phone,
        :validated_in_markdown,
        :matches_target_title
      ]
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    update :set_target_match do
      argument :matches_target_title, :boolean, allow_nil?: false
      change set_attribute(:matches_target_title, arg(:matches_target_title))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
    attribute :title, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :validated_in_markdown, :boolean, default: false, public?: true
    attribute :matches_target_title, :boolean, default: false, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
    belongs_to :source_page, Colt.Resources.Page, allow_nil?: true, public?: true
  end
end
