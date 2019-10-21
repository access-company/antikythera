# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.CloudfrontSignedUrlTest do
  use Croma.TestCase
  alias Antikythera.CloudfrontSignedUrl

  @resource_url       "http://123456abcdefg.cloudfront.net/index.html"
  @expires_in_seconds 2_147_483_646
  @key_pair_id        "ABCDEFGHIJKLMNOPQRST"
  @private_key        """
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
  @signature_with_query    "TTfoKwPF7xn-ZRilOXwuidh1tAtJFJm8BPs6dBc4zLNGlgV~V7XN1YvDy5xNgZInUf1CvpvRMW0NFUqxJqNZd3FOk6QpySVoHbWYQWYoEH2eWV5cftYtJi2GUaol~yDLEN36zuOHmDSfYpSPktYIePiagz9e3R3ZzNEQUCpIZTO8XfJiISCoHkREeJxA4slMQhhuofFwSCfr2yW2ZMVk75JxPtNmAde-sj4C09PORyNWTuWOoYYghb5DfF4yDlk5WeQKCwGmjhsQ7mM7UMU3xk-fOKWdZcyxUIjqxlQSQEVVwP4QlHdFo4y2uNhER8e0HvhQk-Pbpfj~JFePmeNoPA__"

  defp assert_query_params(query_params, expected_signature) do
    [
      {"Expires"    , expires    },
      {"Signature"  , signature  },
      {"Key-Pair-Id", key_pair_id},
    ] = query_params
    assert expires     == Integer.to_string(@expires_in_seconds)
    assert signature   == expected_signature
    assert key_pair_id == @key_pair_id
  end

  defp assert_base_url_and_get_query_params(url) do
    %URI{host: host, path: path, query: query, scheme: scheme} = URI.parse(url)
    assert "#{scheme}://#{host}#{path}" == @resource_url
    URI.query_decoder(query) |> Enum.to_list()
  end

  setup do
    lifetime = 60
    :meck.expect(System, :system_time, fn :second -> @expires_in_seconds - lifetime end)
    on_exit(fn -> :meck.unload() end)
    %{lifetime: lifetime}
  end

  test "should generate a signed URL for URL without query", %{lifetime: lifetime} do
    signed_url = CloudfrontSignedUrl.get_signed_url(@resource_url, lifetime, @key_pair_id, @private_key)
    query_params = assert_base_url_and_get_query_params(signed_url)
    assert_query_params(query_params, @signature_without_query)
  end

  test "should generate a signed URL for URL with query", %{lifetime: lifetime} do
    signed_url = CloudfrontSignedUrl.get_signed_url(@resource_url <> "?hello=world", lifetime, @key_pair_id, @private_key)
    query_params = assert_base_url_and_get_query_params(signed_url)
    [{"hello", "world"} | tail] = query_params
    assert_query_params(tail, @signature_with_query)
  end
end
