defmodule Roger.Integration.Jobs do
  @moduledoc false

  defmodule TestJob do
    @moduledoc false

    use Roger.Job
    require Logger

    def perform(_) do
      #:timer.sleep 10
      :ok
    end
  end

end
