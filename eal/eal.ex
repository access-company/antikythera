# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule AntikytheraEal do
  @moduledoc """
  Environment abstraction layer: pluggable interfaces defined in antikythera.

  (This module exists solely for documentation purpose and thus contains only this `@moduledoc`.)

  Some of antikythera's features are pluggable so that one can use environment-specific implementations.
  For example, in order to maintain cluster membership, list of currently running ErlangVM nodes
  may be obtained from the IaaS platform API.

  Administrators of an antikythera instance must provide the set of concrete callback modules
  suitable for their environments.
  The callback modules to be used by antikythera must be specified as `:eal_impl_modules` key in mix configs.
  Note that `:eal_impl_modules` are resolved at compile time.
  This means:

  - compiling antikythera requires the callback modules for all behaviours, and
  - to change any of the callback modules you have to recompile antikythera.

  ## Module naming scheme for each interface

  All pluggable interfaces are defined as behaviour modules and named as
  `AntikytheraEal.SomeFeature.Behaviour` (e.g. `AntikytheraEal.ClusterConfiguration.Behaviour`).
  Each behaviour comes with a concrete callback module which is used for tests of antikythera
  (e.g. `AntikytheraEal.ClusterConfiguration.StandAlone`).
  The parent module (e.g. `AntikytheraEal.ClusterConfiguration`) works as a proxy module
  when invoking the callback functions of the module specified in mix config
  (see also `AntikytheraEal.ImplChooser`).
  """
end
