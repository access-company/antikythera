# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.TokenBucket do
  @moduledoc """
  A thin wrapper around [`Foretoken`](https://github.com/skirino/foretoken) to avoid collisions between bucket names by prefixing executor pool IDs.
  For details, refer to [Foretoken's documentation](https://hexdocs.pm/foretoken/api-reference.html).
  """

  @doc """
  Usage of this function is the same as `take/4` except that an executor pool ID is required as an argument.
  """
  defun take(epool_id               :: v[Antikythera.ExecutorPool.Id.t],
             bucket                 :: any,
             milliseconds_per_token :: g[pos_integer],
             max_tokens             :: g[pos_integer],
             tokens_to_take         :: g[pos_integer] \\ 1) :: :ok | {:error, pos_integer} do
    bucket_with_epool_id = {epool_id, bucket}
    Foretoken.take(bucket_with_epool_id, milliseconds_per_token, max_tokens, tokens_to_take)
  end
end
