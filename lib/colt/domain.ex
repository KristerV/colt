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
    resource Colt.Resources.IcpLearning
    resource Colt.Resources.SuppressedDomain
    resource Colt.Resources.EmailAccount
    resource Colt.Resources.CampaignEmailAccount
    resource Colt.Resources.Sequence
    resource Colt.Resources.SequenceStep
    resource Colt.Resources.CampaignContact
    resource Colt.Resources.Thread
    resource Colt.Resources.OutboundEmail
    resource Colt.Resources.InboundEmail
    resource Colt.Resources.Note
    resource Colt.Resources.Pitch
    resource Colt.Resources.AppSetting
  end
end
