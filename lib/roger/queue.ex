defmodule Roger.Queue do

  defstruct queue: nil, type: nil, max_workers: nil, consumer_tag: nil, channel: nil, confirmed: false

  def define(type, max_workers) do
    %__MODULE__{type: type, max_workers: max_workers}
  end

  def make_name(%Roger.Application{} = application, type) do
    "#{application.id}-#{type}"
  end

end
