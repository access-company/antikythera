# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Registry do
  alias Antikythera.{GearName, TenantId, Context}
  alias Antikythera.ExecutorPool.Id, as: EPoolId
  alias __MODULE__

  @type name :: {:gear, GearName.t(), String.t()} | {:tenant, TenantId.t(), String.t()}

  @doc false
  defun make_name(epool_id_or_context :: v[EPoolId.t() | Context.t()], name :: v[String.t()]) ::
          name do
    {gear_or_tenant, id} =
      case epool_id_or_context do
        %Context{executor_pool_id: epool_id} -> epool_id
        epool_id -> epool_id
      end

    {gear_or_tenant, id, name}
  end

  defmodule Unique do
    @moduledoc """
    A global (cluster-wide) process registry to implement 1-to-1 process communications.

    Process names can be arbitrary string as long as it's unique within an executor pool.
    Each process is not allowed to have more than one name.
    When the registered process dies its name will be automatically removed from the registry.

    Note that the uniqueness of names is not strictly checked;
    in case of race conditions of simultaneous registrations on different nodes,
    multiple processes successfully register the same name.
    The conflict will be resolved by choosing a single process and killing the others.
    To avoid troubles with this kind of naming conflicts,
    it's recommended to use intrinsically unique IDs such as login IDs of clients.
    """

    defun register(name :: v[String.t()], epool_id_or_context :: v[EPoolId.t() | Context.t()]) ::
            :ok | {:error, :taken | :pid_already_registered} do
      :syn.register(Registry.make_name(epool_id_or_context, name), self())
    end

    defun send_message(
            name :: v[String.t()],
            epool_id_or_context :: v[EPoolId.t() | Context.t()],
            message :: any
          ) :: boolean do
      case :syn.find_by_key(Registry.make_name(epool_id_or_context, name)) do
        :undefined ->
          false

        pid ->
          send(pid, message)
          true
      end
    end
  end

  defmodule Group do
    @moduledoc """
    A global (cluster-wide) process registry for implementing publisher-subscriber communication pattern.

    In this registry you can register multiple processes with the same name.
    Then you can broadcast a message to the group of processes having the same name.
    Group names can be arbitrary string.
    Each process can join multiple groups at the same time.
    When the registered process dies its pid will be automatically removed from all the groups that the process has joined.
    """

    defun join(name :: v[String.t()], epool_id_or_context :: v[EPoolId.t() | Context.t()]) :: :ok do
      :syn.join(Registry.make_name(epool_id_or_context, name), self())
    end

    defun leave(name :: v[String.t()], epool_id_or_context :: v[EPoolId.t() | Context.t()]) ::
            :ok | {:error, :pid_not_in_group} do
      :syn.leave(Registry.make_name(epool_id_or_context, name), self())
    end

    defun publish(
            name :: v[String.t()],
            epool_id_or_context :: v[EPoolId.t() | Context.t()],
            message :: any
          ) :: non_neg_integer do
      {:ok, count} = :syn.publish(Registry.make_name(epool_id_or_context, name), message)
      count
    end
  end
end
