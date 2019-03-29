defmodule FaktoryWorker.ConnectionManager.Server do
  @moduledoc false

  use GenServer

  alias FaktoryWorker.ConnectionManager

  @spec start_link(opts :: keyword()) :: {:ok, pid()} | :ignore | {:error, any()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec send_command(connection_manager :: atom() | pid(), command :: Protocol.protocol_command()) ::
          {:ok, any()} | {:error, any()}
  def send_command(connection_manager, command) do
    GenServer.call(connection_manager, {:send_command, command})
  end

  @impl true
  def init(opts) do
    {:ok, ConnectionManager.new(opts)}
  end

  @impl true
  def handle_call({:send_command, command}, _, state) do
    {result, state} = ConnectionManager.send_command(state, command)
    {:reply, result, state}
  end
end