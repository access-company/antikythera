# Logging

- From any part of your gear code, you can put messages to log files.
  Pass a `String.t` to one of the following functions:
    - `YourGear.Logger.error/1`
    - `YourGear.Logger.info/1`
    - `YourGear.Logger.debug/1`
- `error`, `info`, `debug` are the log levels that represent severity of each message.
- You can configure your logger setting to include which levels of messages to be included in your logs.
  Default setting is `info` (i.e., `error` and `info` are included, `debug` is not included).
- On your local development environment, you can set your log level by setting `LOG_LEVEL` environment variable.
- Developers will be notified when any `error` level logs are reported. See [Alerting](./alerting.md) for details.

## Auto-generated log messages

- Information about incoming web requests is automatically logged, as in the following format:
  ```
  2016-01-26T00:40:22.557+00:00 [info] context=20160126-004022.557_ip-172-31-5-176_0.684.0 GET /path?query=params from=xxx.xxx.xxx.xxx START encoding=gzip, deflate, sdch
  2016-01-26T00:40:22.567+00:00 [info] context=20160126-004022.557_ip-172-31-5-176_0.684.0 GET /path?query=params from=xxx.xxx.xxx.xxx END status=200 time=10ms
  ```

    - `context` field is a context ID of the current request processing, in the form of `<start date and time>_<erlang node ID>_<process ID>`.
    - Query parameters are shown in the URL-decoded form.
    - `encoding` field is the value of `accept-encoding` request header. This field is shown mainly to check whether the client uses gzip/deflate compression.
- On start/end of [async job](./async_job.md) executions the following logs are generated:
  ```
  2016-08-06T09:17:24.043+00:00 [info] context=20160806-091724.043_ip-172-31-22-164_0.662.0 <async_job> module=Testgear.TestAsyncJob job_id=P97tnfACMEivaKW-3zey attempt=1th/3 run_at=2016-08-06T09:17:24.042+00:00 START
  2016-08-06T09:17:24.144+00:00 [info] context=20160806-091724.043_ip-172-31-22-164_0.662.0 <async_job> module=Testgear.TestAsyncJob job_id=P97tnfACMEivaKW-3zey attempt=1th/3 run_at=2016-08-06T09:17:24.042+00:00 END status=success time=71ms
  ```

    - `context` is the same as in the case of web requests (see above).
    - `module` is the name of the module which defines the job.
    - `attempt` is the number of job executions (including retries) for this job, together with its upper limit.
    - `run_at` is the start time specified by the job's schedule.
    - `status` is one of `success`, `failure_retry` and `failure_abandon`.
    - By providing implementation of `inspect_payload/1` callback, you can additionally include information of `payload`.
      This can be useful to easily identify jobs in logs.
      See documentation for `Antikythera.AsyncJob` for detail.
- Also websocket connected/disconnected events are logged:
  ```
  2016-11-09T04:47:19.089+00:00 [info] context=20161109-044719.089_ip-172-31-15-109_0.1164.0 <websocket> CONNECTED
  2016-11-09T04:47:19.831+00:00 [info] context=20161109-044719.089_ip-172-31-15-109_0.1164.0 <websocket> DISCONNECTED connected_at=2016-11-09T04:47:19.089+00:00 frames_received=0 frames_sent=0
  ```

    - `frames_received` is the number of frames the connection received from the client.
      Some control frames are automatically handled by antikythera and not included in the number.
    - `frames_sent` is the number of frames the connection sent to the client.
      Some control frames are automatically sent by antikythera and not included in the number.
- In addition to the default log messages explained above, antikythera automatically logs errors which occur during execution of gear code.

## Obtaining log files

- You can download your gear's log files from within `ac_console` ([dev](https://ac-console.solomondev.access-company.com)/[prod](https://ac-console.solomon.access-company.com)).
- Note that there are multiple running nodes in the antikythera instance and as such the log files are created on a per-node basis.
- Note also that log files will become downloadable in a few hours:
    - log files are rotated on every 2 hours, and
    - rotated logs are uploaded to cloud storage on every 30 minutes.
- Alternatively you can manually trigger rotation and upload of your gear's log files from within `ac_console` UI.
