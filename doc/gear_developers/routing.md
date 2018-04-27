# Web Requests Routing

- Antikythera's web request router consists of the following 2 stages:
    - Domain-based routing
    - Path-based routing
- This process is schematically shown in the following flow diagram:

![](../images/RequestHandlingFlow.png)

## Domain-based routing to a specific gear

- Antikythera hosts multiple running gears and incoming web requests are routed based on the domain part of the URL.
- When a gear is started, antikythera's routing layer registers the domains of the gear and subsequent requests to the domains will be routed to the gear.
- Each gear's domain is configurable and defaults to the following subdomain (note that `_`s in gear name are replaced by `-`s):
    - local environment: `<gear-name>.localhost:8080` (when you run `$ iex -S mix` in your gear project)
    - dev   environment: `<gear-name>.solomondev.access-company.com`
    - prod  environment: `<gear-name>.solomon.access-company.com`

## Path-based routing to a specific controller action

- Once an appropriate gear for an web request is determined based on the domain part,
  antikythera then routes the request to a controller action by matching URL path and HTTP method.
- Gears must define the routing rules in `web/router.ex`.
    - Refer to [ExDoc document](https://hexdocs.pm/antikythera/Antikythera.Router.html) of [`Antikythera.Router`](../../lib/web/router/router.ex) for details of the routing DSL.
