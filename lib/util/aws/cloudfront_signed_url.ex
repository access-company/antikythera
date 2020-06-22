# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Aws.CloudfrontSignedUrl do
  @moduledoc """
  This module provides `generate_signed_url/5` to generate [a signed URL for CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-signed-urls.html)
  """

  @doc """
  Generates a signed URL to access a file via CloudFront.

  ## Parameters

  - `resource_url` (string): CloudFront URL used for accessing the file, including query string parameters, if any.
  - `lifetime_in_seconds` (positive integer): Expiration time is determined as the sum of the current time (in seconds) and this value.
  - `key_pair_id` (string): ID for an active CloudFront key pair used for generating the signature.
  - `private_key` (string): RSA private key for the key pair specified by `key_pair_id`.
  - `url_encoded?` (boolean): Whether `resource_url` is encoded or not (optional, default is `false`).

  ## Return value

  A generated signed URL (string).
  """
  defun generate_signed_url(resource_url        :: v[String.t],
                            lifetime_in_seconds :: v[pos_integer],
                            key_pair_id         :: v[String.t],
                            private_key         :: v[String.t],
                            url_encoded?        :: v[boolean] \\ false) :: String.t do
    encoded_url = if url_encoded?, do: resource_url, else: URI.encode(resource_url)
    expires_in_seconds = System.system_time(:second) + lifetime_in_seconds
    joiner = if URI.parse(encoded_url) |> Map.get(:query) |> is_nil(), do: "?", else: "&"
    encoded_url <> joiner <> URI.encode_query(make_query_params_for_canned_policy(encoded_url, expires_in_seconds, key_pair_id, private_key))
  end

  @doc """
  Generates a signed URL to access a file via CloudFront using a custom policy.

  ## Parameters

  - `resource_url` (string): CloudFront URL used for accessing the file, including query string parameters, if any.
  - `lifetime_in_seconds` (positive integer): Expiration time is determined as the sum of the current time (in seconds) and this value.
  - `key_pair_id` (string): ID for an active CloudFront key pair used for generating the signature.
  - `private_key` (string): RSA private key for the key pair specified by `key_pair_id`.
  - `url_encoded?` (boolean): Whether `resource_url` is encoded or not (optional, default is `false`).
  - `optional_policy` (Keyword): Optional policy conditions to be added to a custom policy (default is `[]`). Currently, supports only the following keywords:
    - `:date_greater_than`(integer >= 0): Seconds from `AWS:EpockTime`. Specified to `DateGreaterThan`
    - `:ip_address` (string): Specified to `IpAddress`. This must not contain any white spaces. This should be wrapped by `""`, e.g. `"1.1.1.1"`, and allows an array format e.g. `["1.1.1.1","1.1.1.2"]`.

  ## Return value

  A generated signed URL (string).
  """
  defun generate_signed_url_using_custom_policy(resource_url        :: v[String.t],
                                                lifetime_in_seconds :: v[pos_integer],
                                                key_pair_id         :: v[String.t],
                                                private_key         :: v[String.t],
                                                url_encoded?        :: v[boolean] \\ false,
                                                optional_policy     :: Keyword.t \\ []) :: String.t do
    encoded_url = if url_encoded?, do: resource_url, else: URI.encode(resource_url)
    expires_in_seconds = System.system_time(:second) + lifetime_in_seconds
    joiner = if URI.parse(encoded_url) |> Map.get(:query) |> is_nil(), do: "?", else: "&"
    encoded_url <> joiner <> URI.encode_query(make_query_params_for_custom_policy(encoded_url, expires_in_seconds, key_pair_id, private_key, optional_policy))
  end

  defunpt make_query_params_for_canned_policy(encoded_url        :: v[String.t],
                                              expires_in_seconds :: v[pos_integer],
                                              key_pair_id        :: v[String.t],
                                              private_key        :: v[String.t]) :: [{String.t, String.t}] do
    policy_statement =
      ~s/{"Statement":[{"Resource":"#{encoded_url}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires_in_seconds}}}}]}/
    signature = create_signature(policy_statement, private_key)
    [
      {"Expires",     expires_in_seconds},
      {"Signature",   signature         },
      {"Key-Pair-Id", key_pair_id       },
    ]
  end

  defunpt generate_custom_policy(encoded_url :: v[String.t], expires_in_seconds :: v[pos_integer], optional_policy :: Keyword.t) :: v[String.t] do
    date_greater_than =
      case Keyword.fetch(optional_policy, :date_greater_than) do
        {:ok, t} when is_integer(t) and t >= 0 -> ~s/,"DateGreaterThan":{"AWS:EpochTime":#{t}}/
        _                                      -> ""
      end
    ip_address =
      case Keyword.fetch(optional_policy, :ip_address) do
        {:ok, ip} -> ~s/,"IpAddress":{"AWS:SourceIp":#{ip}}/
        _         -> ""
      end
    ~s/{"Statement":[{"Resource":"#{encoded_url}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires_in_seconds}}#{date_greater_than}#{ip_address}}}]}/
  end

  defunpt make_query_params_for_custom_policy(encoded_url        :: v[String.t],
                                              expires_in_seconds :: v[pos_integer],
                                              key_pair_id        :: v[String.t],
                                              private_key        :: v[String.t],
                                              optional_policy    :: Keyword.t) :: [{String.t, String.t}] do
    policy_statement = generate_custom_policy(encoded_url, expires_in_seconds, optional_policy)
    signature = create_signature(policy_statement, private_key)
    [
      {"Policy",      encode_for_aws(policy_statement)},
      {"Signature",   signature                       },
      {"Key-Pair-Id", key_pair_id                     },
    ]
  end

  defunp encode_for_aws(string :: v[String.t]) :: v[String.t] do
    string
    |> Base.encode64()
    # Replace characters that are invalid in a URL query string with characters that are valid.
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-creating-signed-url-canned-policy.html
    |> String.replace("+", "-")
    |> String.replace("=", "_")
    |> String.replace("/", "~")
  end

  defunp create_signature(policy_statement :: v[String.t], private_key :: v[String.t]) :: String.t do
    :public_key.sign(policy_statement, :sha, decode_rsa_key(private_key))
    |> encode_for_aws()
  end

  defp decode_rsa_key(rsa_key) do
    [pem_entry] = :public_key.pem_decode(rsa_key)
    :public_key.pem_entry_decode(pem_entry)
  end
end
