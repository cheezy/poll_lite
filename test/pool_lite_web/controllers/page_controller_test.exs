defmodule PoolLiteWeb.PageControllerTest do
  use PoolLiteWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Create"
    assert html =~ "Live Polls"
  end
end
