defmodule Roger.Startup do
  use GenServer

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, nil, 0}
  end

  def handle_info(:timeout, state) do
    apps = Application.get_env(:roger, :applications, [])
    Roger.Application.start_all(apps)
    {:stop, :normal, state}
  end
end
