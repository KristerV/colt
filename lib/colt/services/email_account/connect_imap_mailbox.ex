defmodule Colt.Services.EmailAccount.ConnectImapMailbox do
  @moduledoc """
  Connect one inbox from raw IMAP/SMTP credentials: create a Nylas grant via
  custom auth, then persist the `EmailAccount`. Driven per-row by
  `Colt.Jobs.ImportMailbox` during CSV import.

  Idempotent on re-import: if the user already has a still-connected inbox for
  this address we return it untouched rather than minting a second Nylas grant
  (which Nylas would bill separately).

  `mailbox` is a string-keyed map — `"address"`, `"display_name"`, `"tz"`,
  `"settings"` — as produced by `Colt.Services.EmailAccount.ImportMailboxes`
  and round-tripped through Oban args.
  """

  alias Colt.Accounts.User
  alias Colt.Nylas
  alias Colt.Resources.EmailAccount

  @default_tz "Europe/Tallinn"

  @spec run(String.t(), map()) :: {:ok, EmailAccount.t()} | {:error, term()}
  def run(user_id, mailbox) when is_binary(user_id) and is_map(mailbox) do
    with {:ok, user} <- fetch_user(user_id),
         :new <- already_connected_or_new(user_id, mailbox["address"]),
         {:ok, grant} <- Nylas.create_imap_grant(mailbox["settings"]),
         {:ok, account} <- persist(user, mailbox, grant) do
      {:ok, account}
    else
      {:already, account} -> {:ok, account}
      {:error, _} = err -> err
    end
  end

  defp fetch_user(user_id), do: Ash.get(User, user_id, authorize?: false)

  # The lookup is a `get?` action: it returns {:error, NotFound} when there's no
  # match, which for us is the happy path — proceed and mint a grant. A hit means
  # this inbox is already connected; return it untouched (no duplicate grant).
  defp already_connected_or_new(user_id, address) do
    case EmailAccount.get_active_for_address(user_id, address, authorize?: false) do
      {:ok, %EmailAccount{} = existing} -> {:already, existing}
      _ -> :new
    end
  end

  defp persist(user, mailbox, grant) do
    EmailAccount.create_from_nylas(
      :imap,
      mailbox["address"],
      mailbox["display_name"],
      grant_id!(grant),
      mailbox["tz"] || @default_tz,
      actor: user
    )
  end

  # Custom auth returns the grant object as `%{"id" => ...}`; be tolerant of the
  # token-endpoint shape (`"grant_id"`) too.
  defp grant_id!(%{"id" => id}) when is_binary(id), do: id
  defp grant_id!(%{"grant_id" => id}) when is_binary(id), do: id
end
