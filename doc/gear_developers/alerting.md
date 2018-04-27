# Alerting

- When error logs are reported via `YourGear.Logger.error/1` function,
  the errors are sent to developers as alerts.
- It is also possible to send alerts without logging,
  by calling `YourGear.AlertManager.notify/1` function from any part of your gear code.
- Currently, only email alerting is supported, and it is automatically configured for newly created gears.
    - The email address of the `ac_console` login user is used as the default destination.
    - [HipChat](https://www.hipchat.com/), [Linkit](https://jin-soku.biz/linkit/) and [Twillio](https://www.twilio.com/)
      are candidates for alternative notification channels to support. Requests and contributions are welcomed.

## Alert behavior and configurations

- To prevent excessive number of alerts from being sent, alert handlers have a built-in buffering mechanism.
- Occasional errors will be sent in shorter period of buffering (called `fast_interval`, 1 minute by default).
- If errors keep occurring beyond `fast_interval`,
  they will be buffered for longer period (called `delayed_interval`, 30 minutes by default) before sent.
- These intervals are configured per alert methods.
- Required and optional settings (such as addresses for email alert), along with intervals above,
  can be configured in `ac_console`.
  ([dev](https://ac-console.solomondev.access-company.com)/[prod](https://ac-console.solomon.access-company.com))
    - See "Alerts" in your gear's setting view.
