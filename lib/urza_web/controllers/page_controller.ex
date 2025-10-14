defmodule UrzaWeb.PageController do
  use UrzaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
