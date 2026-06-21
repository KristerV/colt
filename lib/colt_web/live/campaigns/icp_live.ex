defmodule ColtWeb.Campaigns.IcpLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, IcpLearning}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("ICP — %{name}", name: campaign.name),
            campaign: campaign,
            icp_description: campaign.icp_description || "",
            target_job_title: campaign.target_job_title || "",
            business_model: campaign.business_model || :both,
            learnings: load_learnings(campaign.id),
            next_done?: campaign.market != nil,
            saved?: false,
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
         parse_business_model(params["business_model"], socket.assigns.business_model),
       saved?: false
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
        {:noreply, assign(socket, error: gettext("Add a target job title."))}

      true ->
        case Campaign.set_icp(socket.assigns.campaign, icp, title, business_model,
               actor: socket.assigns.current_user
             ) do
          {:ok, campaign} ->
            if socket.assigns.next_done? do
              {:noreply, assign(socket, campaign: campaign, saved?: true, error: nil)}
            else
              {:noreply, push_navigate(socket, to: ~p"/campaigns/#{campaign.id}/suppression")}
            end

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
    case IcpLearning.list_by_target(campaign_id, :company, authorize?: false) do
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
        id="icp-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col lg:flex-row gap-8 lg:gap-16 flex-1 min-h-0"
      >
        <div class="lg:basis-[320px] lg:shrink-0">
          <Liid.headline
            kicker={gettext("04 / ICP")}
            sub={
              gettext(
                "Plain English. The model reads this against every company's website to decide if it's a fit. Be specific about what disqualifies."
              )
            }
          >
            {raw(gettext("Describe the <em>customer</em> you want."))}
          </Liid.headline>
        </div>

        <div class="flex-1 max-w-[640px] flex flex-col gap-4">
          <div class="bg-card border border-border rounded-[11px] p-5 [box-shadow:var(--shadow)]">
            <div class="mb-3">
              <label class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold">
                {gettext("Target audience")}
              </label>
              <div class="text-[12px] text-inkSoft mt-1">
                {gettext(
                  "Sets the buyer side. Used as a hard filter before the model reads your ICP — saves you spelling it out below."
                )}
              </div>
            </div>
            <div class="flex gap-2">
              <%= for {v, label} <- [{:b2b, gettext("B2B")}, {:b2c, gettext("B2C")}, {:both, gettext("Both")}] do %>
                <% on = @business_model == v %>
                <button
                  type="button"
                  phx-click="pick_business_model"
                  phx-value-v={v}
                  class={[
                    "px-3.5 py-2 text-[12px] tracking-[0.04em] uppercase font-semibold border rounded-[8px] cursor-pointer",
                    on &&
                      "border-accentRing bg-accentSoft text-accent [box-shadow:inset_0_0_0_1px_var(--accentRing)]",
                    not on &&
                      "border-borderStrong bg-card text-inkSoft hover:bg-paperAlt hover:text-ink"
                  ]}
                >
                  {label}
                </button>
              <% end %>
              <input type="hidden" name="business_model" value={@business_model} />
            </div>
          </div>

          <div class="bg-card border border-border rounded-[11px] p-5 [box-shadow:var(--shadow)]">
            <div class="mb-3">
              <label
                for="icp"
                class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold"
              >
                {gettext("Ideal customer profile")}
              </label>
              <div class="text-[12px] text-inkSoft mt-1">
                {raw(
                  gettext(
                    "Describe the ideal customer in plain English. The AI agent visits each prospect's website and uses this to decide if they're a fit. Spell out what a good customer looks like — industry, size, business model, what they sell or do — and just as importantly, what a <em>bad</em> fit looks like (e.g. \"not solo freelancers\", \"not B2C\", \"not agencies\")."
                  )
                )}
              </div>
            </div>
            <textarea
              id="icp"
              name="icp_description"
              phx-debounce="200"
              class="w-full min-h-[200px] px-4 py-3.5 border border-borderStrong bg-card text-[15px] leading-[1.55] text-ink rounded-[8px] outline-none resize-y focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
            >{@icp_description}</textarea>

            <div :if={@learnings != []} class="mt-5">
              <div class="text-[10px] tracking-[0.1em] uppercase text-inkFaint font-semibold mb-2">
                {gettext("Learned refinements (%{n})", n: length(@learnings))}
              </div>
              <div class="text-[11px] text-inkSoft mb-3 leading-[1.5]">
                {gettext(
                  "Saved from \"not a good fit\" / \"actually a good fit\" feedback on the funnel. Applied on top of the ICP above. Delete any that no longer reflect what you want — then re-check ICP on the funnel."
                )}
              </div>
              <ul class="flex flex-col gap-2">
                <li
                  :for={l <- @learnings}
                  class="flex items-start gap-2 px-3 py-2 border border-border rounded-[8px] bg-bgSoft"
                >
                  <span class={[
                    "text-[9px] tracking-[0.1em] uppercase font-semibold px-2 py-0.5 rounded-[8px] shrink-0 mt-0.5",
                    if(l.kind == :include,
                      do: "text-green bg-greenSoft",
                      else: "text-inkSoft bg-paperAlt"
                    )
                  ]}>
                    {if l.kind == :include, do: gettext("include"), else: gettext("exclude")}
                  </span>
                  <span class="flex-1 text-[12px] text-ink leading-[1.5]">{l.body}</span>
                  <button
                    type="button"
                    phx-click="delete_learning"
                    phx-value-id={l.id}
                    class="w-5 h-5 flex items-center justify-center text-inkFaint hover:text-red cursor-pointer shrink-0"
                    aria-label={gettext("Delete learning")}
                  >
                    <Liid.icon name="x" size={11} />
                  </button>
                </li>
              </ul>
            </div>
          </div>

          <div class="bg-card border border-border rounded-[11px] p-5 [box-shadow:var(--shadow)]">
            <div class="mb-3">
              <label
                for="title"
                class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold"
              >
                {gettext("Target job title")}
              </label>
              <div class="text-[12px] text-inkSoft mt-1">
                {gettext(
                  "The contact we'll try to extract per company. You can list multiple titles in order of importance — e.g. \"Sales Manager, COO, CEO\" — and we'll pick the highest-priority match found."
                )}
              </div>
            </div>
            <input
              id="title"
              type="text"
              name="target_job_title"
              value={@target_job_title}
              placeholder={gettext("Sales Manager, COO, CEO")}
              phx-debounce="200"
              class="w-full px-4 py-3 border border-borderStrong bg-card text-[14px] text-ink rounded-[8px] outline-none placeholder:text-inkFaint focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]"
            />
          </div>

          <div :if={@error} class="text-[12px] text-red">{@error}</div>

          <div class="flex items-center gap-4 mt-2">
            <.link
              navigate={~p"/campaigns/#{@campaign.id}/filters"}
              class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] font-semibold text-inkSoft bg-card border border-borderStrong rounded-[8px] no-underline [box-shadow:var(--shadow)] hover:bg-paperAlt hover:text-ink"
            >
              <Liid.icon name="chev-l" size={11} /> {gettext("Back")}
            </.link>
            <Liid.btn variant={:primary} mono type="submit">
              <%= if @next_done? do %>
                {gettext("Save")} <Liid.icon name="check" />
              <% else %>
                {gettext("Continue → exclude")} <Liid.icon name="arrow" />
              <% end %>
            </Liid.btn>
            <span :if={@saved?} class="text-[11.5px] text-inkFaint">{gettext("saved.")}</span>
          </div>
        </div>
      </form>
    </Layouts.app>
    """
  end
end
