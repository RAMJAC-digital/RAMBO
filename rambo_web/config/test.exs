import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rambo_web, RamboWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KchPEwZ9yzEkofDWvspqjkk+np71zGQHtZw3E1RQBIfz0qt6QJpCaw1keMrwnNi1",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
