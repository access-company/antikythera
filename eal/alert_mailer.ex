# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.AlertMailer do
  defmodule Mail do
    use Croma.Struct,
      fields: [
        from: Croma.String,
        to: Croma.TypeGen.list_of(Croma.String),
        subject: Croma.String,
        body: Croma.String
      ]
  end

  defmodule Behaviour do
    @moduledoc """
    Interface to email delivery backend for core/gear alerts.

    See `AntikytheraEal` for common information about pluggable interfaces defined in antikythera.
    """

    @doc """
    Sends an alert email.

    CC/BCC and HTML mail is omitted for simplicity.

    This callback is called in `AntikytheraCore.Alert.Handler.Email`, that is,
    when an alert email about error(s) in either antikythera core or gear is sent.
    """
    @callback deliver(mail :: Mail.t()) :: :ok | {:error, term}
  end

  defmodule MemoryInbox do
    @behaviour Behaviour

    @max_size_of_mail_list 100

    @impl true
    defun deliver(%Mail{} = mail) :: :ok do
      ensure_memory_inbox_started()
      |> Agent.update(fn mail_list ->
        [mail | mail_list] |> Enum.take(@max_size_of_mail_list)
      end)
    end

    defp ensure_memory_inbox_started() do
      case Agent.start_link(fn -> [] end, name: __MODULE__) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end

    #
    # API for test
    #
    def get() do
      ensure_memory_inbox_started()
      |> Agent.get(& &1)
    end

    def clean() do
      ensure_memory_inbox_started()
      |> Agent.update(fn _ -> [] end)
    end
  end

  use AntikytheraEal.ImplChooser
end
