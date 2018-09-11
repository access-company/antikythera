# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Foretoken do
  @moduledoc """
  A thin wrapper around [`Foretoken`](https://github.com/skirino/foretoken) to avoid collisions of bucket name between executor pool.
  For details, refer to [Foretoken's documentation](https://hexdocs.pm/foretoken/api-reference.html).
  """

  @doc """
  Usage of this function is same as `Foretoken.token/4` except that an executor pool argument is added.
  """
  defun take(epool_id               :: v[Antikythera.ExecutorPool.Id.t],
             bucket                 :: any,
             milliseconds_per_token :: g[pos_integer],
             max_tokens             :: g[pos_integer],
             tokens_to_take         :: g[pos_integer] \\ 1) :: :ok | {:error, pos_integer} do
    bucket_with_epool_id = {epool_id, bucket}
    Foretoken.Ets.take(bucket_with_epool_id, tokens_to_take, milliseconds_per_token, max_tokens)
  end
end
