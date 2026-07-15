defmodule Colt.Services.Export.CsvTest do
  @moduledoc """
  Pins the CSV export column contract. The phone number is extracted and
  markdown-validated during contact extraction (`Person.phone`), so it must
  ride along in the export — a missing column silently drops it.
  """
  use Colt.DataCase, async: false

  alias Colt.Accounts.User
  alias Colt.Resources.{Campaign, CampaignCompany, Company, Person}
  alias Colt.Services.Export.Csv

  setup do
    user =
      User
      |> Ash.Changeset.for_create(:seed, %{email: "owner@example.com"}, authorize?: false)
      |> Ash.create!(authorize?: false)

    {:ok, campaign} = Campaign.create_draft("Export", actor: user)

    %{user: user, campaign: campaign}
  end

  test "exports the picked person's phone number", %{user: user, campaign: campaign} do
    seed_enriched(campaign, user, 1,
      name: "Anni Tamm",
      title: "CEO",
      email: "anni@example.ee",
      phone: "+372 5123 4567"
    )

    assert {:ok, %{csv: csv}} = Csv.run(campaign)

    [header, row | _] = String.split(csv, "\r\n", trim: true)

    assert "phone" in String.split(header, ",")
    assert csv =~ "+372 5123 4567"

    # Phone lands in the right column, not smeared into a neighbouring cell.
    cols = Enum.zip(String.split(header, ","), String.split(row, ","))
    assert {"phone", "+372 5123 4567"} in cols
  end

  test "a person without a phone yields an empty phone cell, not a crash", %{
    user: user,
    campaign: campaign
  } do
    seed_enriched(campaign, user, 2,
      name: "Mari Kask",
      title: "CTO",
      email: "mari@example.ee",
      phone: nil
    )

    assert {:ok, %{csv: csv}} = Csv.run(campaign)

    [header, row | _] = String.split(csv, "\r\n", trim: true)
    cols = Enum.zip(String.split(header, ","), String.split(row, ","))
    assert {"phone", ""} in cols
  end

  # Builds an enriched, opted-in CampaignCompany with a picked person — the exact
  # shape `Csv.run/1` loads via `CampaignCompany.list_for_export`.
  defp seed_enriched(campaign, user, idx, person_attrs) do
    {:ok, company} =
      Company.upsert_basic(
        %{
          registry_code: "1000#{String.pad_leading(to_string(idx), 4, "0")}",
          market: :ee,
          name: "Company #{idx} OÜ",
          region: "Tallinn",
          status: :registered
        },
        actor: user,
        authorize?: false
      )

    {:ok, person} =
      Person.create_validated(
        Map.merge(%{company_id: company.id, validated_in_markdown: true}, Map.new(person_attrs)),
        actor: user,
        authorize?: false
      )

    {:ok, cc} =
      CampaignCompany
      |> Ash.Changeset.for_create(
        :create,
        %{campaign_id: campaign.id, company_id: company.id},
        actor: user,
        authorize?: false
      )
      |> Ash.create(authorize?: false)

    {:ok, cc} =
      CampaignCompany.set_picked_person(cc, person.id, person.email,
        actor: user,
        authorize?: false
      )

    {:ok, _cc} = CampaignCompany.mark_enriched(cc, actor: user, authorize?: false)

    person
  end
end
