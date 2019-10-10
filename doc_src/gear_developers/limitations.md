# Limitations

There are certain limitations in Antikythera.
We list some major limitations here. But this does not cover all the limitations of Antikythera. Please also read other parts of the documentation when you implement gear.

- Execution time of web/g2g request
    - Set via `GEAR_ACTION_TIMEOUT`. Please refer [here](https://hexdocs.pm/antikythera/development_environment.html#environment-variables-to-tweak-behavior-of-antikythera).
- Execution time of async job
    - Set via `max_duration`. Please refer [here](https://hexdocs.pm/antikythera/Antikythera.AsyncJob.html#module-registering-jobs).
    - Async job has other limitations too.
- Heap size which a process can use
    - Set via `GEAR_PROCESS_MAX_HEAP_SIZE`. Please refer [here](https://hexdocs.pm/antikythera/development_environment.html#environment-variables-to-tweak-behavior-of-antikythera).
    - When a process uses more memory than the limit, Antikythera kills the process and outputs error log(e.g. `xxx killed`).
