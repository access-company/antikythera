# Limitation

There are certain limitations in Antikythera.
We introduce some major limitations here. But this does not cover all the limitations of Antikythera. Please also read other parts of the documentation when you implement gear.

* There is an upper limit of the execution time of web/g2g request.
  * Please refer [here](https://hexdocs.pm/antikythera/development_environment.html#environment-variables-to-tweak-behavior-of-antikythera)
* There is an upper limit of the execution time of `AsyncJob`.
  * `AsyncJob` has other limitations too. Please refer [here](https://hexdocs.pm/antikythera/Antikythera.AsyncJob.html#module-registering-jobs)
* There is an upper limit of heap size which a process can use.
  * Please refer [here](https://hexdocs.pm/antikythera/development_environment.html#environment-variables-to-tweak-behavior-of-antikythera)
  * If the size of the heap used by process exceeds the upper limitation, an error log is written.( ex: `xxx killed`)
