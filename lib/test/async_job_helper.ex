# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Test.AsyncJobHelper do
  @moduledoc """
  Helpers for tests that target async jobs.
  """

  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias AntikytheraCore.ExecutorPool.RegisteredName, as: RegName

  @doc """
  Resets the token bucket that rate-limits accesses to the specified async job queue.

  This function is useful when you hit the rate limit in your tests.
  You can accelerate your test execution by resetting the token bucket.
  See `Antikythera.AsyncJob` for more details about rate limiting.
  """
  defun reset_rate_limit_status(epool_id :: v[EPoolId.t()]) :: :ok do
    # This function inevitably depends on implementation details of `:foretoken` package.
    :ets.delete(:foretoken_buckets, RegName.async_job_queue(epool_id))
    :ok
  end
end
