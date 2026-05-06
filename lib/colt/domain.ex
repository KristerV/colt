defmodule Colt.Domain do
  use Ash.Domain,
    otp_app: :colt

  resources do
    resource Colt.Resources.Company
    resource Colt.Resources.AnnualReport
    resource Colt.Resources.Campaign
    resource Colt.Resources.CampaignCompany
    resource Colt.Resources.ApiCall
    resource Colt.Resources.Page
    resource Colt.Resources.Person
    resource Colt.Resources.Feedback
  end
end
