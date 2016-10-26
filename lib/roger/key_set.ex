defmodule Roger.KeySet do
  @moduledoc """

  An opaque interface to storing keys and testing set member ship of
  keys. Like a bloom filter, but 100% probabilistic.

  iex> {:ok, pid} = Roger.KeySet.start_link
  iex> Roger.KeySet.add(pid, "bla")
  :ok
  iex> Roger.KeySet.contains?(pid, "bla")
  true
  iex> Roger.KeySet.contains?(pid, "beh")
  false

  Keys can also be removed:

  iex> {:ok, pid} = Roger.KeySet.start_link
  iex> Roger.KeySet.add(pid, "bla")
  iex> Roger.KeySet.remove(pid, "bla")
  :ok
  iex> Roger.KeySet.contains?(pid, "bla")
  false

  The state of the keyset can be retrieved in binary format. This
  state is to be treated as an opaque datastructure. We can then load
  the state into a new keyset process.

  The state can also be given as an argument when the keyset process
  is started.

  iex> {:ok, pid} = Roger.KeySet.start_link
  iex> Roger.KeySet.add(pid, "existing")
  iex> {:ok, state} = Roger.KeySet.get_state(pid)
  iex> {:ok, pid2} = Roger.KeySet.start_link(state: state)
  iex> Roger.KeySet.contains?(pid2, "existing")
  true

  Many keys can also be added at once:

  iex> {:ok, pid} = Roger.KeySet.start_link
  iex> Roger.KeySet.add_many(pid, ~w(a b c))
  :ok
  iex> Roger.KeySet.contains?(pid, "a")
  true
  iex> Roger.KeySet.contains?(pid, "b")
  true
  iex> Roger.KeySet.contains?(pid, "c")
  true

  Two keysets can also be used in set operations. These will always be
  applied to the first keyset; the second is left untouched:

  iex> {:ok, a} = Roger.KeySet.start_link
  iex> Roger.KeySet.add_many(a, ~w(a1 a2 a3))
  iex> {:ok, b} = Roger.KeySet.start_link
  iex> Roger.KeySet.add_many(b, ~w(b1 b2))
  iex> Roger.KeySet.union(a, b)
  :ok
  iex> Roger.KeySet.contains?(a, "b1")
  true
  iex> Roger.KeySet.contains?(b, "a1")
  false
  iex> Roger.KeySet.difference(a, b)
  :ok
  iex> Roger.KeySet.contains?(a, "b1")
  false

  """

  use GenServer


  def start_link(opts \\ []) do
    GenServer.start(__MODULE__, [opts])
  end

  def add(pid, key) do
    GenServer.call(pid, {:add, key})
  end

  def add_many(pid, keys) when is_list(keys) do
    GenServer.call(pid, {:add_many, keys})
  end

  def remove(pid, key) do
    GenServer.call(pid, {:remove, key})
  end

  def contains?(pid, key) do
    GenServer.call(pid, {:contains, key})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def put_state(pid, state) do
    GenServer.call(pid, {:put_state, state})
  end

  def union(pid, pid2) do
    GenServer.call(pid, {:set_operation, :union, pid2})
  end

  def difference(pid, pid2) do
    GenServer.call(pid, {:set_operation, :difference, pid2})
  end


  # server side

  def init([opts]) do
    {:ok, load_state(opts[:state])}
  end

  def handle_call({:add, key}, _from, state) do
    {:reply, :ok, MapSet.put(state, key)}
  end

  def handle_call({:add_many, keys}, _from, state) do
    state = Enum.reduce(keys, state, &(MapSet.put(&2, &1)))
    {:reply, :ok, state}
  end

  def handle_call({:contains, key}, _from, state) do
    {:reply, MapSet.member?(state, key), state}
  end

  def handle_call({:remove, key}, _from, state) do
    {:reply, :ok, MapSet.delete(state, key)}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, save_state(state)}, state}
  end

  def handle_call({:set_operation, operation, pid2}, _from, state) do
    {:reply, :ok, set_operation(pid2, operation, state)}
  end

  defp load_state(state) when is_binary(state) do
    state
    |> :erlang.binary_to_term
  end
  defp load_state(nil), do: MapSet.new()

  defp save_state(state) do
    :erlang.term_to_binary(state)
  end

  defp set_operation(source, operation, state) do
    {:ok, state2} = get_state(source)
    Kernel.apply(MapSet, operation, [state, load_state(state2)])
  end

end
