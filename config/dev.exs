import Config

# Development configuration
config :urza, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Isolated,
  peer: Oban.Peers.Isolated,
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
