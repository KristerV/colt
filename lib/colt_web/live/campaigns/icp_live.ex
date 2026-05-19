defmodule ColtWeb.Campaigns.IcpLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, IcpLearning}
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
            business_model: campaign.business_model || :both,
            learnings: load_learnings(campaign.id),
            error: nil
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/campaigns/new")}
    end
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     assign(socket,
       icp_description: params["icp_description"] || socket.assigns.icp_description,
       target_job_title: params["target_job_title"] || socket.assigns.target_job_title,
       business_model:
         parse_business_model(params["business_model"], socket.assigns.business_model)
     )}
  end

  def handle_event("pick_business_model", %{"v" => v}, socket) do
    {:noreply, assign(socket, business_model: parse_business_model(v, :both))}
  end

  def handle_event(
        "save",
        %{"icp_description" => icp, "target_job_title" => title} = params,
        socket
      ) do
    icp = String.trim(icp)
    title = String.trim(title)
    business_model = parse_business_model(params["business_model"], socket.assigns.business_model)

    cond do
      title == "" ->
        {:noreply, assign(socket, error: "Add a target job title.")}

      true ->
        case Campaign.set_icp(socket.assigns.campaign, icp, title, business_model,
               actor: socket.assigns.current_user
             ) do
          {:ok, campaign} ->
            {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/market")}

          {:error, err} ->
            {:noreply, assign(socket, error: inspect(err))}
        end
    end
  end

  def handle_event("delete_learning", %{"id" => id}, socket) do
    case IcpLearning.get(id) do
      {:ok, learning} ->
        :ok = Ash.destroy!(learning, authorize?: false)
        {:noreply, assign(socket, learnings: load_learnings(socket.assigns.campaign.id))}

      _ ->
        {:noreply, socket}
    end
  end

  defp parse_business_model("b2b", _), do: :b2b
  defp parse_business_model("b2c", _), do: :b2c
  defp parse_business_model("both", _), do: :both
  defp parse_business_model(_, fallback), do: fallback

  defp load_learnings(campaign_id) do
    case IcpLearning.list_for_campaign(campaign_id, authorize?: false) do
      {:ok, learnings} -> learnings
      _ -> []
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={1}
      campaign={@campaign}
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
              <label class="font-mono text-[11px] tracking-[0.08em] uppercase text-ink70">
                Target audience
              </label>
              <div class="text-[12px] text-ink40 mt-1">
                Sets the buyer side. Used as a hard filter before the model reads your ICP — saves you spelling it out below.
              </div>
            </div>
            <div class="flex gap-1.5">
              <%= for {v, label} <- [{:b2b, "B2B"}, {:b2c, "B2C"}, {:both, "Both"}] do %>
                <% on = @business_model == v %>
                <button
                  type="button"
                  phx-click="pick_business_model"
                  phx-value-v={v}
                  class={[
                    "px-3.5 py-2 text-[12px] font-mono tracking-[0.04em] uppercase border rounded-sharp cursor-pointer",
                    on && "border-[var(--accent)] text-ink",
                    not on && "border-ink20 text-ink55 hover:text-ink"
                  ]}
                  style={on && "background: color-mix(in oklch, var(--accent) 8%, transparent);"}
                >
                  {label}
                </button>
              <% end %>
              <input type="hidden" name="business_model" value={@business_model} />
            </div>
          </div>

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

            <div :if={@learnings != []} class="mt-4">
              <div class="font-mono text-[10px] tracking-[0.12em] uppercase text-ink55 mb-2">
                Learned refinements ({length(@learnings)})
              </div>
              <div class="text-[11px] text-ink40 mb-3 leading-[1.5]">
                Saved from "not a good fit" / "actually a good fit" feedback on
                the funnel. Applied on top of the ICP above. Delete any that no
                longer reflect what you want — then re-check ICP on the funnel.
              </div>
              <ul class="flex flex-col gap-1.5">
                <li
                  :for={l <- @learnings}
                  class="flex items-start gap-2 px-3 py-2 border border-ink20 rounded-sharp bg-paperAlt"
                >
                  <span class={[
                    "font-mono text-[9px] tracking-[0.12em] uppercase px-1.5 py-0.5 border rounded-sharp shrink-0 mt-0.5",
                    if(l.kind == :include,
                      do: "text-ink70 border-ink40",
                      else: "text-ink55 border-ink20"
                    )
                  ]}>
                    {if l.kind == :include, do: "include", else: "exclude"}
                  </span>
                  <span class="flex-1 text-[12px] text-ink leading-[1.5]">{l.body}</span>
                  <button
                    type="button"
                    phx-click="delete_learning"
                    phx-value-id={l.id}
                    class="w-5 h-5 flex items-center justify-center text-ink40 hover:text-fail cursor-pointer shrink-0"
                    aria-label="Delete learning"
                  >
                    <Liid.icon name="x" size={11} />
                  </button>
                </li>
              </ul>
            </div>
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
