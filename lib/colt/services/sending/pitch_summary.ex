defmodule Colt.Services.Sending.PitchSummary do
  @moduledoc """
  Read a sender's website and summarize "what they sell" for the EmailWriter.

  Pipeline:
    1. Fetch the landing page.
    2. Extract nav links.
    3. Ask Claude (cheap) to pick up to 3 product/about-style paths.
    4. Fetch each, convert to markdown.
    5. Ask Claude (smart) to summarize the offer — what + for whom + value prop.
    6. Persist via `Pitch.finish_fetch/3`. That action discards stale results
       (mismatched `fetch_ref`) so a newer domain change always wins.

  Run with `run/2` from a Task; the caller has already flipped `fetching? = true`
  and stored the `fetch_ref`.
  """

  alias Colt.Resources.Pitch
  alias Colt.Services.Ai.Complete
  alias Colt.Services.Enrichment.ExtractNavLinks
  alias Colt.Services.Markdown.FromHtml
  alias Colt.Services.Scrape.Fetch

  @pick_schema %{
    type: "object",
    additionalProperties: false,
    required: ["paths"],
    properties: %{
      paths: %{
        type: "array",
        maxItems: 3,
        items: %{type: "string"}
      }
    }
  }

  @pick_system """
  You pick up to 3 paths from a company's own website that best describe WHAT
  THEY SELL — products, services, pricing, features, "about us", "what we do".

  Skip: contact, careers/jobs, blog posts, news, legal, login/signup, language
  switchers, social links, customer logins.

  If multiple candidates fit, prefer hub pages over deep sub-pages. Return JSON.
  """

  @summary_system """
  You write a short, plain-language summary of a company's offer for use as
  context when writing cold-outreach emails on the company's behalf.

  Cover:
  - What they sell (product / service)
  - Who it's for (target customer)
  - The 1–2 value props they lead with

  Keep it 3–6 sentences. No marketing fluff, no superlatives, no emoji.
  Plain text, no Markdown.
  """

  def run(pitch_id, fetch_ref, opts \\ []) do
    actor = Keyword.get(opts, :actor)

    with {:ok, pitch} <- Pitch.get(pitch_id, actor: actor, authorize?: actor != nil),
         :ok <- ensure_fresh(pitch, fetch_ref),
         {:ok, base_url} <- normalise_url(pitch.domain),
         {:ok, landing} <- fetch_landing(base_url),
         {:ok, paths} <- pick_paths(landing.html, base_url, opts),
         {:ok, extra} <- fetch_extras(paths, base_url),
         {:ok, summary} <- summarize(landing.markdown, extra, opts) do
      persist(pitch, summary, fetch_ref, actor)
    else
      {:stale, _} -> {:ok, :stale}
      {:error, reason} -> handle_failure(pitch_id, fetch_ref, reason, actor)
    end
  end

  defp ensure_fresh(%{fetch_ref: ref}, ref), do: :ok
  defp ensure_fresh(_, _), do: {:stale, :ref_mismatch}

  defp normalise_url(nil), do: {:error, :no_domain}
  defp normalise_url(""), do: {:error, :no_domain}

  defp normalise_url(domain) do
    domain = String.trim(domain)

    cond do
      String.starts_with?(domain, "http://") or String.starts_with?(domain, "https://") ->
        {:ok, domain}

      true ->
        {:ok, "https://" <> domain}
    end
  end

  defp fetch_landing(url) do
    with {:ok, %{html: html, final_url: final}} <- Fetch.run(url),
         {:ok, markdown} <- FromHtml.run(html) do
      {:ok, %{html: html, markdown: markdown, final_url: final}}
    end
  end

  defp pick_paths(html, base_url, opts) do
    case ExtractNavLinks.run(html, base_url) do
      {:ok, []} ->
        {:ok, []}

      {:ok, links} ->
        listing =
          links
          |> Enum.take(40)
          |> Enum.map_join("\n", fn %{path: p, title: t} -> "- #{p}  (#{t || ""})" end)

        user = """
        Paths:
        #{listing}

        Pick up to 3 paths that best describe what this company sells.
        Return {"paths": ["/...", ...]}.
        """

        case Complete.run(:cheap, user,
               system: @pick_system,
               response_format: :json,
               schema: @pick_schema,
               campaign_id: opts[:campaign_id],
               subject: opts[:subject],
               task: "pick_pitch_paths",
               max_tokens: 2000
             ) do
          {:ok, %{content: %{"paths" => paths}}} when is_list(paths) ->
            {:ok, paths |> Enum.filter(&is_binary/1) |> Enum.take(3)}

          {:ok, _} ->
            {:ok, []}

          {:error, _} = err ->
            err
        end
    end
  end

  defp fetch_extras(paths, base_url) do
    base = URI.parse(base_url)

    markdowns =
      paths
      |> Enum.map(fn path ->
        url = base |> URI.merge(path) |> URI.to_string()

        with {:ok, %{html: html}} <- Fetch.run(url),
             {:ok, md} <- FromHtml.run(html) do
          %{path: path, markdown: md}
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, markdowns}
  end

  defp summarize(landing_md, extras, opts) do
    extras_section =
      extras
      |> Enum.map_join("\n\n", fn %{path: p, markdown: md} ->
        "### #{p}\n#{cap(md, 3000)}"
      end)

    user = """
    Landing page:
    #{cap(landing_md, 4000)}

    Extra pages:
    #{extras_section}

    Summarize what this company sells (3–6 sentences, plain text).
    """

    case Complete.run(:smart, user,
           system: @summary_system,
           temperature: 0.4,
           max_tokens: 700,
           campaign_id: opts[:campaign_id],
           subject: opts[:subject],
           task: "pitch_summary"
         ) do
      {:ok, %{content: text}} when is_binary(text) -> {:ok, String.trim(text)}
      {:ok, _} -> {:error, :empty_summary}
      {:error, _} = err -> err
    end
  end

  defp persist(pitch, summary, fetch_ref, actor) do
    case Pitch.finish_fetch(pitch, summary, fetch_ref, actor: actor, authorize?: actor != nil) do
      {:ok, p} -> {:ok, p}
      err -> err
    end
  end

  defp handle_failure(pitch_id, fetch_ref, _reason, actor) do
    # Always clear `fetching?` so the UI unlocks even if we crashed.
    with {:ok, pitch} <- Pitch.get(pitch_id, actor: actor, authorize?: actor != nil),
         :ok <- ensure_fresh(pitch, fetch_ref) do
      Pitch.finish_fetch(pitch, pitch.ai_summary, fetch_ref,
        actor: actor,
        authorize?: actor != nil
      )
    else
      _ -> {:ok, :stale}
    end
  end

  defp cap(nil, _), do: ""
  defp cap(s, n) when is_binary(s), do: String.slice(s, 0, n)
end
