defmodule ColtWeb.Campaigns.IcpLive do
  use ColtWeb, :live_view

  alias Colt.Resources.Campaign
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_user_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: "ICP — #{campaign.name}",
            campaign: campaign,
            icp_description: campaign.icp_description || "",
            target_job_title: campaign.target_job_title || "",
            error: nil
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/campaigns/new")}
    end
  end

  def handle_event(
        "validate",
        %{"icp_description" => icp, "target_job_title" => title},
        socket
      ) do
    {:noreply, assign(socket, icp_description: icp, target_job_title: title)}
  end

  def handle_event(
        "save",
        %{"icp_description" => icp, "target_job_title" => title},
        socket
      ) do
    icp = String.trim(icp)
    title = String.trim(title)

    cond do
      title == "" ->
        {:noreply, assign(socket, error: "Add a target job title.")}

      true ->
        case Campaign.set_icp(socket.assigns.campaign, icp, title,
               actor: socket.assigns.current_user
             ) do
          {:ok, campaign} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/market")}

          {:error, err} ->
            {:noreply, assign(socket, error: inspect(err))}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={1}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <form
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col lg:flex-row gap-8 lg:gap-16 flex-1 min-h-0"
      >
        <div class="lg:basis-[320px] lg:shrink-0">
          <Liid.headline
            kicker="02 / ICP"
            sub="Plain English. The model reads this against every company's website to decide if it's a fit. Be specific about what disqualifies."
          >
            Describe the <em>customer</em> you want.
          </Liid.headline>
        </div>

        <div class="flex-1 max-w-[640px] flex flex-col gap-9">
          <div>
            <div class="mb-3">
              <label
                for="icp"
                class="font-mono text-[11px] tracking-[0.08em] uppercase text-ink70"
              >
                Ideal customer profile
              </label>
              <div class="text-[12px] text-ink40 mt-1">
                Describe the ideal customer in plain English. The AI agent
                visits each prospect's website and uses this to decide if
                they're a fit. Spell out what a good customer looks like —
                industry, size, business model, what they sell or do — and
                just as importantly, what a <em>bad</em> fit looks like
                (e.g. "not solo freelancers", "not B2C", "not agencies").
              </div>
            </div>
            <textarea
              id="icp"
              name="icp_description"
              phx-debounce="200"
              class="w-full min-h-[200px] px-[22px] py-5 border border-ink20 bg-paperAlt text-[15px] leading-[1.55] text-ink rounded-sharp outline-none resize-y focus:border-ink"
            >{@icp_description}</textarea>
          </div>

          <div>
            <div class="mb-3">
              <label
                for="title"
                class="font-mono text-[11px] tracking-[0.08em] uppercase text-ink70"
              >
                Target job title
              </label>
              <div class="text-[12px] text-ink40 mt-1">
                The contact we'll try to extract per company. You can list
                multiple titles in order of importance — e.g. "Sales Manager,
                COO, CEO" — and we'll pick the highest-priority match found.
              </div>
            </div>
            <input
              id="title"
              type="text"
              name="target_job_title"
              value={@target_job_title}
              placeholder="Sales Manager, COO, CEO"
              phx-debounce="200"
              class="w-full px-[14px] py-3 border border-ink20 bg-paperAlt text-[14px] text-ink rounded-sharp outline-none focus:border-ink"
            />
          </div>

          <div :if={@error} class="font-mono text-[11px] text-fail">{@error}</div>

          <div class="flex items-center gap-4 mt-2">
            <.link
              navigate={~p"/campaigns/new"}
              class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] border border-ink20 rounded-sharp no-underline text-ink"
            >
              <Liid.icon name="chev-l" size={11} /> Back
            </.link>
            <Liid.btn variant={:primary} mono type="submit">
              Continue → market <Liid.icon name="arrow" />
            </Liid.btn>
          </div>
        </div>
      </form>
    </Layouts.app>
    """
  end
end
