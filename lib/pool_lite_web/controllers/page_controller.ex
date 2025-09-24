defmodule PoolLiteWeb.PageController do
  use PoolLiteWeb, :controller

  @spec home(Conn.t(), map()) :: Conn.t()
  def home(conn, _params) do
    conn
    |> assign(:page_title, "PollLite - Real-time Polling Platform")
    |> render(:home)
  end
end
