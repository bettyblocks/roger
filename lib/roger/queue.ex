defmodule Roger.Queue do
  @moduledoc false

  @type t :: %__MODULE__{}

  defstruct type: nil, max_workers: nil, consumer_tag: nil, channel: nil, confirmed: false

  def define({type, max_workers}) do
    define(type, max_workers)
  end

  def define(type, max_workers) do
    %__MODULE__{type: type, max_workers: max_workers}
  end

  def make_name(partition_id, type, postfix \\ "") do
    "#{partition_id}-#{type}#{postfix}"
  end

end
