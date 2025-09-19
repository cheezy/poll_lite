defmodule PoolLiteWeb.PageController do
  use PoolLiteWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "PollLite - Real-time Polling Platform")
    |> render(:home)
  end
end
