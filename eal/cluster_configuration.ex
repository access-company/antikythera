# Copyright(c) 2015-2018 ACCESS CO., LTD. All rights reserved.

use Croma
alias Croma.Result, as: R

defmodule AntikytheraEal.ClusterConfiguration do
  defmodule Behaviour do
    @callback running_hosts()     :: R.t(%{String.t => boolean})
    @callback zone_of_this_host() :: String.t
  end

  defmodule StandAlone do
    @behaviour Behaviour

    @impl true
    defun running_hosts() :: R.t(%{String.t => boolean}) do
      [_, host] = Node.self() |> Atom.to_string() |> String.split("@")
      {:ok, %{host => true}}
    end

    @impl true
    defun zone_of_this_host() :: String.t, do: "zone"
  end

  use AntikytheraEal.ImplChooser
end
