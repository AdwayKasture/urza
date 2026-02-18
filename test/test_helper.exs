Mox.defmock(Urza.AI.LLMAdapterMock, for: Urza.AI.LLMAdapter)
Application.put_env(:urza, :llm_adapter, Urza.AI.LLMAdapterMock)

# Register tools for testing before starting the application
Urza.Toolset.register_tools([
  Urza.Workers.Calculator,
  Urza.Workers.Web,
  Urza.Workers.Echo
])

# Start the test application
Application.ensure_all_started(:urza)

# Start Oban for testing (using Urza's Oban config)
oban_config = Application.fetch_env!(:urza, Oban)
Oban.start_link(oban_config)

# Start the repo explicitly for testing (not started by the app)
Urza.Repo.start_link()

# Set up Ecto Sandbox for tests - use shared mode for all tests
Ecto.Adapters.SQL.Sandbox.mode(Urza.Repo, :auto)

ExUnit.start()
