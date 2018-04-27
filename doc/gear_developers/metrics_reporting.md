# Metrics Reporting

- In antikythera core and gears, statistical metrics can be generated.
- Generated metrics are buffered, aggregated, then flushed to stable storage **every minute**.
- By default, antikythera uses Elasticsearch as its metrics storage,
  utilizing its search/aggregation feature and visualization with Kibana.
- All metrics are stored in `metrics-YYYY.MM.DD` indices under `antikythera` subspace.
    - Regarding antikythera Elasticsearch and its subspace structure, see [doc](./elasticsearch.md) for details.
    - These indices can be searched from ac_console endpoint.
      ([dev](https://ac-console.solomondev.access-company.com/antikythera_es/) /
      [prod](https://ac-console.solomon.access-company.com/antikythera_es/))
- All metrics documents come with following predefined fields:
    - `@timestamp`
    - `node_id`
    - `otp_app_name`
        - `antikythera` or gear name
    - `epool_id`
        - `gear-<gear_name>` or `tenant-<tenant_id>`
        - Exists only in [executor pool](./executor_pool.md) related metrics
- Metrics are stored for 1 month. Older indices will be automatically deleted.

## Auto-collected metrics

- The following metrics are automatically gathered by antikythera:
    - Metrics about web/[g2g](./g2g.md) requests
        - Number of processed requests (`web/g2g_request_count_*`)
        - Time distribution of response times (`web/g2g_response_time_ms_*`)
        - Executor pool checkout failure count (`web_timeout_in_epool_checkout_sum`)
        - Number of working processes for web request handling in an executor pool (`epool_working_action_runner_*`)
    - Metrics about [websocket](./websocket.md) interactions
        - Number of active connections (`epool_websocket_connections_*`)
        - Number of rejected attempts to establish websocket connections (`epool_websocket_rejected_count`)
        - Number of received/sent websocket frames (`websocket_frames_received/sent`)
    - Metrics about [async job](./async_job.md)
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
- For quick visualization of any metrics, use Kibana from ac_console endpoint
  ([dev](https://ac-console.solomondev.access-company.com/antikythera_es/_plugin/kibana/index.html) /
  [prod](https://ac-console.solomon.access-company.com/antikythera_es/_plugin/kibana/index.html))
    - Put `otp_app_name: <gear_name>` in search box to narrow down.
    - The metrics indices and ac_console Kibana are shared among gear developers, so use carefully and responsibly.
- `antikythera_sysytem_dashboard` and `gear_metrics_dashboard` are embedded in ac_console for quick check.
- See [doc](./elasticsearch.md) and links therein for more detailed Elasticsearch and Kibana usage.
- Note that all metrics are aggregated in uploader process **per node**, then uploaded to Elasticsearch.
  There you will aggregate those metrics **across nodes** (mostly via Kibana query).
    - This two-phase aggregation provides the entire view of metrics from applications running in multiple nodes,
      while reducing volume of network traffic.
    - However, total metrics could be inaccurate, even with a coherent strategy is used.
      e.g. A sum of per-node sums is an accurate total sum, but an average of per-node averages is not an accurate total average.
