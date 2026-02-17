import Config

# Ecto repositories
config :urza, ecto_repos: [Urza.Repo]

# Oban configuration
config :urza, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  peer: Oban.Peers.Postgres,
  repo: Urza.Repo,
  prefix: nil,
  queues: [
    default: 10,
    web: 10
  ]

# LLM Adapter configuration
config :urza, :llm_adapter, ReqLLM

# Import environment specific config
import_config "#{config_env()}.exs"
