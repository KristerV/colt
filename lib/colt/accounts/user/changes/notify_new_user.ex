defmodule Colt.Accounts.User.Changes.NotifyNewUser do
  @moduledoc """
  Sends a Discord notification when a brand-new user is created via magic-link
  upsert. Detects "new" by checking the email's existence before the action
  runs, since the action is also used for sign-in of existing users.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Colt.Accounts.User
  alias Colt.Services.Discord

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(fn cs ->
      email = Changeset.get_attribute(cs, :email)
      existing? = match?({:ok, _}, Ash.get(User, [email: email], authorize?: false))
      Changeset.put_context(cs, :__new_user_signup__, not existing?)
    end)
    |> Changeset.after_action(fn cs, result ->
      if cs.context[:__new_user_signup__] do
        Discord.Notify.run("New user registered: #{result.email}")
      end

      {:ok, result}
    end)
  end
end
