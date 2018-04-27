defmodule <%= gear_name_camel %>.Router do
  use SolomonLib.Router

  get "/hello", Hello, :hello
end
