defmodule RamboWebWeb.PageControllerTest do
  use RamboWebWeb.ConnCase

  test "GET / serves emulator UI", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Load ROM"
    assert html =~ "RAMBO Web Emulator"
  end
end
