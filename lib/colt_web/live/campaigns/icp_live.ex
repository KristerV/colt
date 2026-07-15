defmodule ColtWeb.Campaigns.IcpLive do
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, IcpLearning}
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user, load: [:suppressed_count]) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("ICP — %{name}", name: campaign.name),
            campaign: campaign,
            icp_description: campaign.icp_description || "",
            target_job_title: campaign.target_job_title || "",
            business_model: campaign.business_model || :both,
            reach_owner?: campaign.reach_owner?,
            reach_title?: campaign.reach_title?,
            reach_generic?: campaign.reach_generic?,
            require_website?: campaign.require_website?,
            learnings: load_learnings(campaign.id),
            next_done?: suppression_present?(campaign),
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
       reach_owner?: parse_bool(params["reach_owner"], socket.assigns.reach_owner?),
       reach_title?: parse_bool(params["reach_title"], socket.assigns.reach_title?),
       reach_generic?: parse_bool(params["reach_generic"], socket.assigns.reach_generic?),
       require_website?: parse_bool(params["require_website"], socket.assigns.require_website?),
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
    owner? = parse_bool(params["reach_owner"], socket.assigns.reach_owner?)
    title? = parse_bool(params["reach_title"], socket.assigns.reach_title?)
    generic? = parse_bool(params["reach_generic"], socket.assigns.reach_generic?)
    website? = parse_bool(params["require_website"], socket.assigns.require_website?)

    rungs = %{
      reach_owner?: owner?,
      reach_title?: title?,
      reach_generic?: generic?,
      require_website?: website?
    }

    cond do
      not (owner? or title? or generic?) ->
        {:noreply,
         assign(socket,
           error: gettext("Pick at least one way to reach someone.")
         )}

      title? and title == "" ->
        {:noreply, assign(socket, error: gettext("Add a target job title, or untick that rung."))}

      true ->
        case Campaign.set_icp(socket.assigns.campaign, icp, title, business_model, rungs,
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

  defp suppression_present?(%{suppressed_count: n}) when is_integer(n), do: n > 0
  defp suppression_present?(_), do: false

  defp parse_business_model("b2b", _), do: :b2b
  defp parse_business_model("b2c", _), do: :b2c
  defp parse_business_model("both", _), do: :both
  defp parse_business_model(_, fallback), do: fallback

  defp parse_bool("true", _), do: true
  defp parse_bool("false", _), do: false
  defp parse_bool(_, fallback), do: fallback

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
              <label class="text-[10.5px] tracking-[0.08em] uppercase text-inkFaint font-semibold">
                {gettext("Who should we reach?")}
              </label>
              <div class="text-[12px] text-inkSoft mt-1">
                {gettext(
                  "Tried in this order, top to bottom — we stop at the first one we find. Tick only the ones you're happy to email."
                )}
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <div class="px-3.5 py-3 border border-border rounded-[8px] bg-bgSoft">
                <input type="hidden" name="reach_owner" value="false" />
                <label class="flex items-center gap-2.5 text-[13px] text-ink cursor-pointer">
                  <input
                    type="checkbox"
                    name="reach_owner"
                    value="true"
                    checked={@reach_owner?}
                    class="accent-accent w-[15px] h-[15px]"
                  />
                  <span class="font-semibold">{gettext("Owner")}</span>
                </label>
                <div class="text-[11.5px] text-inkSoft mt-1 ml-[25px] leading-[1.5]">
                  {gettext(
                    "The person who registered the company, when the registry's contact address is theirs rather than a shared inbox. No website needed."
                  )}
                </div>
              </div>

              <div class="px-3.5 py-3 border border-border rounded-[8px] bg-bgSoft">
                <input type="hidden" name="reach_title" value="false" />
                <label class="flex items-center gap-2.5 text-[13px] text-ink cursor-pointer">
                  <input
                    type="checkbox"
                    name="reach_title"
                    value="true"
                    checked={@reach_title?}
                    class="accent-accent w-[15px] h-[15px]"
                  />
                  <span class="font-semibold">{gettext("Job title")}</span>
                </label>
                <div class="text-[11.5px] text-inkSoft mt-1 ml-[25px] leading-[1.5]">
                  {gettext(
                    "Read the company's contact pages and pick the best match. List titles in order of importance — we take the highest-priority one found."
                  )}
                </div>
                <input
                  id="title"
                  type="text"
                  name="target_job_title"
                  value={@target_job_title}
                  disabled={not @reach_title?}
                  placeholder={gettext("Sales Manager, COO, CEO")}
                  phx-debounce="200"
                  class={[
                    "w-full mt-2.5 ml-[25px] max-w-[calc(100%-25px)] px-4 py-2.5 border border-borderStrong bg-card text-[14px] text-ink rounded-[8px] outline-none placeholder:text-inkFaint focus:border-accent focus:[box-shadow:0_0_0_3px_var(--accentSoft)]",
                    not @reach_title? && "opacity-40 cursor-not-allowed"
                  ]}
                />
              </div>

              <div class="px-3.5 py-3 border border-border rounded-[8px] bg-bgSoft">
                <input type="hidden" name="reach_generic" value="false" />
                <label class="flex items-center gap-2.5 text-[13px] text-ink cursor-pointer">
                  <input
                    type="checkbox"
                    name="reach_generic"
                    value="true"
                    checked={@reach_generic?}
                    class="accent-accent w-[15px] h-[15px]"
                  />
                  <span class="font-semibold">{gettext("Generic inbox")}</span>
                </label>
                <div class="text-[11.5px] text-inkSoft mt-1 ml-[25px] leading-[1.5]">
                  {gettext(
                    "The company's shared mailbox — info@, contact@ and the like. Nobody's name on it, so expect a colder reception."
                  )}
                </div>
              </div>
            </div>
          </div>

          <div class="bg-card border border-border rounded-[11px] p-5 [box-shadow:var(--shadow)]">
            <input type="hidden" name="require_website" value="false" />
            <label class="flex items-center gap-2.5 text-[13px] text-ink cursor-pointer">
              <input
                type="checkbox"
                name="require_website"
                value="true"
                checked={@require_website?}
                class="accent-accent w-[15px] h-[15px]"
              />
              <span class="font-semibold">{gettext("Target must have a website")}</span>
            </label>
            <div class="text-[11.5px] text-inkSoft mt-1.5 ml-[25px] leading-[1.5]">
              {gettext(
                "We look for a site on the registry first, then search for one. Companies where we still find nothing are dropped."
              )}
            </div>
            <div
              :if={not @require_website?}
              class="flex items-start gap-2 mt-3 ml-[25px] px-3 py-2.5 border border-amber/25 bg-amberSoft rounded-[8px]"
            >
              <span class="text-[9px] tracking-[0.1em] uppercase font-semibold text-amber shrink-0 mt-[3px]">
                {gettext("note")}
              </span>
              <span class="flex-1 text-[11.5px] text-inkSoft leading-[1.5]">
                {gettext(
                  "Keeps small companies that have no site at all — often exactly the ones you want. But the ICP check reads a company's website, so with nothing to read it can't run: those companies are targeted on your filters alone. Companies that do have a site are still ICP-checked as normal."
                )}
              </span>
            </div>
          </div>

          <div :if={@error} class="text-[12px] text-red">{@error}</div>

          <div class="flex flex-wrap items-center gap-4 mt-2">
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
