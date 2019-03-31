# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.TokenBucket do
  @moduledoc """
  A thin wrapper around [`Foretoken`](https://github.com/skirino/foretoken) to avoid collisions between bucket names by prefixing executor pool IDs.

  For details, refer to [Foretoken's documentation](https://hexdocs.pm/foretoken/api-reference.html).
  """

  @doc """
  Takes the specified tokens from the bucket.

  Internally the actual bucket name is prefixed with the given `epool_id`.
  Note that return value on error is slightly different from that of `Foretoken.take/5` (for backward compatibility).
  """
  defun take(epool_id               :: v[Antikythera.ExecutorPool.Id.t],
             bucket                 :: any,
             milliseconds_per_token :: g[pos_integer],
             max_tokens             :: g[pos_integer],
             tokens_to_take         :: g[pos_integer] \\ 1) :: :ok | {:error, pos_integer} do
    bucket_with_epool_id = {epool_id, bucket}
    case Foretoken.take(bucket_with_epool_id, milliseconds_per_token, max_tokens, tokens_to_take) do
      :ok                                   -> :ok
      {:error, {:not_enough_token, millis}} -> {:error, millis}
    end
  end
end
