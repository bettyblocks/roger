defmodule Roger.Queue do
  @moduledoc """
  Struct which holds information about a single queue.
  """

  @type t :: %__MODULE__{}

  defstruct type: nil, max_workers: nil, consumer_tag: nil, channel: nil, confirmed: false

  def define({type, max_workers}) do
    define(type, max_workers)
  end

  def define(type, max_workers) do
    %__MODULE__{type: type, max_workers: max_workers}
  end

  def make_name(application_id, type, postfix \\ "") do
    "#{application_id}-#{type}#{postfix}"
  end

end
