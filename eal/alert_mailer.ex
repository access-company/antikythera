# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraEal.AlertMailer do
  @moduledoc """
  Interface to mailer backend for Core/Gear alerts.
  """

  defmodule Mail do
    use Croma.Struct, recursive_new?: true, fields: [
      from:    Croma.String,
      to:      Croma.TypeGen.list_of(Croma.String),
      subject: Croma.String,
      body:    Croma.String,
    ]
  end

  defmodule Behaviour do
    @doc """
    Minimal `mail` delivering API. CC/BCC or HTML mail is omitted for simplicity.
    """
    @callback deliver(mail :: Mail.t) :: :ok | {:error, term}
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
        {:ok   , pid                    } -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end

    # API for test

    def get() do
      ensure_memory_inbox_started()
      |> Agent.get(&(&1))
    end

    def clean() do
      ensure_memory_inbox_started()
      |> Agent.update(fn _ -> [] end)
    end
  end

  use AntikytheraEal.ImplChooser
end
