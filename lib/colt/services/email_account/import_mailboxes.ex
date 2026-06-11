defmodule Colt.Services.EmailAccount.ImportMailboxes do
  @moduledoc """
  Parse a mailbox-export CSV into a list of importable inbox specs. Pure —
  no Nylas calls, no DB writes. The caller (the Email accounts LiveView)
  enqueues one `Colt.Jobs.ImportMailbox` per spec we return.

  Two formats are auto-detected from the header row:

    * **IMAP** (`"IMAP Host"` column present) — generic IMAP/SMTP inboxes,
      e.g. the mailpool.io export. Host/port/creds come straight from the file.
    * **Google Workspace** (`"App Password"` column present) — connected over
      Gmail IMAP using the app password (not the plain password). The `Secret`
      and `Admin*` columns are ignored — they're for TOTP/admin-OAuth flows we
      don't use here.

  Both land as `provider: :imap` grants in Nylas.
  """

  alias NimbleCSV.RFC4180, as: CSV

  @default_tz "Europe/Tallinn"
  @gmail_imap_host "imap.gmail.com"
  @gmail_imap_port 993
  @gmail_smtp_host "smtp.gmail.com"
  @gmail_smtp_port 465

  @type mailbox :: %{
          address: String.t(),
          display_name: String.t() | nil,
          tz: String.t(),
          settings: map()
        }

  @doc """
  Returns `{:ok, [mailbox]}` or `{:error, :empty | :unknown_format}`.
  """
  @spec run(String.t()) :: {:ok, [mailbox]} | {:error, :empty | :unknown_format}
  def run(csv_text) when is_binary(csv_text) do
    with {:ok, headers, rows} <- parse(csv_text),
         {:ok, mailboxes} <- build(headers, rows) do
      {:ok, mailboxes}
    end
  end

  defp parse(csv_text) do
    case csv_text |> strip_bom() |> CSV.parse_string(skip_headers: false) do
      [headers | rows] -> {:ok, headers, rows}
      _ -> {:error, :empty}
    end
  end

  defp build(headers, rows) do
    cond do
      "IMAP Host" in headers -> {:ok, rows_to_mailboxes(headers, rows, &imap_mailbox/1)}
      "App Password" in headers -> {:ok, rows_to_mailboxes(headers, rows, &google_mailbox/1)}
      true -> {:error, :unknown_format}
    end
  end

  defp rows_to_mailboxes(headers, rows, builder) do
    rows
    |> Enum.map(fn row -> headers |> Enum.zip(row) |> Map.new() end)
    |> Enum.map(builder)
    |> Enum.reject(&blank?(&1.address))
  end

  # Generic IMAP/SMTP export (mailpool.io etc.).
  defp imap_mailbox(r) do
    %{
      address: r["Email"],
      display_name: full_name(r["First Name"], r["Last Name"]),
      tz: @default_tz,
      settings: %{
        "imap_username" => r["IMAP Username"],
        "imap_password" => r["IMAP Password"],
        "imap_host" => r["IMAP Host"],
        "imap_port" => to_port(r["IMAP Port"]),
        "smtp_username" => r["SMTP Username"],
        "smtp_password" => r["SMTP Password"],
        "smtp_host" => r["SMTP Host"],
        "smtp_port" => to_port(r["SMTP Port"])
      }
    }
  end

  # Google Workspace over Gmail IMAP, authenticated with the app password.
  defp google_mailbox(r) do
    address = r["Email"]
    app_password = r["App Password"]

    %{
      address: address,
      display_name: nil,
      tz: @default_tz,
      settings: %{
        "imap_username" => address,
        "imap_password" => app_password,
        "imap_host" => @gmail_imap_host,
        "imap_port" => @gmail_imap_port,
        "smtp_username" => address,
        "smtp_password" => app_password,
        "smtp_host" => @gmail_smtp_host,
        "smtp_port" => @gmail_smtp_port
      }
    }
  end

  defp full_name(first, last) do
    [first, last]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp to_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_port(_), do: nil

  defp strip_bom(text), do: String.replace_leading(text, "﻿", "")

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
