defmodule CrazyIvan.Repo do
  use Ecto.Repo,
    otp_app: :crazy_ivan,
    adapter: Ecto.Adapters.Postgres
end
