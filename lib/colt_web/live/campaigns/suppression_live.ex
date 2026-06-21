defmodule ColtWeb.Campaigns.SuppressionLive do
  @moduledoc """
  Campaign setup step 05 — "Already contacted". Upload any export of emails
  you've already sent; we regex out every address, reduce to unique domains, and
  store them so enrichment skips matching companies before spending scrape/AI
  budget. Format-agnostic — separators, headers, and columns don't matter.
  """
  use ColtWeb, :live_view

  alias Colt.Resources.{Campaign, SuppressedDomain}
  alias Colt.Services.Enrichment.Suppression
  alias ColtWeb.Components.Liid

  on_mount {ColtWeb.LiveUserAuth, :live_plan_required}

  @max_file_size 20_000_000

  def mount(%{"id" => id}, _session, socket) do
    case Campaign.get(id, actor: socket.assigns.current_user) do
      {:ok, campaign} ->
        socket =
          socket
          |> assign(
            page_title: gettext("Exclude — %{name}", name: campaign.name),
            campaign: campaign,
            domains: load_domains(campaign.id),
            added: nil,
            error: nil
          )
          |> allow_upload(:csv,
            accept: ~w(.csv .txt text/csv text/plain),
            max_entries: 1,
            max_file_size: @max_file_size
          )

        {:ok, socket}

      {:error, _} ->
        {:ok, push_navigate(socket, to: ~p"/campaigns/new")}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, error: nil)}
  end

  def handle_event("save", _params, socket) do
    campaign_id = socket.assigns.campaign.id

    domains =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        domains =
          path
          |> File.stream!(read_ahead: 64 * 1024)
          |> Suppression.domains_from_text()

        {:ok, domains}
      end)
      |> List.flatten()

    case domains do
      [] ->
        {:noreply,
         assign(socket, error: gettext("No email domains found in that file."), added: nil)}

      domains ->
        before = MapSet.new(Enum.map(socket.assigns.domains, & &1.domain))

        Enum.map(domains, &%{campaign_id: campaign_id, domain: &1})
        |> Ash.bulk_create!(SuppressedDomain, :create,
          upsert?: true,
          upsert_identity: :campaign_domain,
          upsert_fields: [:domain],
          return_errors?: true,
          stop_on_error?: true,
          authorize?: false
        )

        added = Enum.count(domains, &(not MapSet.member?(before, &1)))

        {:noreply, assign(socket, domains: load_domains(campaign_id), added: added, error: nil)}
    end
  end

  def handle_event("clear", _params, socket) do
    Ash.bulk_destroy!(socket.assigns.domains, :destroy, %{}, authorize?: false)

    {:noreply,
     assign(socket, domains: load_domains(socket.assigns.campaign.id), added: nil, error: nil)}
  end

  defp load_domains(campaign_id) do
    case SuppressedDomain.list_for_campaign(campaign_id, authorize?: false) do
      {:ok, domains} -> domains
      _ -> []
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      step={4}
      campaign={@campaign}
      campaign_name={@campaign.name}
      campaign_id={@campaign.id}
    >
      <div class="flex flex-col gap-8 max-w-[640px] mx-auto py-12">
        <div class="text-[10.5px] tracking-[0.09em] uppercase text-inkFaint font-semibold">
          {gettext("05 / Exclude · %{name}", name: @campaign.name)}
        </div>
        <h1 class="font-semibold text-[25px] md:text-[28px] leading-[1.15] tracking-[-0.02em] m-0 text-ink">
          {raw(gettext("Skip the <em>already contacted</em>."))}
        </h1>
        <p class="text-[14px] leading-[1.5] text-inkSoft max-w-[520px]">
          {gettext(
            "Upload a CSV of people you've already emailed. We pull out the unique domains and skip any matching company during enrichment — before we spend a cent scraping it."
          )}
        </p>

        <form phx-change="validate" phx-submit="save" autocomplete="off">
          <div
            class="border border-dashed border-borderStrong rounded-[11px] px-6 py-10 text-center bg-card [box-shadow:var(--shadow)]"
            phx-drop-target={@uploads.csv.ref}
          >
            <div class="text-[11px] tracking-[0.08em] uppercase text-inkSoft font-semibold mb-2">
              {gettext("Export of sent emails")}
            </div>
            <div class="text-[12px] text-inkFaint mb-5 max-w-[420px] mx-auto leading-[1.5]">
              {gettext(
                "Drop any CSV or text export — straight from Smartlead, your inbox, wherever. We scan the whole file for email addresses and keep their domains. Separators, headers, and extra columns don't matter."
              )}
            </div>

            <.live_file_input upload={@uploads.csv} class="sr-only" />
            <label
              for={@uploads.csv.ref}
              class="inline-flex items-center gap-2 px-4 py-[7px] text-[12px] font-semibold border border-borderStrong bg-card rounded-[8px] text-inkSoft cursor-pointer hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
            >
              <Liid.icon name="file" size={12} /> {gettext("Choose file")}
            </label>

            <%= for entry <- @uploads.csv.entries do %>
              <div class="mt-4 text-[11px] text-inkSoft">{entry.client_name}</div>
              <%= for err <- upload_errors(@uploads.csv, entry) do %>
                <div class="mt-1 text-[11px] text-red">{upload_error_label(err)}</div>
              <% end %>
            <% end %>

            <div class="mt-6">
              <Liid.btn variant={:primary} type="submit" disabled={@uploads.csv.entries == []}>
                {gettext("Extract domains")} <Liid.icon name="arrow" />
              </Liid.btn>
            </div>
          </div>
        </form>

        <div :if={@added} class="text-[11px] text-inkSoft">
          {gettext("Added %{n} new domains.", n: @added)}
        </div>
        <div :if={@error} class="text-[11px] text-red">{@error}</div>

        <div class="flex flex-wrap items-center gap-3">
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/icp"}
            class="inline-flex items-center gap-2 px-3.5 py-[7px] text-[12px] font-semibold border border-borderStrong bg-card rounded-[8px] no-underline text-inkSoft hover:bg-paperAlt hover:text-ink [box-shadow:var(--shadow)]"
          >
            <Liid.icon name="chev-l" size={11} /> {gettext("Back")}
          </.link>
          <.link
            navigate={~p"/campaigns/#{@campaign.id}/target"}
            class="inline-flex items-center gap-2 px-[18px] py-[9px] text-[13px] font-semibold bg-accent text-white border border-accent rounded-[8px] no-underline [box-shadow:0_1px_2px_rgba(59,122,224,.3)] hover:bg-[#3169c8] hover:border-[#3169c8]"
          >
            {gettext("Continue → target")} <Liid.icon name="arrow" />
          </.link>
        </div>

        <div class="bg-card border border-border rounded-[11px] [box-shadow:var(--shadow)] p-4">
          <div class="flex items-center justify-between mb-3">
            <div class="text-[10px] tracking-[0.12em] uppercase text-inkSoft font-semibold">
              {gettext("Excluded domains (%{n})", n: length(@domains))}
            </div>
            <button
              :if={@domains != []}
              type="button"
              phx-click="clear"
              data-confirm={gettext("Remove all excluded domains for this campaign?")}
              class="text-[10px] tracking-[0.08em] uppercase font-semibold text-inkFaint hover:text-red cursor-pointer"
            >
              {gettext("Clear all")}
            </button>
          </div>

          <div :if={@domains == []} class="text-[12px] text-inkFaint">
            {gettext("Nothing excluded yet. Upload a file above, or skip this step.")}
          </div>

          <ul
            :if={@domains != []}
            class="flex flex-col gap-1"
          >
            <li
              :for={d <- @domains}
              id={"sup-#{d.domain}"}
              class="text-[12px] text-ink px-3 py-1.5 bg-paperAlt rounded-[8px]"
            >
              {d.domain}
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error_label(:too_large), do: gettext("File is too large (max 20 MB).")
  defp upload_error_label(:not_accepted), do: gettext("That's not a CSV file.")
  defp upload_error_label(:too_many_files), do: gettext("Upload one file at a time.")
  defp upload_error_label(_), do: gettext("Upload failed.")
end
