defmodule Colt.Jobs.Enrichment.VerifyEmail do
  @moduledoc """
  Final stage. Hits MyEmailVerifier on the picked contact's email.

  * `:valid` → mark CC `:enriched`.
  * `:catch_all` → also `:enriched`. Every address that reaches this job was
    either published by a human on the company's own site or filed with the
    registry, so a catch-all domain doesn't cast doubt on it — it just means the
    check was uninformative. This stops being true once the owner rung learns to
    *guess* addresses (see `docs/todo.md`); a guessed address on a catch-all
    domain must not be trusted, and that resolver has to check the status itself
    rather than lean on this job.
  * `:invalid` → mark CC `:verify_failed` (terminal, lands in Failed bucket).
  * transport error → `{:error, _}` so Oban retries; once attempts run out,
    `Oban.PerformError` discards the job and we mark `:failed` (stage
    `:verify`) so the funnel doesn't show a permanently-spinning row.
  """
  use Oban.Worker, queue: :ai, max_attempts: 3, priority: 1

  require Logger

  alias Colt.Resources.{CampaignCompany, Person}

  alias Colt.Services.Enrichment.{
    Broadcast,
    FailureMessage,
    Transition,
    VerifyEmail
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_company_id" => id}, attempt: attempt} = job) do
    with {:ok, cc} <- CampaignCompany.get(id),
         {:ok, cc} <- Transition.resume(cc) do
      cond do
        cc.status in [:verify_failed, :enriched] ->
          :ok

        cc.picked_person_id == nil ->
          # ExtractContacts decided no one was worth picking; nothing to
          # verify. Treat as :no_contacts so we don't burn an API call.
          Transition.stage(cc, :verify, :fall)

          {:ok, _} =
            Transition.terminate(cc, :no_contacts, reason: "no contact to verify")

          :ok

        true ->
          do_perform(cc, attempt, job.max_attempts)
      end
    end
  end

  defp do_perform(cc, attempt, max_attempts) do
    {:ok, person} = Person.get(cc.picked_person_id)

    cond do
      cached_valid?(person) ->
        broadcast_done(cc)

      cached_invalid?(person) ->
        broadcast_invalid(cc, person.email)

      true ->
        Broadcast.stage(cc.campaign_id, cc.id, :verify, :work)
        call_api(cc, person, attempt, max_attempts)
    end
  end

  defp call_api(cc, person, attempt, max_attempts) do
    case VerifyEmail.run(person.email) do
      {:ok, status} when status in [:valid, :catch_all] ->
        {:ok, _} = Person.set_verification(person, status)
        broadcast_done(cc)

      {:ok, :invalid} ->
        {:ok, _} = Person.set_verification(person, :invalid)
        broadcast_invalid(cc, person.email)

      {:error, reason} when attempt >= max_attempts ->
        {user_msg, detail} = FailureMessage.run(:verify, reason)
        Transition.stage(cc, :verify, :fail)

        {:ok, _} =
          Transition.terminate(cc, :failed,
            stage: :verify,
            reason: user_msg,
            detail: detail
          )

        :ok

      {:error, reason} ->
        # Let Oban retry — Req already did transport-level backoff inside
        # the service. We're catching genuine intermittent failure.
        {:error, reason}
    end
  end

  defp broadcast_done(cc) do
    Transition.stage(cc, :verify, :done)
    {:ok, _} = Transition.terminate(cc, :enriched)
    :ok
  end

  defp broadcast_invalid(cc, email) do
    Transition.stage(cc, :verify, :fail)

    {:ok, _} =
      Transition.terminate(cc, :verify_failed, reason: "email did not verify: #{email}")

    :ok
  end

  defp cached_valid?(%{email_verification_status: s}) when s in [:valid, :catch_all], do: true
  defp cached_valid?(_), do: false

  defp cached_invalid?(%{email_verification_status: :invalid}), do: true
  defp cached_invalid?(_), do: false
end
