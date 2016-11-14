# Configuration


## AMQP connection

Roger depends on RabbitMQ as its backing store. The minimum
configuration is below:

    config :roger, Roger.AMQPClient,
      host: "localhost",
      port: 5672

These options are directly forwarded
to [the AMQP connection](https://hexdocs.pm/amqp/0.1.0/).  The most
common options are:

 * `:username` - The name of a user registered with the broker (defaults to "guest");
 * `:password` - The password of user (defaults to "guest");
 * `:virtual_host` - The name of a virtual host in the broker (defaults to "/");
 * `:host` - The hostname of the broker (defaults to "localhost");
 * `:port` - The port the broker is listening on (defaults to `5672`);
 * `:channel_max` - The channel_max handshake parameter (defaults to `0`);
 * `:frame_max` - The frame_max handshake parameter (defaults to `0`);
 * `:heartbeat` - The hearbeat interval in seconds (defaults to `0` - turned off);
 * `:connection_timeout` - The connection timeout in milliseconds (defaults to `infinity`);
 * `:ssl_options` - Enable SSL by setting the location to cert files (defaults to `none`);
 * `:client_properties` - A list of extra client properties to be sent to the server, defaults to `[]`;


## Worker callbacks

Roger can be configured with a callback module which invoke functions
on various places in a job's life cycle.

    config :roger, Roger.Partition.Worker,
      callbacks: MyWorkerModule

In this scenario, `MyWorkerModule` needs to *use* `Roger.Worker.Callback`:

    defmodule MyWorkerModule do
      use Roger.Partition.Worker.Callback

      def after_run(_app_id, job, result, _state) do
        IO.puts("Job #{job.id} succeeded with: #{inspect result}")
      end
    end

In this worker module, you can implement the functions `before_run/2`,
`after_run/4`, `on_error/4`, `on_cancel/2` and `on_buried/4` to
respond to job events.

See `Roger.Partition.Worker.Callback` for the full documentation on
these functions.



State persistence callbacks
---------------------------

Each Roger partition has one global process running in the cluster,
which holds some information necessary to implement certain features
(see `Roger.Partition.Global` for details).

It provides hooks to persist the information between partition /
node restarts. By default, the global state is loaded from and written
to the filesystem, but it is possible to override the persister, like
this:

    config :roger, Roger.Partition.Global,
      persister: Your.PersisterModule

The persister module must implement the
`Roger.Partition.Global.StatePersister` behaviour, which provides
simple load and save functions.
