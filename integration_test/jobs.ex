defmodule Roger.Integration.Jobs do

  defmodule TestJob do
    use Roger.Job
    require Logger

    def perform(_) do
      :timer.sleep 10
      #Logger.warn "Executing!"
      #File.write!("/tmp/job.txt", "#{DateTime.utc_now} - Executed on: #{node}\n", [:append])
      :nop
    end
  end

end
