import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pool_lite, PoolLite.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pool_lite_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  ownership_timeout: 60_000,
  timeout: 60_000,
  queue_target: 5000,
  queue_interval: 10_000,
  log: false,
  show_sensitive_data_on_connection_error: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pool_lite, PoolLiteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "cyDr89b3yCOoG59/BdABviBRLYDqE2MyNvDecH9MXFWlUxy7aPsJ27/PDLL09QSS",
  server: false

# In test we don't send emails
config :pool_lite, PoolLite.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure logger for tests - suppress error logs to avoid Postgrex warnings
config :logger, level: :critical

# Alternatively, if you want warnings but not errors:
# config :logger,
#   level: :warning,
#   compile_time_purge_matching: [[level_lower_than: :critical]]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
