# Phase 4a sanity-check one-liners. Each block is independently runnable via:
#
#     mix run priv/scripts/dev_helpers.exs
#
# Comment in the block you want; leave the rest off.
#
# Requires env: OPENROUTER_API_KEY, GOOGLE_CSE_API_KEY, GOOGLE_CSE_ENGINE_ID.
# Wallaby additionally requires `chromedriver` on PATH.

# ── 1. AI · cheap ───────────────────────────────────────────────────────────
# Colt.Services.Ai.Complete.run(:cheap, "Reply with the single word: hi")
# |> IO.inspect(label: "ai cheap")

# ── 2. AI · smart + JSON ────────────────────────────────────────────────────
# Colt.Services.Ai.Complete.run(
#   :smart,
#   [%{role: "user", content: ~s|Return {"ok": true} as JSON.|}],
#   response_format: :json,
#   max_tokens: 64
# )
# |> IO.inspect(label: "ai smart json")

# ── 3. AI · smart with cached system prompt ─────────────────────────────────
# system = "You are a curt assistant. Reply in <=5 words."
# for n <- 1..2 do
#   Colt.Services.Ai.Complete.run(:smart, "ping #{n}", system: system, max_tokens: 32)
#   |> IO.inspect(label: "ai cached #{n}")
# end

# ── 4. Search · Google CSE ──────────────────────────────────────────────────
# Colt.Services.Search.Google.run("bolt.eu")
# |> IO.inspect(label: "google", limit: 3)

# ── 5. Scrape · static-only target ──────────────────────────────────────────
# Colt.Services.Scrape.Fetch.run("https://example.com")
# |> case do
#   {:ok, %{fetcher: f, html: html}} -> IO.puts("static target → fetcher=#{f}, #{byte_size(html)}B")
#   other -> IO.inspect(other, label: "scrape")
# end

# ── 6. Scrape · SPA fallback (pick a real SPA URL) ──────────────────────────
# Colt.Services.Scrape.Fetch.run("https://your-spa-here.example")
# |> case do
#   {:ok, %{fetcher: f, html: html}} -> IO.puts("spa target → fetcher=#{f}, #{byte_size(html)}B")
#   other -> IO.inspect(other, label: "scrape spa")
# end

# ── 7. Markdown ─────────────────────────────────────────────────────────────
# {:ok, html} = Colt.Services.Scrape.Static.run("https://example.com") |> elem(1) |> then(&{:ok, &1.html})
# {:ok, md} = Colt.Services.Markdown.FromHtml.run(html)
# IO.puts("markdown bytes: #{byte_size(md)} (vs html #{byte_size(html)})")

# ── 8. Locks · serialize 3 concurrent calls on the same host ────────────────
# host = "example.com"
# task = fn id ->
#   Task.async(fn ->
#     Colt.Locks.with_domain_lock(host, fn ->
#       IO.puts("[#{id}] enter @ #{System.system_time(:millisecond)}")
#       Process.sleep(500)
#       IO.puts("[#{id}] leave @ #{System.system_time(:millisecond)}")
#     end)
#   end)
# end
# [task.(1), task.(2), task.(3)] |> Enum.each(&Task.await(&1, 5_000))

# ── 9. Broadcast · publish + receive ────────────────────────────────────────
# campaign_id = "test-campaign"
# :ok = Colt.Enrichment.Broadcast.subscribe(campaign_id)
# Colt.Enrichment.Broadcast.stage(campaign_id, "cc-id", :web, :work)
# receive do
#   msg -> IO.inspect(msg, label: "broadcast")
# after
#   1_000 -> IO.puts("broadcast: nothing received")
# end

# ── 10. Costs · monthly summary ─────────────────────────────────────────────
# Colt.Services.Costs.MonthlySummary.run(3) |> IO.inspect(label: "monthly")

IO.puts("dev_helpers.exs loaded — uncomment a block to run it")
