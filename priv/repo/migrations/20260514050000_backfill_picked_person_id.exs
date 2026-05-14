defmodule Colt.Repo.Migrations.BackfillPickedPersonId do
  use Ecto.Migration

  def up do
    # For each enriched CampaignCompany without a picked_person_id, copy the
    # legacy choice that lived on the global Person.matches_target_title flag.
    # The flag was last-write-wins across campaigns, so older campaigns inherit
    # the most recent run's pick — same behavior the UI showed pre-fix.
    execute("""
    UPDATE campaign_companies cc
       SET picked_person_id = p.id
      FROM persons p
     WHERE cc.picked_person_id IS NULL
       AND cc.status = 'enriched'
       AND p.company_id = cc.company_id
       AND p.validated_in_markdown = TRUE
       AND p.matches_target_title = TRUE
    """)
  end

  def down do
    execute("UPDATE campaign_companies SET picked_person_id = NULL")
  end
end
