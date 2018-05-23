# Metrics Reporting

**Note:** This page is being updated for OSS release. Please be patient.
Current contents describes how we are handling our antikythera instance's and gears' metrics data in [ACCESS](https://www.access-company.com).

- In antikythera core and gears, statistical metrics can be generated.
- Generated metrics are buffered, aggregated, then flushed to stable storage **every minute**.
- By default, antikythera uses Elasticsearch as its metrics storage,
  utilizing its search/aggregation feature and visualization with Kibana.
- All metrics are stored in `metrics-YYYY.MM.DD` indices under `antikythera` subspace.h
- All metrics documents come with following predefined fields:
    - `@timestamp`
    - `node_id`
    - `otp_app_name`
        - `antikythera` or gear name
    - `epool_id`
        - `gear-<gear_name>` or `tenant-<tenant_id>`
        - Exists only in [executor pool](https://hexdocs.pm/antikythera/executor_pool.html) related metrics
- Metrics are stored for 1 month. Older indices will be automatically deleted.

## Auto-collected metrics

- The following metrics are automatically gathered by antikythera:
    - Metrics about web/[g2g](https://hexdocs.pm/antikythera/g2g.html) requests
        - Number of processed requests (`web/g2g_request_count_*`)
        - Time distribution of response times (`web/g2g_response_time_ms_*`)
        - Executor pool checkout failure count (`web_timeout_in_epool_checkout_sum`)
        - Number of working processes for web request handling in an executor pool (`epool_working_action_runner_*`)
    - Metrics about [websocket](https://hexdocs.pm/antikythera/websocket.html) interactions
        - Number of active connections (`epool_websocket_connections_*`)
        - Number of rejected attempts to establish websocket connections (`epool_websocket_rejected_count`)
        - Number of received/sent websocket frames (`websocket_frames_received/sent`)
    - Metrics about [async job](https://hexdocs.pm/antikythera/async_job.html)
        - Number of completed/failed jobs (`async_job_success/failure_sum`)
        - Time distribution of async job executions (`async_job_execution_time_ms_*`)
        - Number of waiting jobs in job queue (`epool_waiting_job_count`)
        - Number of runnable jobs in job queue (`epool_runnable_job_count`)
        - Number of running jobs in job queue (`epool_running_job_count`)
        - Number of waiting job brokers (`epool_waiting_broker_count`)
        - Number of working processes for async job in an executor pool (`epool_working_job_runner_*`)

## Custom metrics

- You can generate and collect arbitrary numeric metrics from your gear's code.
- Field names for such metrics are prefixed with `custom_`
  and can be searched/visualized just like auto-generated metrics.
- Use `YourGear.MetricsUploader.submit/2` from anywhere in your code to generate metrics.
  `YourGear.MetricsUploader` process will then buffer and aggregate them before uploading.
    - First argument is metrics data list (`Antikythera.Metrics.DataList.t`).
        - `strategy` for each data must be an atom representation of one of aggregation strategies.
          Currently available strategies are:
            - `:average`
            - `:sum`
            - `:time_distribution`
                - Generates average, max and 95-percentile values
            - `:gauge`
                - Takes last value of each time window
    - Second argument is the context (`Antikythera.Context.t`) from which the currently used executor pool ID will be extracted.

## Metrics search and visualization

- Simply search `metrics-*` indices with filtering on `otp_app_name` field using your gear name.
- Note that all metrics are aggregated in uploader process **per node**, then uploaded to Elasticsearch.
  There you will aggregate those metrics **across nodes** (mostly via Kibana query).
    - This two-phase aggregation provides the entire view of metrics from applications running in multiple nodes,
      while reducing volume of network traffic.
    - However, total metrics could be inaccurate, even with a coherent strategy is used.
      e.g. A sum of per-node sums is an accurate total sum, but an average of per-node averages is not an accurate total average.
