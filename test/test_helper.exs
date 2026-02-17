Mox.defmock(Urza.AI.LLMAdapterMock, for: Urza.AI.LLMAdapter)
Application.put_env(:urza, :llm_adapter, Urza.AI.LLMAdapterMock)

# Start the test application
Application.ensure_all_started(:urza)

# Set up Ecto Sandbox for tests - use shared mode for all tests
Ecto.Adapters.SQL.Sandbox.mode(Urza.Repo, :auto)

ExUnit.start()
