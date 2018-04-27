# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule SolomonLib.GearApplication.MetricsUploader do
  @moduledoc """
  Helper module to define interface module to submit custom metrics data.
  """

  defmacro __using__(_) do
    quote do
      defmodule MetricsUploader do
        defun submit(data_list :: v[SolomonLib.Metrics.DataList.t], context :: v[nil | SolomonLib.Context.t] \\ nil) :: :ok do
          AntikytheraCore.MetricsUploader.submit_custom_metrics(__MODULE__, data_list, context)
        end
      end
    end
  end
end
