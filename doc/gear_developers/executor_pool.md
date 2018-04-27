# "Executor Pool" for Resource Management

## Purpose

Antikythera supports multi-application (multi-gear) and multi-tenant workloads.
This means that multiple gears and multiple tenants share the same computing resources in an antikythera cluster.
In order to mitigate influences of heavily-loaded gear and/or tenant on the other gears/tenants,
antikythera controls execution of simultaneously running tasks using "executor pool"s.

Each executor pool consists of the following pools of Erlang processes:

- Processes for web request processing
- Processes for websocket connections
- Processes for [async job](./async_job.md) execution

Number of processes in the pools are managed by the antikythera core.
These types of pools in an executor pool are independent of each other,
i.e., web request processing does not affect async job execution.

Executor pools are classified into the following two categories:

- Gear executor pool:
    - An executor pool that associates with exactly one gear.
      This type of executor pools is for e.g.
        - Gears that do not have multi-tenant use cases,
        - Gears that do support multi-tenant but need to process tasks which do not belong to any tenants.
    - Every time a gear starts/stops (i.e. antikythera installs/uninstalls a gear) the gear's executor pool is also created/terminated.
      Thus each gear can always use its own gear executor pool.
- Tenant executor pool:
    - An executor pool that associates with a "tenant" which represents a set of request senders.
      This type of executor pools is intended for gears that provide service to multiple tenants.
    - TODO: write about life-cycle of tenant executor pools
    - Note that this type of executor pools can be used by multiple gears.

Each task (e.g. web request processing) is executed by an Erlang process in the executor pool that corresponds to the task;
thus simultaneous task executions are capped by the number of processes in each executor pool.

## How to choose target executor pool for the given task

### Web requests

- To handle an incoming web request, gear implementations must choose an appropriate executor pool for the request.
    - The target executor pool must be specified by `YourGear.executor_pool_for_web_request/1`
      which receives a `Antikythera.Conn.t` and returns a `Antikythera.ExecutorPool.Id.t`.
    - Implementations of `executor_pool_for_web_request/1` must be [pure](https://en.wikipedia.org/wiki/Pure_function);
      i.e. return value must be computed solely from the given `Antikythera.Conn.t`.
    - When the executor pool specified by `executor_pool_for_web_request/1` is overloaded and
      no available executor process found within 5 seconds, the request results in an error.
- In development environment (more precisely, when `Antikythera.Env.compiling_for_release?() == true`),
  the returned value from `YourGear.executor_pool_for_web_request/1` is basically neglected and
  gear executor pool is used for all requests to simplify setting-up of gear development.
- For gear-to-gear requests it's not necessary to choose an executor pool to use;
  no additional executor pool is necessary to process gear-to-gear requests.

#### Example implementations of `executor_pool_for_web_request/1`

1. A gear that does not support multi-tenant use cases:
  uses its gear executor pool for all requests

    ```ex
    def executor_pool_for_web_request(_conn) do
      {:gear, :your_gear}
    end
    ```

2. A gear that serves to multiple tenants:
  specifies tenant ID included in the request path

    ```ex
    def executor_pool_for_web_request(%Conn{request: req}) do
      {:tenant, req.path_matches[:tenant_id]}
    end
    ```

### [Async jobs](./async_job.md)

- When you register your async jobs, you must specify which executor pool to use as arguments to `YourGear.SomeAsyncJob.register/3`.
  See [API reference](https://ac-console.solomondev.access-company.com/exdoc/antikythera/Antikythera.AsyncJob.html) for detailed explanation.

## Associations between gears and tenant executor pools

- After choosing an executor pool for a task (by e.g. `SomeGear.executor_pool_for_web_request/1`),
  antikythera verifies that the gear is allowed to use the specified executor pool.
    - The primary purpose of this verification is to protect from DoS attack by requests containing invalid tenant IDs.
- Available executor pools for a gear are:
    - the gear executor pool of the gear
    - tenant executor pools associated with the gear
- Therefore developer of a gear that uses tenant executor pool must establish associations
  between his/her gear and target tenant executor pools to use.
- You can associate tenant executor pools with your gear from within `ac_console` ([dev](https://ac-console.solomondev.access-company.com)/[prod](https://ac-console.solomon.access-company.com))

## Managing capacity of executor pools

- As of this writing, capacities of executor pools are centrally controlled by the antikythera team.
  Please contact the antikythera team to request a limit increase.

## Limits for gear processes

- In addition to capping of simultaneous processes by executor pools,
  antikythera imposes memory usage limit (up to 400MB on 64bit machine) on each process that runs under an executor pool.
    - Any process that violates this upper limit will be killed.
- This limit, together with the limit on number of processes, protects the entire ErlangVM from running out of memory.
