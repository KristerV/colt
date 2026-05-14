defmodule Colt.Resources.CampaignCompany do
  @moduledoc """
  Per-campaign decisions on a Company. Scaffolded in Phase 2; populated in Phase 3
  when the user confirms filters.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "campaign_companies"
    repo Colt.Repo

    references do
      reference :campaign, on_delete: :delete
      reference :company, on_delete: :delete
      reference :picked_person, on_delete: :nilify
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :mark_scraping
    define :mark_enriched
    define :mark_no_website
    define :mark_rejected, args: [:rejection_reason]
    define :mark_failed
    define :mark_no_contacts
    define :set_picked_person, args: [:picked_person_id]
    define :list_for_campaign, args: [:campaign_id]
    define :list_for_export, args: [:campaign_id]
    define :reset
  end

  actions do
    defaults [:read]
    default_accept []

    create :create do
      accept [:campaign_id, :company_id]
    end

    read :list_for_campaign do
      argument :campaign_id, :uuid, allow_nil?: false
      filter expr(campaign_id == ^arg(:campaign_id))
    end

    read :list_for_export do
      argument :campaign_id, :uuid, allow_nil?: false

      filter expr(
               campaign_id == ^arg(:campaign_id) and
                 status == :enriched and
                 included_in_export == true
             )
    end

    update :mark_scraping do
      change set_attribute(:status, :scraping)
    end

    update :mark_enriched do
      change set_attribute(:status, :enriched)
    end

    update :mark_no_website do
      change set_attribute(:status, :no_website)
    end

    update :mark_rejected do
      argument :rejection_reason, :string, allow_nil?: true

      change set_attribute(:status, :rejected)
      change set_attribute(:rejection_reason, arg(:rejection_reason))
    end

    update :mark_failed do
      argument :failed_stage, :atom,
        constraints: [one_of: [:website, :icp, :contact]],
        allow_nil?: true

      argument :reason, :string, allow_nil?: true
      argument :detail, :string, allow_nil?: true

      change set_attribute(:status, :failed)
      change set_attribute(:failed_stage, arg(:failed_stage))
      change set_attribute(:rejection_reason, arg(:reason))
      change set_attribute(:failure_detail, arg(:detail))
    end

    update :reset do
      description "Admin retry — set status back to pending and clear all failure/outcome fields."

      change set_attribute(:status, :pending)
      change set_attribute(:failed_stage, nil)
      change set_attribute(:rejection_reason, nil)
      change set_attribute(:failure_detail, nil)

      require_atomic? false
    end

    update :set_picked_person do
      accept [:picked_person_id]
      argument :picked_person_id, :uuid, allow_nil?: true
      change set_attribute(:picked_person_id, arg(:picked_person_id))
      require_atomic? false
    end

    update :mark_no_contacts do
      argument :reason, :string, allow_nil?: true

      change set_attribute(:status, :no_contacts)
      change set_attribute(:failed_stage, :contact)
      change set_attribute(:rejection_reason, arg(:reason))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom,
      constraints: [
        one_of: [
          :pending,
          :scraping,
          :rejected,
          :no_website,
          :no_contacts,
          :enriched,
          :failed
        ]
      ],
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :rejection_reason, :string, public?: true
    attribute :failure_detail, :string, public?: true

    attribute :failed_stage, :atom,
      constraints: [one_of: [:website, :icp, :contact]],
      public?: true

    attribute :included_in_export, :boolean, allow_nil?: false, default: true, public?: true
    attribute :picked_person_id, :uuid, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign, Colt.Resources.Campaign, allow_nil?: false, public?: true
    belongs_to :company, Colt.Resources.Company, allow_nil?: false, public?: true

    belongs_to :picked_person, Colt.Resources.Person,
      allow_nil?: true,
      public?: true,
      define_attribute?: false
  end

  identities do
    identity :campaign_company, [:campaign_id, :company_id]
  end
end
