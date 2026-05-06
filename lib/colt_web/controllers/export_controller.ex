defmodule ColtWeb.ExportController do
  use ColtWeb, :controller

  alias Colt.Resources.Campaign
  alias Colt.Services.Export.Csv

  def csv(conn, %{"id" => id}) do
    actor = conn.assigns[:current_user]

    with {:ok, campaign} <- Campaign.get(id, actor: actor),
         {:ok, %{csv: body, filename: filename}} <- Csv.run(campaign) do
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, body)
    else
      _ ->
        conn
        |> put_flash(:error, "Could not export this campaign.")
        |> redirect(to: ~p"/")
    end
  end
end
