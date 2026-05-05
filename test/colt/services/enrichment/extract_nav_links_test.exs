defmodule Colt.Services.Enrichment.ExtractNavLinksTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Enrichment.ExtractNavLinks

  test "pulls same-host paths from nav, header, footer; skips externals + mailto" do
    html = """
    <html><body>
      <header>
        <a href="/about">About</a>
        <a href="https://twitter.com/x">Twitter</a>
      </header>
      <nav>
        <a href="/team/">  Team </a>
        <a href="mailto:a@b.com">mail</a>
      </nav>
      <footer>
        <a href="https://www.example.com/contact">Contact</a>
        <a href="#top">Top</a>
      </footer>
      <main><a href="/hidden">Hidden</a></main>
    </body></html>
    """

    {:ok, links} = ExtractNavLinks.run(html, "https://example.com/")

    paths = Enum.map(links, & &1.path) |> Enum.sort()
    assert paths == ["/about", "/contact", "/team"]
    assert Enum.find(links, &(&1.path == "/about")).title == "About"
  end

  test "blank html → empty list" do
    assert {:ok, []} = ExtractNavLinks.run("", "https://example.com/")
  end
end
