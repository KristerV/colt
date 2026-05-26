defmodule Colt.Resources.Person do
  @moduledoc """
  An extracted human contact. Globally shared across campaigns; the
  per-campaign choice lives on `CampaignCompany.picked_person_id`.
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
    define :set_verification, args: [:email_verification_status]
    define :set_email, args: [:email]
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
        :validated_in_markdown
      ]
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    update :set_email do
      accept [:email]
      require_atomic? false
    end

    update :set_verification do
      require_atomic? false

      argument :email_verification_status, :atom,
        constraints: [one_of: [:valid, :invalid]],
        allow_nil?: false

      change set_attribute(:email_verification_status, arg(:email_verification_status))

      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :email_verified_at, DateTime.utc_now())
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
    attribute :title, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :validated_in_markdown, :boolean, default: false, public?: true

    attribute :email_verification_status, :atom,
      constraints: [one_of: [:valid, :invalid]],
      public?: true

    attribute :email_verified_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
    belongs_to :source_page, Colt.Resources.Page, allow_nil?: true, public?: true
  end
end
