# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.MetricsStorage do
  alias Antikythera.Time
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.Metrics.{Buffer, Results}
  alias AntikytheraCore.Cluster.NodeId
  alias __MODULE__, as: S

  @type metrics_per_unit :: {Buffer.metrics_unit, Results.per_unit_results_map}

  defmodule Behaviour do
    @moduledoc """
    Interface to storage for metrics data.

    See `AntikytheraEal` for common information about pluggable interfaces defined in antikythera.

    Metrics data generated during runtime is buffered for a while by `AntikytheraCore.MetricsUploader`
    processes and then transferred to metrics storage using `upload/3` callback.
    """

    @doc """
    Uploads the metrics data to the metrics storage.

    `otp_app_name` is either a gear name or `:antikythera`.
    `node_id` is the name of the current node and callback implementation may include `node_id`
    in the body of the upload.
    """
    @callback upload(otp_app_name :: atom, node_id :: NodeId.t, results :: Results.t) :: [S.metrics_per_unit]
  end

  defmodule Memory do
    alias Antikythera.NestedMap

    @behaviour Behaviour

    @impl true
    defun upload(otp_app_name :: v[atom], node_id :: NodeId.t, results :: Results.t) :: [] do
      if not Enum.empty?(results) do
        ensure_agent_started() |> Agent.update(fn state1 ->
          state2 =
            Enum.reduce(results, state1, fn({{minute, epool_id}, values_map1}, s) ->
              {Time, ymd, _hm0, 0} = minute
              values_map2 = add_fields(values_map1, otp_app_name, node_id, epool_id)
              NestedMap.force_update(s, [ymd, otp_app_name, epool_id], fn tree_or_nil ->
                store_data_in_tree(tree_or_nil || :gb_trees.empty(), minute, values_map2)
              end)
            end)
          index_latest = Map.keys(state2) |> Enum.max()
          Map.take(state2, [index_latest])
        end)
      end
      []
    end

    defp add_fields(map1, otp_app_name, node_id, epool_id) do
      map2 =
        map1
        |> Map.put("otp_app_name", Atom.to_string(otp_app_name))
        |> Map.put("node_id", node_id)
      if epool_id == :nopool do
        map2
      else
        Map.put(map2, "epool_id", EPoolId.to_string(epool_id))
      end
    end

    defp store_data_in_tree(tree, minute, values_map) do
      new_map =
        case :gb_trees.lookup(minute, tree) do
          :none                  -> values_map
          {:value, existing_map} -> Map.merge(existing_map, values_map)
        end
      :gb_trees.enter(minute, new_map, tree)
    end

    @doc """
    Retrieve metrics in memory for testing.
    """
    defun download(otp_app_name :: v[atom], epool_id :: v[:nopool | EPoolId.t], t1 :: v[Time.t], t2 :: v[Time.t]) :: [{Time.t, Results.per_unit_results_map}] do
      {Time, ymd, _hms, _millis} = t2
      ensure_agent_started() |> Agent.get(fn state ->
        case get_in(state, [ymd, otp_app_name, epool_id]) do
          nil  -> []
          tree -> documents_in_range(tree, t1, t2)
        end
      end)
    end

    defp documents_in_range(tree, t1, t2) do
      t_start = Time.truncate_to_minute(t1)
      t_end   = Time.truncate_to_minute(t2) |> Time.shift_minutes(1)
      iter    = :gb_trees.iterator_from(t_start, tree)
      take_upto(iter, t_end, [])
    end

    defp take_upto(iter1, t_end, acc) do
      case :gb_trees.next(iter1) do
        {t, m, iter2} when t <= t_end -> take_upto(iter2, t_end, [{t, m} | acc])
        _empty_or_out_of_range        -> Enum.reverse(acc)
      end
    end

    defunp ensure_agent_started() :: pid do
      case Agent.start(fn -> %{} end, [name: __MODULE__]) do
        {:ok, pid}                        -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end
  end

  #
  # wrapper of `upload/3` for MetricsUploader
  #
  defun save(otp_app_name :: v[atom], results :: Results.t) :: Results.t do
    upload(otp_app_name, NodeId.get(), results)
    |> Map.new()
  end

  use AntikytheraEal.ImplChooser
end
