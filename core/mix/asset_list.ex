# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Mix.AssetList do
  alias SolomonLib.{GearName, Time}

  @typep keyset :: MapSet.t(String.t)

  defun write!(gear_name :: v[GearName.t], keys :: v[[String.t]]) :: :ok do
    content = Enum.sort(keys) |> Enum.join("\n")
    version = Mix.Project.config()[:version]
    path    = Path.join(dir(), "#{gear_name}-#{version}")
    File.write!(path, content)
    IO.puts("created an asset list file: #{path}")
  end

  defun load_all(gear_name :: v[GearName.t], threshold_time :: v[Time.t]) :: keyset do
    Path.wildcard(Path.join(dir(), "#{gear_name}-*"))
    |> filter_relevant_paths_and_discard_others(threshold_time)
    |> Enum.reduce(MapSet.new(), &load/2)
  end

  defp filter_relevant_paths_and_discard_others(paths, threshold_time) do
    {paths_before, paths_after} = split_paths(paths, threshold_time)
    case Enum.reverse(paths_before) do
      []                               -> paths_after
      [path_latest | paths_irrelevant] ->
        Enum.each(paths_irrelevant, &File.rm!/1)
        [path_latest | paths_after]
    end
  end

  defp split_paths(paths, threshold_time) do
    {pairs_before, pairs_after} =
      Enum.map(paths, fn path -> {mtime(path), path} end)
      |> Enum.sort()
      |> Enum.split_while(fn {time, _} -> time < threshold_time end)
    {Enum.map(pairs_before, &elem(&1, 1)), Enum.map(pairs_after, &elem(&1, 1))}
  end

  defp mtime(path) do
    {date, time} = File.stat!(path).mtime
    {Time, date, time, 0}
  end

  defunp load(path :: Path.t, set :: keyset) :: keyset do
    IO.puts("loading an asset list file: #{path}")
    File.read!(path)
    |> String.split("\n", trim: true)
    |> Enum.into(set)
  end

  defunp dir() :: Path.t do
    Path.join(System.user_home!(), "antikythera_gear_asset_list")
  end
end
