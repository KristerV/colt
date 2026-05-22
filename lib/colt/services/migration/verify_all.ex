defmodule Colt.Services.Migration.VerifyAll do
  @moduledoc """
  One-shot backfill. Walks every CC that's currently `:enriched` (i.e. was
  finalised before the verify stage existed) and runs it through
  MyEmailVerifier. Updates the CC status to `:verify_failed` if the picked
  contact's email turns out to be undeliverable.

  Self-contained on purpose — no pipeline plumbing changes. Run once:

      mix run -e 'Colt.Services.Migration.VerifyAll.run()'
  """

  require Logger
  import Ecto.Query

  alias Colt.Repo
  alias Colt.Resources.{CampaignCompany, Person}
  alias Colt.Services.Enrichment.{Broadcast, Transition, VerifyEmail}

  @concurrency 4

  def run do
    ccs = load_enriched()
    Logger.info("[VerifyAll] #{length(ccs)} enriched CCs to verify")

    stats =
      ccs
      |> Task.async_stream(&verify_one/1,
        max_concurrency: @concurrency,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{valid: 0, invalid: 0, skipped: 0, errored: 0}, fn
        {:ok, key}, acc -> Map.update!(acc, key, &(&1 + 1))
        {:exit, _}, acc -> Map.update!(acc, :errored, &(&1 + 1))
      end)

    Logger.info("[VerifyAll] done: #{inspect(stats)}")
    {:ok, stats}
  end

  defp load_enriched do
    from(cc in CampaignCompany, where: cc.status == :enriched) |> Repo.all()
  end

  defp verify_one(%CampaignCompany{picked_person_id: nil} = cc) do
    Logger.info("[VerifyAll] cc=#{cc.id} has no picked_person, skipping")
    :skipped
  end

  defp verify_one(%CampaignCompany{picked_person_id: person_id} = cc) do
    {:ok, person} = Person.get(person_id)
    do_verify(cc, person)
  end

  defp do_verify(cc, %Person{email: nil}) do
    Logger.info("[VerifyAll] cc=#{cc.id} picked_person has no email, skipping")
    :skipped
  end

  defp do_verify(cc, %Person{} = person) do
    Broadcast.stage(cc.campaign_id, cc.id, :verify, :work)

    case VerifyEmail.run(person.email) do
      {:ok, :valid} ->
        {:ok, _} = Person.set_verification(person, :valid)
        Broadcast.stage(cc.campaign_id, cc.id, :verify, :done)
        Logger.info("[VerifyAll] cc=#{cc.id} #{person.email} => valid")
        :valid

      {:ok, :invalid} ->
        {:ok, _} = Person.set_verification(person, :invalid)
        Broadcast.stage(cc.campaign_id, cc.id, :verify, :fail)

        {:ok, _} =
          Transition.terminate(cc, :verify_failed,
            reason: "email did not verify: #{person.email}"
          )

        Logger.warning("[VerifyAll] cc=#{cc.id} #{person.email} => INVALID")
        :invalid

      {:error, reason} ->
        Logger.error("[VerifyAll] cc=#{cc.id} #{person.email} verifier error: #{inspect(reason)}")
        :errored
    end
  end
end
