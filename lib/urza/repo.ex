defmodule Urza.Repo do
  use Ecto.Repo,
    otp_app: :urza,
    adapter: Ecto.Adapters.Postgres
end
