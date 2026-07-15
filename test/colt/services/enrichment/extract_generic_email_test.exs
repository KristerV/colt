defmodule Colt.Services.Enrichment.ExtractGenericEmailTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ExtractGenericEmail

  # The AI pass is stubbed everywhere below so the default suite stays pure and
  # offline. A live-model check of the real classifier lives in
  # ClassifyEmailAddressTest, tagged :eval.
  defp stub(verdicts) do
    fn email, _opts -> {:ok, Map.get(verdicts, email, :personal)} end
  end

  defp never_called do
    fn email, _opts -> flunk("classifier should not have been called, got #{email}") end
  end

  describe "keyword pass" do
    test "matches a generic mailbox on the host" do
      html = ~s|<p>Reach us: <a href="mailto:hello@acme.io">Hello</a></p>|
      assert {:ok, "hello@acme.io"} = ExtractGenericEmail.run(html, "acme.io")
    end

    test "matches subdomain of host" do
      html = "Sales: sales@eu.acme.io"
      assert {:ok, "sales@eu.acme.io"} = ExtractGenericEmail.run(html, "acme.io")
    end

    test "a keyword hit never reaches the classifier" do
      html = "info@acme.io and alice@acme.io"

      assert {:ok, "info@acme.io"} =
               ExtractGenericEmail.run(html, "acme.io", classifier: never_called())
    end

    test "ignores mailboxes on other domains" do
      html = "support@otherdomain.com"
      assert {:ok, nil} = ExtractGenericEmail.run(html, "acme.io", classifier: never_called())
    end

    test "a page with no addresses at all never reaches the classifier" do
      html = "<p>Call us on 555-0100.</p>"
      assert {:ok, nil} = ExtractGenericEmail.run(html, "acme.io", classifier: never_called())
    end
  end

  describe "AI pass" do
    test "finds a shared inbox the keyword list doesn't know" do
      html = "<p>tere@acme.io</p>"

      assert {:ok, "tere@acme.io"} =
               ExtractGenericEmail.run(html, "acme.io",
                 classifier: stub(%{"tere@acme.io" => :generic})
               )
    end

    test "ignores personal-name addresses" do
      html = "alice@acme.io"

      assert {:ok, nil} =
               ExtractGenericEmail.run(html, "acme.io",
                 classifier: stub(%{"alice@acme.io" => :personal})
               )
    end

    test "keeps the first generic address, skipping people before it" do
      html = "alice@acme.io bob@acme.io kontor@acme.io myyk@acme.io"

      assert {:ok, "kontor@acme.io"} =
               ExtractGenericEmail.run(html, "acme.io",
                 classifier: stub(%{"kontor@acme.io" => :generic, "myyk@acme.io" => :generic})
               )
    end

    test "still refuses a third-party host" do
      html = "kontakt@someoneelse.com"

      assert {:ok, nil} =
               ExtractGenericEmail.run(html, "acme.io", classifier: never_called())
    end

    test "caps how many addresses it will pay to classify" do
      # 12 personal addresses, and the only shared inbox is last — past the cap,
      # so it must not be found and must not cost 12 calls.
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      html =
        (1..12 |> Enum.map_join(" ", &"person#{&1}@acme.io")) <> " info2@acme.io"

      counting = fn _email, _opts ->
        Agent.update(agent, &(&1 + 1))
        {:ok, :personal}
      end

      assert {:ok, nil} = ExtractGenericEmail.run(html, "acme.io", classifier: counting)
      assert Agent.get(agent, & &1) == 8
    end
  end
end
