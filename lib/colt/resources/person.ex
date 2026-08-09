defmodule Colt.Resources.Person do
  @moduledoc """
  An extracted human contact. Globally shared across campaigns; the
  per-campaign choice lives on `CampaignCompany.picked_person_id`.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

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
    define :create_manual
    define :update_manual
    define :for_company, args: [:company_id]
    define :set_verification, args: [:email_verification_status]
    define :create_from_address
    define :by_email, args: [:company_id, :email]
    define :find_by_email, args: [:email]
    define :search, args: [:query]
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

    create :create_manual do
      description "Hand-entered contact (not from enrichment). Company is the manual placeholder company."
      accept [:company_id, :name, :title, :email, :phone]
    end

    update :update_manual do
      description "Edit a hand-entered contact's person fields from the sales contact edit form."
      accept [:name, :title, :email, :phone]
      require_atomic? false
    end

    read :for_company do
      argument :company_id, :uuid, allow_nil?: false
      filter expr(company_id == ^arg(:company_id))
    end

    create :create_from_address do
      description "A contact resolved from an address we already hold (registry email, generic inbox) rather than scraped off a page. No source_page — nothing was read to find it."
      accept [:company_id, :name, :email]
    end

    read :by_email do
      description "Find an existing contact for this company by address, so re-resolving a rung doesn't duplicate people."
      argument :company_id, :uuid, allow_nil?: false
      argument :email, :string, allow_nil?: false
      filter expr(company_id == ^arg(:company_id) and email == ^arg(:email))
      get? true
    end

    read :find_by_email do
      description """
      Match a registered user against a contact we already enriched, in any
      campaign. This is how the admin client view picks up a client's name,
      phone and company without any campaign being named in code.
      """

      argument :email, :string, allow_nil?: false
      filter expr(fragment("lower(?) = lower(?)", email, ^arg(:email)))
      prepare build(load: [:company], sort: [inserted_at: :desc], limit: 1)
    end

    read :search do
      description "Admin lookup by contact name or address. Capped at 20."
      argument :query, :string, allow_nil?: false
      prepare build(load: [:company], limit: 20, sort: [inserted_at: :desc])

      prepare fn query, _context ->
        trimmed = query |> Ash.Query.get_argument(:query) |> to_string() |> String.trim()

        Ash.Query.filter(
          query,
          expr(
            ^trimmed != "" and
              (fragment("? ilike '%' || ? || '%'", name, ^trimmed) or
                 fragment("? ilike '%' || ? || '%'", email, ^trimmed))
          )
        )
      end
    end

    update :set_email do
      accept [:email]
      require_atomic? false
    end

    update :set_verification do
      require_atomic? false

      argument :email_verification_status, :atom,
        constraints: [one_of: [:valid, :catch_all, :invalid]],
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
      constraints: [one_of: [:valid, :catch_all, :invalid]],
      public?: true,
      description:
        ":catch_all means the domain accepts every address, so verification proved nothing. Deliverable for an address a human published (scraped) or filed with the registry; worthless for a guessed one. See docs/specs/contact-acquisition.md §3."

    attribute :email_verified_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true
    belongs_to :source_page, Colt.Resources.Page, allow_nil?: true, public?: true
  end
end
