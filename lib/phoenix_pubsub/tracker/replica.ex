defmodule Phoenix.Tracker.Replica do
  @moduledoc false
  alias Phoenix.Tracker.Replica

  @type name :: String.t

  @type t :: %Replica{
    name: name,
    vsn: term,
    last_heartbeat_at: pos_integer,
    status: :up | :down | :permdown
  }

  defstruct name: nil,
            vsn: nil,
            last_heartbeat_at: nil,
            status: :up


  @type op_result :: {%{name => Replica.t}, previous_node :: Replica.t | nil, updated_node :: Replica.t}

  @doc """
  Returns a new Replica with a unique vsn.
  """
  @spec new(name) :: Replica.t
  def new(name) do
    %Replica{name: name, vsn: {now_ms(), System.unique_integer()}}
  end

  @spec ref(Replica.t) :: Phoenix.Tracker.State.noderef
  def ref(%Replica{name: name, vsn: vsn}), do: {name, vsn}

  @spec put_heartbeat(%{name => Replica.t}, Phoenix.Tracker.State.noderef) :: op_result
  def put_heartbeat(replicas, {name, vsn}) do
    case Map.fetch(replicas, name) do
      :error ->
        new_replica = touch_last_heartbeat(%Replica{name: name, vsn: vsn, status: :up})
        {Map.put(replicas, name, new_replica), nil, new_replica}

      {:ok, %Replica{} = prev_replica} ->
        updated_replica = touch_last_heartbeat(%Replica{prev_replica | vsn: vsn, status: :up})
        {Map.put(replicas, name, updated_replica), prev_replica, updated_replica}
    end
  end

  @spec detect_down(%{name => Replica.t}, Replica.t, pos_integer, pos_integer) :: op_result
  def detect_down(replicas, replica, temp_interval, perm_interval, now \\ now_ms()) do
    downtime = now - replica.last_heartbeat_at
    cond do
      downtime > perm_interval -> {Map.delete(replicas, replica.name), replica, permdown(replica)}
      downtime > temp_interval ->
        updated_replica = down(replica)
        {Map.put(replicas, replica.name, updated_replica), replica, updated_replica}
      true -> {replicas, replica, replica}
    end
  end

  defp permdown(replica), do: %Replica{replica | status: :permdown}

  defp down(replica), do: %Replica{replica | status: :down}

  defp touch_last_heartbeat(replica) do
    %Replica{replica | last_heartbeat_at: now_ms()}
  end

  defp now_ms, do: :os.timestamp() |> time_to_ms()
  defp time_to_ms({mega, sec, micro}) do
    trunc(((mega * 1000000 + sec) * 1000) + (micro / 1000))
  end
end