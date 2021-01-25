# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version.History do
  @moduledoc """
  Functions to get information from "history" files.

  Antikythera uses history files to detect new deployable versions of antikythera instance and gears.
  Each of antikythera instance and gears has its own history file.
  The files reside in `AntikytheraCore.Path.history_dir/0`.

  When deploying a new version, after successfully generated a compiled artifact (tarball),
  antikythera's deploy script instructs the ErlangVM nodes by appending a line to the history file of the target OTP application.
  Each line takes either of the following forms:

  |                                          | format of line                          | installable    | upgradable    |
  | deploy with hot code upgrade             | `<version>`                             | true           | true          |
  | deploy with hot code upgrade (canary)    | `<version> canary=<hosts>`              | false          | host in hosts |
  | deploy without hot code upgrade          | `<version> noupgrade`                   | true           | false         |
  | deploy without hot code upgrade (canary) | `<version> noupgrade_canary=<deadline>` | now < deadline | false         |

  - "installable" means that the version can be installed into a node that doesn't have the OTP application.
      - See also `script/in_cloud/erl/boot_impl.sh`, which chooses an appropriate version of
        OTP release of the antikythera instance at startup of a newly created host.
  - "upgradable" means that the version can be applied by hot code upgrade to a node that has a previous version of the OTP application.

  Versions in a history file are expected to monotonically increase.
  """

  alias Antikythera.{Time, GearName, GearNameStr, VersionStr, SecondsSinceEpoch}
  alias AntikytheraCore.Path, as: CorePath
  alias AntikytheraCore.Cluster

  defmodule Entry do
    alias Croma.TypeGen, as: TG

    use Croma.Struct,
      recursive_new?: true,
      fields: [
        version: VersionStr,
        canary_target_hosts: TG.nilable(TG.list_of(Croma.String)),
        noupgrade: Croma.Boolean,
        installable_until: TG.nilable(Time)
      ]

    defun from_line(s :: v[String.t()]) :: t do
      case String.split(s, " ", trim: true) do
        [version] ->
          %__MODULE__{
            version: version,
            noupgrade: false,
            canary_target_hosts: nil,
            installable_until: nil
          }

        [version, "canary=" <> hosts_str] ->
          hosts = String.split(hosts_str, ",", trim: true)

          %__MODULE__{
            version: version,
            noupgrade: false,
            canary_target_hosts: hosts,
            installable_until: nil
          }

        [version, "noupgrade"] ->
          %__MODULE__{
            version: version,
            noupgrade: true,
            canary_target_hosts: nil,
            installable_until: nil
          }

        [version, "noupgrade_canary=" <> timestamp] ->
          {:ok, t} = Time.from_iso_timestamp(timestamp)

          %__MODULE__{
            version: version,
            noupgrade: true,
            canary_target_hosts: nil,
            installable_until: t
          }
      end
    end

    defun installable?(%__MODULE__{canary_target_hosts: hosts, installable_until: until}) ::
            boolean do
      case {hosts, until} do
        {nil, nil} -> true
        {_, nil} -> false
        {nil, _} -> Time.now() < until
      end
    end

    defun upgradable?(%__MODULE__{noupgrade: noupgrade, canary_target_hosts: hosts}) :: boolean do
      if noupgrade do
        false
      else
        case hosts do
          nil -> true
          _ -> Cluster.node_to_host(Node.self()) in hosts
        end
      end
    end

    defun canary?(%__MODULE__{canary_target_hosts: hosts, installable_until: until}) :: boolean do
      case {hosts, until} do
        {nil, nil} -> false
        _ -> true
      end
    end
  end

  defun latest_installable_gear_version(gear_name :: v[GearName.t()]) :: nil | VersionStr.t() do
    find_latest_installable_version(File.read!(file_path(gear_name)))
  end

  defunpt find_latest_installable_version(content :: v[String.t()]) :: nil | VersionStr.t() do
    String.split(content, "\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      e = Entry.from_line(line)
      if Entry.installable?(e), do: e.version, else: nil
    end)
  end

  defun next_upgradable_version(
          app_name :: v[:antikythera | GearName.t()],
          current_version :: v[VersionStr.t()]
        ) :: nil | VersionStr.t() do
    find_next_upgradable_version(app_name, File.read!(file_path(app_name)), current_version)
  end

  defunpt find_next_upgradable_version(
            app_name :: v[:antikythera | GearName.t()],
            content :: v[String.t()],
            current_version :: v[VersionStr.t()]
          ) :: nil | VersionStr.t() do
    lines_without_previous_versions =
      String.split(content, "\n", trim: true)
      |> Enum.drop_while(fn line -> !String.starts_with?(line, current_version) end)

    case lines_without_previous_versions do
      [] ->
        raise "current version is not found in history file for #{app_name}"

      _ ->
        lines_with_new_versions =
          Enum.drop_while(lines_without_previous_versions, fn l ->
            String.starts_with?(l, current_version)
          end)

        find_next(lines_with_new_versions)
    end
  end

  defp find_next([]), do: nil

  defp find_next([l | ls]) do
    e = Entry.from_line(l)

    cond do
      Entry.upgradable?(e) -> e.version
      Entry.canary?(e) -> find_next(ls)
      :noupgrade_deploy -> nil
    end
  end

  defunp file_path(app_name :: v[:antikythera | GearName.t()]) :: Path.t() do
    Path.join(CorePath.history_dir(), Atom.to_string(app_name))
  end

  defun find_all_modified_history_files(since :: v[SecondsSinceEpoch.t()]) ::
          {boolean, [GearName.t()]} do
    antikythera_instance_name_str =
      Antikythera.Env.antikythera_instance_name() |> Atom.to_string()

    files =
      CorePath.list_modified_files(CorePath.history_dir(), since) |> Enum.map(&Path.basename/1)

    {antikythera_appearance, others} =
      Enum.split_with(files, &(&1 == antikythera_instance_name_str))

    gear_names =
      Enum.filter(others, &GearNameStr.valid?/1)
      # generate atom from trusted data source
      |> Enum.map(&String.to_atom/1)

    {antikythera_appearance != [], gear_names}
  end

  defun all_deployable_gear_names() :: [GearName.t()] do
    {_, gear_names} = find_all_modified_history_files(0)
    gear_names
  end
end
