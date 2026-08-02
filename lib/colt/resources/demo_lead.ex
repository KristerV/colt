defmodule Colt.Resources.DemoLead do
  @moduledoc """
  What a prospect chose at the end of the `/demo` deck.

  Every branch of the closing slide is recorded, including the one that just
  navigates to registration — which branch wins is the thing worth knowing.

  `visitor_id` and `variant` come from `ab_funnel`, so a lead joins back to the
  deck session that produced it: which cut they watched, which slides, where
  they dropped. `campaign_contact_id` is a different link and is usually blank:
  it is only set when the demo URL carried `?c=<id>`, i.e. when the link was
  handed to a specific contact rather than posted cold. When it is set, the
  submission is also mirrored as a `Note` on that contact's thread.

  `submit` is the one action open to an anonymous visitor; everything else is
  admin-only. Input is length-bounded because that submit is unauthenticated
  and the app has no rate limiting.
  """
  use Ash.Resource,
    otp_app: :colt,
    domain: Colt.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "demo_leads"
    repo Colt.Repo

    references do
      reference :campaign_contact, on_delete: :nilify
    end
  end

  code_interface do
    # Only `kind` is positional — the rest arrive as a map, which reads far
    # better at the call site than nine positional arguments.
    define :submit, args: [:kind]
    define :list
    define :get, action: :read, get_by: [:id]
    define :toggle
    define :count_new
  end

  actions do
    defaults [:read]
    default_accept []

    # Returns the count rather than the rows so the admin tile never has to
    # build a query of its own. The inner count is unauthorised because the
    # caller has already been through this action's own policies — left
    # authorised it starts a second, actorless authorization pass that no
    # policy matches.
    action :count_new, :integer do
      run fn _input, _context ->
        Ash.count(Ash.Query.for_read(__MODULE__, :new_leads), authorize?: false)
      end
    end

    read :new_leads do
      filter expr(status == :new)
    end

    create :submit do
      accept [
        :kind,
        :name,
        :phone,
        :email,
        :message,
        :variant,
        :visitor_id,
        :slide,
        :campaign_contact_id
      ]
    end

    read :list do
      prepare build(sort: [inserted_at: :desc], load: [campaign_contact: [:person]])
    end

    update :toggle do
      require_atomic? false

      change fn changeset, _ ->
        next =
          case changeset.data.status do
            :new -> :done
            :done -> :new
          end

        Ash.Changeset.change_attribute(changeset, :status, next)
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    # The deck is public, so the visitor writing this has no actor at all.
    policy action(:submit) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      constraints: [one_of: [:call_request, :not_a_fit, :try_it]],
      allow_nil?: false,
      public?: true

    # Bounded because this resource is written by an anonymous, unauthenticated
    # visitor and the app has no rate limiting. Unbounded text here would also
    # reach a real sales thread via the `?c=` note mirror.
    attribute :name, :string, public?: true, constraints: [max_length: 200]
    attribute :phone, :string, public?: true, constraints: [max_length: 60]
    attribute :email, :string, public?: true, constraints: [max_length: 320]
    attribute :message, :string, public?: true, constraints: [max_length: 4_000]

    # Which cut they watched and who they are, straight from ab_funnel.
    attribute :variant, :string, public?: true
    attribute :visitor_id, :string, public?: true
    attribute :slide, :string, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:new, :done]],
      allow_nil?: false,
      default: :new,
      public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :campaign_contact, Colt.Resources.CampaignContact,
      public?: true,
      allow_nil?: true
  end
end
