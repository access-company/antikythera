# Copyright(c) 2015-2024 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule AntikytheraCore.Metrics.AggregateStrategy do
  @moduledoc """
  Defines (1) a behaviour to compute metrics results from raw metrics data and (2) some implementations of the behaviour.
  "Raw metrics data" is values reported from other components (e.g. response time values).
  "Metrics results" are values that summarize characteristics of "raw metrics data" (e.g. average response time).

  Antikythera gear implementations must specify `name` of one of the strategies when submitting raw metric data.
  For available `name` see the type definition in `AntikytheraCore.Metrics.AggregateStrategy.Name`.
  For detailed information about each strategy refer to each module's documentation.
  """

  @type data_t :: any
  @type results_t :: Keyword.t(number)

  defmodule Behaviour do
    alias AntikytheraCore.Metrics.AggregateStrategy, as: Strategy
    @callback init(number) :: Strategy.data_t()
    @callback merge(Strategy.data_t(), number) :: Strategy.data_t()
    @callback results(Strategy.data_t()) :: Strategy.results_t()
  end

  # We should not use macro to generate the following list of modules,
  # since it can lead to compilation error when adding/removing file in `aggregate_strategy/`.
  all_behaviour_impl_modules = [
    __MODULE__.Average,
    __MODULE__.Gauge,
    __MODULE__.RequestCount,
    __MODULE__.Sum,
    __MODULE__.TimeDistribution
  ]

  all_behaviour_impl_names =
    Enum.map(all_behaviour_impl_modules, fn mod ->
      # during compilation, no problem
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      Module.split(mod) |> List.last() |> Macro.underscore() |> String.to_atom()
    end)

  use Croma.SubtypeOfAtom, values: all_behaviour_impl_modules

  defmodule Name do
    use Croma.SubtypeOfAtom, values: all_behaviour_impl_names
  end

  for {name, mod} <- Enum.zip(all_behaviour_impl_names, all_behaviour_impl_modules) do
    def name_to_module(unquote(name)), do: unquote(mod)
  end
end
