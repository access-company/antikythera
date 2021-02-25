# Changelog of Interfaces Provided by Antikythera

This file contains the history of **backward-incompatible changes** in interfaces of antikythera
which are exposed to antikythera instance administrators and/or gear developers.

---

- 0.4.0:
    - Add a new callback named `health_check_grace_period_in_seconds/0` to `AntikytheraEal.ClusterConfiguration.Behaviour`.
- 0.3.0:
    - Upgrade Elixir to v1.9 series.
    - Strict check of Erlang and Elixir versions is no longer done by antikythera. If an antikythera instance wants to make these versions in sync, it has to check these versions itself.
    - Error handler for invalid executor pool ID is added; log message is no longer automatically emitted.
- 0.2.0:
    - Rate limiting on accesses to async job queues was introduced.
    - `.tool-versions` file was included in hex package. Antikythera fetched from hex.pm should now be properly compiled.
