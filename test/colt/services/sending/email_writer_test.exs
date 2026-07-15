defmodule Colt.Services.Sending.EmailWriterTest do
  # Touches the DB only for the (empty) few-shot example lookups; the focus is
  # the prompt construction around the sending account's name.
  use Colt.DataCase, async: false

  alias Colt.Services.Sending.EmailWriter

  defp base_ctx(sender) do
    %{
      contact: %{id: Ash.UUID.generate(), campaign_id: Ash.UUID.generate()},
      sequence: %{id: Ash.UUID.generate()},
      person: %{name: "Mart Tamm", title: "CTO", email: "mart@acme.ee"},
      company: nil,
      sender: sender,
      pitch: nil,
      language: "en",
      email_steps: [%{kind: :email, position: 0, delay_days: 0}],
      ooo_step: nil,
      ooo_in_pool?: false,
      all_steps: [%{kind: :email, position: 0, delay_days: 0}]
    }
  end

  test "prompt names the sender and tells the model to write as them" do
    sender = %{display_name: "Robert Kuusk", address: "robert@liidid.ee"}

    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(sender))

    assert prompt.user =~ "Robert Kuusk"
    assert prompt.user =~ "robert@liidid.ee"
    # System rule: use the sender's name, never one from the examples.
    assert prompt.system =~ "Sender identity"
    assert prompt.system =~ "never a name"
  end

  test "includes the full multi-line signature so its details survive" do
    sig = "Robert Kuusk\nHead of Sales, Liidid\n+372 5555 1234"
    sender = %{display_name: sig, address: "robert@liidid.ee"}

    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(sender))

    # The phone/title must reach the model, not just the name.
    assert prompt.user =~ "+372 5555 1234"
    assert prompt.user =~ "Head of Sales, Liidid"
    # Name for the intro is the first line of the signature.
    assert prompt.user =~ "Name: Robert Kuusk"
  end

  test "starter_body seeds the signature with blank lines above it" do
    sig = "Robert Kuusk\n+372 5555 1234"
    assert EmailWriter.starter_body(%{display_name: sig}) == "\n\n" <> sig
    assert EmailWriter.starter_body(%{display_name: nil}) == nil
    assert EmailWriter.starter_body(%{display_name: "   "}) == nil
  end

  test "falls back to a humanized email local-part when signature is blank" do
    sender = %{display_name: nil, address: "siim.kask@liids.ee"}

    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(sender))

    assert prompt.user =~ "Siim Kask"
  end

  test "tolerates a missing sender without inventing a name" do
    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(nil))

    assert prompt.user =~ "no sender assigned"
  end
end
