defmodule Roger.Partition.Global.StatePersister.Filesystem do
  @moduledoc """

  Module implementing filesystem storage for `Roger.Partition.Global` state persistence.

  The path in which the state files are saved can be configured like this:

      config :roger, Roger.Partition.Global.StatePersister.Filesystem,
        path: "/path/to/files"

  Note that in a distributed setup, it does not make sense to use this
  persister unless you are sharing the filesystem between the multiple
  machines.

  """

  alias Roger.Partition.Global.StatePersister

  @behaviour StatePersister

  @storage_dir Application.get_env(:roger, __MODULE__, [])[:path] || "/tmp"

  def init(_id) do
    :ok
  end

  def load(id) do
    File.read(filename(id))
  end

  def store(id, data) do
    File.write(filename(id), data)
  end

  defp filename(id) do
    :filename.join(@storage_dir, "#{id}.state")
  end
end
