# Copyright(c) 2015-2021 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Plug.ContentDecoding do
  @moduledoc """
  Plug to decompress the request body when the request has `Content-Encoding` header.

  Currently only `gzip` is supported.

  Antikythera does not transparently handle compressed request body, as [cowboy](https://github.com/ninenines/cowboy/issues/946).
  Compression can pack very large data into a small body, so automatically decompressing it may lead to running out of memory.

  Therefore, this plug can be used only if the request client is trusted (e.g. after authentication).
  """
end
