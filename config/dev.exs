import Config

# Development configuration - starts Oban for standalone dev/testing
config :urza, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Isolated,
  peer: Oban.Peers.Isolated,
  repo: Urza.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [
    default: 10,
    web: 10
  ]

# Database configuration
config :urza, Urza.Repo,
  hostname: "localhost",
  username: "postgres",
  password: "password",
  database: "urza_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :urza, :persistence_adapter, Urza.Persistence.ETS

config :urza, :notification_adapter, Urza.Notification.IO
