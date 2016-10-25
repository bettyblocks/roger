defmodule Roger.AMQPClientTest do
  use ExUnit.Case
  doctest Roger.AMQPClient

  alias AMQP.Channel

  test "AMQP client has been started" do
    assert is_pid(Process.whereis(Roger.AMQPClient))
  end

  test "open channel" do
    assert {:ok, channel} = Roger.AMQPClient.open_channel

    assert %Channel{} = channel
    assert is_pid(channel.pid)

    on_exit fn -> Channel.close(channel) end
  end

  test "publish" do
    :ok = Roger.AMQPClient.publish("", "test-queue", "test-payload", [])
  end

end
