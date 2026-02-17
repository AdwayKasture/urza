import Config

# Test database configuration
config :urza, Urza.Repo,
  hostname: "localhost",
  username: "postgres",
  password: "password",
  database: "urza_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Test configuration
config :urza, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Isolated,
  peer: Oban.Peers.Isolated,
  repo: Urza.Repo,
  prefix: nil,
  queues: [
    default: 10,
    web: 10
  ],
  testing: :manual

# Configure LLM adapter mock for tests
config :urza, :llm_adapter, Urza.AI.LLMAdapterMock

# Configure communication adapter to use callback for tests
config :urza, :notification_adapter, Urza.Notification.Process

# Configure persistence adapter to use for tests
config :urza, :persistence_adapter, Urza.Persistence.ETS
