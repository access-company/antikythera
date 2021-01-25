# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.GearApplication.MetricsUploader do
  @moduledoc """
  Helper module to define interface module to submit custom metrics data.
  """

  defmacro __using__(_) do
    quote do
      defmodule MetricsUploader do
        defun submit(
                data_list :: v[Antikythera.Metrics.DataList.t()],
                context :: v[nil | Antikythera.Context.t()] \\ nil
              ) :: :ok do
          AntikytheraCore.MetricsUploader.submit_custom_metrics(__MODULE__, data_list, context)
        end
      end
    end
  end
end
