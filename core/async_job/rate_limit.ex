# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.AsyncJob.RateLimit do
  @milliseconds_per_token 500
  @max_tokens             30
  @tokens_per_command     3
  @max_check_attempts     5

  # For documentation and test
  def milliseconds_per_token(), do: @milliseconds_per_token
  def max_tokens()            , do: @max_tokens
  def tokens_per_command()    , do: @tokens_per_command

  defun check_for_command(queue_name :: v[atom]) :: :ok | {:error, pos_integer} do
    case Foretoken.take(queue_name, @milliseconds_per_token, @max_tokens, @tokens_per_command) do
      :ok                                   -> :ok
      {:error, {:not_enough_token, millis}} -> {:error, millis}
    end
  end

  defun check_with_retry_for_query(queue_name :: v[atom], f :: (() -> a), attempts :: v[non_neg_integer] \\ 0) :: a when a: any do
    case Foretoken.take(queue_name, @milliseconds_per_token, @max_tokens) do
      :ok                                   -> f.()
      {:error, {:not_enough_token, millis}} ->
        if attempts >= @max_check_attempts do
          raise "rate limit violation hasn't been resolved by retries"
        else
          :timer.sleep(millis)
          check_with_retry_for_query(queue_name, f, attempts + 1)
      end
    end
  end
end
