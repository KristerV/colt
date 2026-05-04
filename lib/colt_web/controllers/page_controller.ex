defmodule ColtWeb.PageController do
  use ColtWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
