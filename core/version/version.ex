# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Version do
  alias Antikythera.VersionStr

  defun current_version(app_name :: v[atom]) :: nil | VersionStr.t() do
    case Application.started_applications() |> List.keyfind(app_name, 0) do
      {_, _, v} -> List.to_string(v)
      nil -> nil
    end
  end

  defun read_from_app_file(lib_dir :: Path.t(), app_name :: v[atom | String.t()]) ::
          VersionStr.t() do
    app_file_path = Path.join([lib_dir, "ebin", "#{app_name}.app"])
    {:ok, [{:application, _, kw}]} = :file.consult(app_file_path)
    List.to_string(kw[:vsn])
  end
end
