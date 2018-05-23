# Asynchronous Jobs

**Note:** This page is being updated for OSS release. Please be patient.

Antikythera provides gears with a way to asynchronously run arbitrary code.
This feature is referred to as "async job" throughout documentations of antikythera.
Async jobs are executed in background of HTTP request/response interactions.

Async jobs are useful for tasks such as:

- batch inserts
- sending many emails
- download and process files
- scheduled jobs

Antikythera's async job processing comes with the following features:

- Automatic retry of failed jobs
- Support of timed jobs (jobs that start at specified times)
- Support of recurring schedule (using crontab format)
- Timeout of job execution
- Load balancing of job executions within ErlangVMs in the cluster
- Resource capping (implemented in terms of [executor pools](https://hexdocs.pm/antikythera/executor_pool.html))

## Usage example

To use async job, gear implementation must define a module that `use`s `Antikythera.AsyncJob`.

```ex
defmodule YourGear.SomeAsyncJob do
  use Antikythera.AsyncJob

  def run(payload, _job_id, _context) do
    # put arbitrary code here
    YourGear.Logger.info(inspect(payload))
  end
end
```

Then invoke `YourGear.SomeAsyncJob.register/3`.
You can register new jobs from within both controller actions and async jobs.
In your local development environment you can try within `$ iex -S mix`.

```ex
YourGear.SomeAsyncJob.register(%{"arbitrary" => "map"}, {:gear, :your_gear})
```

Internally, it inserts the job to a job queue for executor pool `{:gear, :your_gear}`,
the job queue notifies a broker process of the newly registered job,
the broker spawns a worker to run the job,
and then the following call to `YourGear.SomeAsyncJob.run/3` is evaluated within the worker:

```ex
YourGear.SomeAsyncJob.run(%{"arbitrary" => "map"}, job_metadata, context_for_this_job_execution)
```

For details of the async job API please refer to `Antikythera.AsyncJob`.
