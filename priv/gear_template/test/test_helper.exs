SolomonLib.Test.Config.init()

defmodule Req do
  use SolomonLib.Test.HttpClient
end

defmodule Socket do
  use SolomonLib.Test.WebsocketClient
end
