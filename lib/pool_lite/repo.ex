defmodule PoolLite.Repo do
  use Ecto.Repo,
    otp_app: :pool_lite,
    adapter: Ecto.Adapters.Postgres
end
