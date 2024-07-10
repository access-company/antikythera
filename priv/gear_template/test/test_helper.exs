Antikythera.Test.Config.init()

defmodule Req do
  use Antikythera.Test.HttpClient
end

defmodule Socket do
  use Antikythera.Test.WebsocketClient
end

defmodule OpenApiAssert do
  use Antikythera.Test.OpenApiAssertHelper,
    yaml_files: ["doc/api/api.yaml"]
end
