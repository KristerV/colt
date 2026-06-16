defmodule Colt.Services.Sending.EmailWriterTest do
  # Touches the DB only for the (empty) few-shot example lookups; the focus is
  # the prompt construction around the sending account's name.
  use Colt.DataCase, async: false

  alias Colt.Services.Sending.EmailWriter

  defp base_ctx(sender) do
    %{
      contact: %{id: Ash.UUID.generate(), campaign_id: Ash.UUID.generate()},
      person: %{name: "Mart Tamm", title: "CTO", email: "mart@acme.ee"},
      company: nil,
      sender: sender,
      pitch: nil,
      language: "en",
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

  test "falls back to a humanized email local-part when display name is blank" do
    sender = %{display_name: nil, address: "siim.kask@liids.ee"}

    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(sender))

    assert prompt.user =~ "Siim Kask"
  end

  test "tolerates a missing sender without inventing a name" do
    {:ok, prompt} = EmailWriter.prompt_for(base_ctx(nil))

    assert prompt.user =~ "no sender assigned"
  end
end
