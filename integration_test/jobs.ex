defmodule Roger.Integration.Jobs do

  defmodule TestJob do
    use Roger.Job
    require Logger

    def perform(_) do
      #:timer.sleep 10
      :ok
    end
  end

end
