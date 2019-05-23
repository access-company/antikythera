# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Zip do
  alias Croma.Result, as: R

  defun zip(
    zip_path :: v[String.t],
    src_path :: v[String.t]
  ) :: R.t(Path.t) do
    {_, 0} = System.cmd("zip", [zip_path, src_path])
    {:ok, zip_path}
  end
end
