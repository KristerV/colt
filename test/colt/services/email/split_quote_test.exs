defmodule Colt.Services.Email.SplitQuoteTest do
  use ExUnit.Case, async: true

  alias Colt.Services.Email.SplitQuote

  test "splits an Outlook From:/Sent:/To: header block" do
    text = """
    Tere Krister

    Saada video.

    From: oscar@liids.ee <oscar@liids.ee>
    Sent: Monday, June 15, 2026 4:15 PM
    To: rene@diamantek.ee
    Subject: ukselingide müük
    """

    assert {:ok, %{body: body, quoted: quoted}} = SplitQuote.run(text)
    assert body == "Tere Krister\n\nSaada video."
    assert quoted =~ "From: oscar@liids.ee"
  end

  test "splits a Gmail attribution line" do
    text = "Sounds good!\n\nOn Mon, Jun 15, 2026 at 4:15 PM Oscar <oscar@liids.ee> wrote:\npitch"

    assert {:ok, %{body: "Sounds good!", quoted: quoted}} = SplitQuote.run(text)
    assert quoted =~ "wrote:"
  end

  test "splits an Estonian attribution line" do
    text = "Sobib!\n\nOn 15.06.2026 Oscar kirjutas:\npitch"
    assert {:ok, %{body: "Sobib!", quoted: quoted}} = SplitQuote.run(text)
    assert quoted =~ "kirjutas:"
  end

  test "splits on the Original Message divider and on > prefixes" do
    assert {:ok, %{body: "Jah", quoted: q1}} =
             SplitQuote.run("Jah\n\n----- Original Message -----\nold")

    assert q1 =~ "Original Message"

    assert {:ok, %{body: "Jah", quoted: "> old"}} = SplitQuote.run("Jah\n\n> old")
  end

  test "leaves an unquoted message whole" do
    assert {:ok, %{body: "Tere\n\nKrister", quoted: nil}} = SplitQuote.run("Tere\n\nKrister")
  end

  test "keeps the message whole when it is entirely quote" do
    text = "> only quoted content"
    assert {:ok, %{body: ^text, quoted: nil}} = SplitQuote.run(text)
  end

  test "does not treat a prose mention of from: as a quote" do
    text = "The order is from: our Tartu warehouse, shipping Monday."
    assert {:ok, %{body: ^text, quoted: nil}} = SplitQuote.run(text)
  end
end
