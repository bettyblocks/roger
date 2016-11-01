defmodule RogerTest do
  use ExUnit.Case
  doctest Roger


  test "predefined applications get started automatically" do

    :ok = Application.stop :roger

    Application.put_env(:roger, :applications, example: [default: 10, other: 2])

    :ok = Application.start :roger
    :timer.sleep 200

    assert [app] = Roger.Application.running_applications
    assert "example" == app.id
    assert 2 == Enum.count(app.queues)

  end

end
