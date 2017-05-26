defmodule Conn do
  @moduledoc """
  Documentation for RoguePortConn.
  """
  require Logger

  def start_supervisor() do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    {:ok, {
      %{strategy: :simple_one_for_one},
      [%{id: :conn,
         start: {ConnWorker, :start, []}
         }]}}
  end

  def start_conns(sup) do
    conns_count = 2
    for _ <- 1..conns_count do
      Supervisor.start_child(sup, [])
    end
  end

  def start(_, _) do
    {:ok, sup} = start_supervisor()
    start_conns(sup)
    {:ok, sup}
  end

  def stop(_) do
    :ok
  end

end


defmodule ConnWorker do
  use GenServer
  require Logger

  def init([]) do
    host = System.get_env("HOST")
    {:ok, conn} = AMQP.Connection.open([host: host, username: "admin", password: "uochie3AjiePheeZaich"])
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Basic.qos(chan, prefetch_count: 10)
    AMQP.Queue.declare(chan, "redeliver", [auto_delete: true])
    consumer_pid = spawn fn -> do_start_consumer(chan) end
    AMQP.Basic.consume(chan, "redeliver", consumer_pid)
    {:ok, conn}
  end

  def do_start_consumer(chan) do
    receive do
      {:basic_consume_ok, %{consumer_tag: consumer_tag}} ->
        do_consume(chan, consumer_tag)
    end
  end

  def do_consume(chan, consumer_tag) do
    receive do
      {:basic_deliver, _payload, %{delivery_tag: delivery_tag} = _meta} ->
        AMQP.Basic.reject(chan, delivery_tag, requeue: true)
        do_consume(chan, consumer_tag)
      {:basic_cancel, %{consumer_tag: ^consumer_tag, no_wait: _}} ->
        exit(:basic_cancel)
      {:basic_cancel_ok, %{consumer_tag: ^consumer_tag}} ->
        exit(:normal)
    end
  end

  def start() do
    GenServer.start_link(ConnWorker, [])
  end
end
