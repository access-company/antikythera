# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.Aws.CloudfrontSignedUrlTest do
  use Croma.TestCase

  @resource_url "http://123456abcdefg.cloudfront.net/index.html"
  @expires_in_seconds 2_147_483_646
  @key_pair_id "ABCDEFGHIJKLMNOPQRST"
  @private_key """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEogIBAAKCAQEAiCibBsb6xu31bfU57wJb4tOw6mzon+bY183pkt2CKGYA8l1n
  nc7hZK0KXg/1PzA7UwnN3IOuQ46jVZOE/m0kGhQs3E0OLxz2fWuRAMwvjMms6ibM
  xzHO5xTYwTHAqUioyY1/NtRfOv6QnXIWWUloY69KYHC/0yOX4F3sS2u5MtD61QFm
  DFTgj7KEfMLX4z1n/z+pMyKDZXmGfsMLBlzAC02QZddOf7OlqXwjf+JpqKkdQf/J
  V2zWqbVmbXRj/XX3WNoebsgdqG0NV80Td1dYdLhegvjaDdR3tCdYmKBMEWsU/a4f
  tRYGbqPX4odcFyzbTvYmrXfnDldec7WN3Htl1QIDAQABAoIBAF7GdPKIurKRnI7H
  bWYS7Ea9N55V5K65DyNYL0eNbDYWmn4ZyjAsevOLB3ZmAT3UotawMl1WQ4y+0q6U
  mrRG4CRO+tL1x/O/Y0v1/d7iQg7rqrLqAwx8fRqYhjAkI4kyDFsPZQeTWB5GZ/9Q
  FIJd+I26zDjJAp1DX0pL1ljBSQ43IykHTF1skJeZZGkix0eO9yf8Ocsrd0axj0JJ
  JUCsKvChv2Xb3gAPBxcu8WbnpKRuVvl0JPXwkK4nnMKaKUGE3zAzlBlw7u4lqtlu
  S77vvFkjHxdbd/iSvuQmQg9Ll6sPg4TbrnkcCndzzXu++mmrI2gJD4W23zoU4BOS
  S9Kwi9kCgYEA5xVGUWpOl+Vhd7YAUJhitk95Pvt+XMiC7qmJSzot5arA/YfZjxIg
  oGFecKBkuWsPB8BAE4HEqRTVkozprngWQ08ZHkfZxiUTwDwsC2IlkSl2UbNM1DUn
  +YVRCS++ycHKTmshzuodBeS3cQxDpJR10OhGCAvyeJGxlRxsHYQS4JcCgYEAltcS
  yRgAkigiOY5Gnf71ad9YJNYRKd36I9lDie+1hxT/umNGqyW2/GcSFDdsHWD+6Mgj
  I2B5PMB5/YyeFPUX3jXkZfS7rR72FCFs24SdSzNVCgZq8NMDWCy4fOEQye/IYXID
  6EBeejeS92wkdUa6J57zD1cJ911033uSIGTRznMCgYEAmgPz+g+AknyvmboUO6NV
  J22QwgmdDvoVSjx05U7BiHFmb5Q7zL+oPzymVSqR94MDYYchLd8v1AGu1x5UIZSo
  QfRWKXh6DTZpE5cHRA8GOtoHoix+6HEFU6kneZf48T/YNqvwvJgNAACQwygJbYgF
  fldRVcugr/trAJcQ+Bsu+cECf2Qqbk8boUVtYUzXLg29QTsNFXtgrAUhYvprTG5M
  wD7zst4TDtqYMOtrhpXmN+VKg/wQ60SSy++L4XZ96nwARdlJ8GHEItzTspWrnJ4p
  ckp9y/rcSCej+JSVHe3Ph1aR5H7RN8cC97oxLWcgaRV34iZtZvrI0dVyOiot5Nue
  F7UCgYEAgCyKtFPFXTGgGpUVVdD7qvbt5lh3+eAN2EgUIFu6bn+X+t4p1EXXK4ED
  E25nYe8lbUQC7yZaKHoa83MupJ1ideBR4asIu9jZp88UJlG3SKftucSx07xZVYqG
  ZUrSo7mF2SQO0bv13KTB1BCWb2SoQr6Jy6beVMFFFQii5LaMB6M=
  -----END RSA PRIVATE KEY-----
  """

  @signature_without_query "WN~hWyAYH2FAL1C-4-zPkqFvsjiuo80BfAR9yE4t3qLRln62B9TQ1Ck~VZFcGvtPcFz9Gqw8dcy1BOAcRKdMs5JqWCYQiijHRurXnok3TZmxOAMEHOKv0HjTcnRD9kcR7YikW7BE9I03VASHE0wx8GieB2VQEg3uhbbdzVVQoDw27O9NUwbmKlw5dHqJW6m3jrFxEG1ALH50XENAtMeP96-EtdPOOQenlWzlBio1fOOGideNb4VQdPOG-QjLuzaGN8aGgDeeiXvEwVG-WstwgJdXwqA2ucdXY5SVty5356e9GWQ9KhsSpoznYdhnFdRjVXDayNzkYMNuxXVdtFMvNQ__"
  @signature_with_query1 "TzC4VcV7T1RRoiE32iSIzPxkD9X4-hHKrBWgLgDUuCay~Sqt3E1fb~z4eShZUw6-wGZIC3rFaYUJ9SswQZpaGe6mRUCscqBJQ0uilpMsxq2bZl6HU5sGAagD6tD9~MAlWs8Q74BUVs8CbUmsX2buKHvRdnvnmkhjM4KocFaOsIBeHWxb3M0L~lYokjRaSHs3NUcACne6vo0~AB6fwwfkJ1bvxBD2KHDzbMHY2NrKau0zBkgRHcofr9tRNa7fPT-rwrdNVDcViFwnf1i3D2PSInWeVJuD9s9w7gU4Wigv5Y0OkYION-ZZkEswPUVEgttJSOKrP8DHgL6LQ1b~Vbgg9g__"
  @signature_with_query2 "TTfoKwPF7xn-ZRilOXwuidh1tAtJFJm8BPs6dBc4zLNGlgV~V7XN1YvDy5xNgZInUf1CvpvRMW0NFUqxJqNZd3FOk6QpySVoHbWYQWYoEH2eWV5cftYtJi2GUaol~yDLEN36zuOHmDSfYpSPktYIePiagz9e3R3ZzNEQUCpIZTO8XfJiISCoHkREeJxA4slMQhhuofFwSCfr2yW2ZMVk75JxPtNmAde-sj4C09PORyNWTuWOoYYghb5DfF4yDlk5WeQKCwGmjhsQ7mM7UMU3xk-fOKWdZcyxUIjqxlQSQEVVwP4QlHdFo4y2uNhER8e0HvhQk-Pbpfj~JFePmeNoPA__"
  @signature_with_query3 "BzTb7kOa1P2sp2lO~sO4j17b7UZpxgDXIvR4ET5FFa0rwu9Z5u9ubC09EGjHn9r-k~pxWu-KJyvr--f0MDNtUGWR5fgOb74iobt4GP9-NsS9WRu3JdhFZXHqAGkPF9TtSXrP8qMtcsBJ~F0SWeWevdhU19FMPH4hIe9ff0m2J29BIFZUe9~fyWh3daMQ9aC7Zf84G3V00FW~v21ggcRhDgkLdN6eUCm-cayzs6kZhr0V6PABjw0Ve9hJbAHC-B2PbTwfFVkiLn0B4dQtgwYC9NHhvWzil7xGBhJvAX7CPJJNImi~A1x8FdigTgMUXg4fwAapj0tk4FmkFu-NHI-AQg__"

  defp assert_query_params(query_params, expected_signature) do
    [
      {"Expires", expires},
      {"Signature", signature},
      {"Key-Pair-Id", key_pair_id}
    ] = query_params

    assert expires == @expires_in_seconds
    assert signature == expected_signature
    assert key_pair_id == @key_pair_id
  end

  defp assert_base_url_and_key_pair_id(url) do
    %URI{host: host, path: path, query: query, scheme: scheme} = URI.parse(url)
    assert "#{scheme}://#{host}#{path}" == URI.encode(@resource_url)
    query_params = URI.query_decoder(query) |> Enum.to_list() |> Enum.take(-3)

    [
      {"Expires", _},
      {"Signature", _},
      {"Key-Pair-Id", key_pair_id}
    ] = query_params

    assert key_pair_id == @key_pair_id
  end

  test "should generate a signature for URL without query" do
    CloudfrontSignedUrl.make_query_params(
      @resource_url,
      @expires_in_seconds,
      @key_pair_id,
      @private_key
    )
    |> assert_query_params(@signature_without_query)
  end

  test "should generate a signature for URL with query" do
    [
      {"?", @signature_with_query1},
      {"?hello=world", @signature_with_query2},
      {~s/?hello="日本"&/, @signature_with_query3}
    ]
    |> Enum.each(fn {query, expected_signature} ->
      resource_url = URI.encode(@resource_url <> query)

      CloudfrontSignedUrl.make_query_params(
        resource_url,
        @expires_in_seconds,
        @key_pair_id,
        @private_key
      )
      |> assert_query_params(expected_signature)
    end)
  end

  test "should return encoded URL" do
    ["", "?", "?hello=world", ~s/?hello="日本"&/]
    |> Enum.each(fn query ->
      resource_url = @resource_url <> query

      signed_url =
        CloudfrontSignedUrl.generate_signed_url(resource_url, 60, @key_pair_id, @private_key)

      joiner = if query == "", do: "?", else: "&"
      assert String.starts_with?(signed_url, URI.encode(resource_url) <> joiner <> "Expires=")
      assert_base_url_and_key_pair_id(signed_url)
    end)
  end

  test "should preserve the original URL if it is encoded" do
    ["", "?", "?hello=world", ~s/?hello="日本"&/]
    |> Enum.each(fn query ->
      resource_url = URI.encode(@resource_url <> query)

      signed_url =
        CloudfrontSignedUrl.generate_signed_url(
          resource_url,
          60,
          @key_pair_id,
          @private_key,
          true
        )

      joiner = if query == "", do: "?", else: "&"
      assert String.starts_with?(signed_url, resource_url <> joiner <> "Expires=")
      assert_base_url_and_key_pair_id(signed_url)
    end)
  end
end
