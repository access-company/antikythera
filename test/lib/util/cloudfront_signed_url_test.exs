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

  @signature_without_query "DE1GkSlp4UtQkIBBATpBnzyyr7hGLzwV39CrN~VHRgWCA9pnlrW5KW8qkARdK7ZvuQ21L5dLJ39hYzfFguY-3jVVXEnhD9Vi~ilVXypM84E7K3HZvOev0ZFJexSDXLFUGqrh8WcU~CTvX-RNywY3SLLQEIXjufPQbhNqIvRs-jFnQfEw1dn2KMYpFQ1xMFYUygMxT0yccE0OHnjBA94LOmpyDs42ZS3LVmeD~dPlnCMfJL14mV9awgNqN5rlfdhG2I~STDNA4qNadG~-BpWiTq6L3DnM2ZmqdDq-fE4QbBY7MyUJILnUyRVzojpaHJ1T-6ibXRvwdFAxJucefCkbZA__"
  @signature_with_query    "AFkIdETPTReVQFNRO4jJkEn942YktXEtQmEpAc8r02~ttCXpHuMomuzZzHanDkG-NBpqc86iohNQ25vICobDqtl3-VWFn~ZjESBFl2oUxLERryCAWh--Ffi7Q7p2~~dFgQ64~Vt9H8JmEuHx9otBFVroF97FfK9JbyGyId965T1RwC0FG-0OMHM1YsJSO9hY0iI5iTbzY-HyPIcLiYzYUPaD2~RVGPLQclnKP0oHprWfsde5zdfl5hIRG6HH3qmWPN5tr61PNQ~vdNqlfvs14B1oLZvcSqz17BZCLzpyKxwz8jv4qGpGH9JfsA599js6pUj2BI2xkcfle1XXAj2K-Q__"

  defp assert_queries(query_list, expected_signature) do
    [
      {"Expires"    , expires    },
      {"Signature"  , signature  },
      {"Key-Pair-Id", key_pair_id},
    ] = query_list
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
    assert_queries(query_params, @signature_without_query)
  end

  test "should generate a signed URL for URL with query", %{lifetime: lifetime} do
    signed_url = CloudfrontSignedUrl.get_signed_url(@resource_url <> "?hello=world", lifetime, @key_pair_id, @private_key)
    query_params = assert_base_url_and_get_query_params(signed_url)
    [{"hello", "world"} | tail] = query_params
    assert_queries(tail, @signature_with_query)
  end
end
