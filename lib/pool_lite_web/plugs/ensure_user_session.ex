defmodule PoolLiteWeb.Plugs.EnsureUserSession do
  @moduledoc """
  A plug that ensures every user has a unique session identifier.

  This plug automatically assigns a persistent user identifier to each
  visitor, which is used for vote tracking and preventing duplicate votes.

  The identifier is stored in the Phoenix session and will persist across
  page reloads and browser sessions (until cookies are cleared).
  """

  import Plug.Conn
  alias PoolLiteWeb.UserSession

  @doc """
  Initialize the plug with options.
  """
  @spec init(map()) :: map()
  def init(opts), do: opts

  @doc """
  Ensure the connection has a valid user identifier.

  If no identifier exists in the session, or if the existing one is invalid,
  a new identifier is generated and stored.
  """
  @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_session(conn, "user_identifier") do
      nil ->
        # No identifier exists, create a new one
        create_and_store_user_id(conn)

      identifier when is_binary(identifier) ->
        if UserSession.valid_user_id?(identifier) do
          # Valid identifier exists, keep using it
          conn
        else
          # Invalid identifier, replace it
          create_and_store_user_id(conn)
        end

      _ ->
        # Invalid type, replace it
        create_and_store_user_id(conn)
    end
  end

  defp create_and_store_user_id(conn) do
    user_id = UserSession.generate_user_id()
    put_session(conn, "user_identifier", user_id)
  end
end
