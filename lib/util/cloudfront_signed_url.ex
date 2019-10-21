# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.CloudfrontSignedUrl do
  @moduledoc """
  This module provides `get_signed_url/4` to generate [a signed URL for CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-signed-urls.html)
  Note that currently we support only a signed URL using a *canned policy*.
  """

  @doc """
  Generates a signed URL to access a file via CloudFront.

  ## Parameters

  - `resource_url` (string): CloudFront URL used for accessing the file, including query string parameters, if any.
  - `lifetime_in_seconds` (positive integer): Expiration time is determined as the sum of the current time (in seconds) and this value.
  - `key_pair_id` (string): ID for an active CloudFront key pair used for generating the signature.
  - `private_key` (string): RSA private key for the key pair specified by `key_pair_id`.

  ## Return value

  A generated signed URL (string).
  """
  defun get_signed_url(resource_url        :: v[String.t],
                       lifetime_in_seconds :: v[pos_integer],
                       key_pair_id         :: v[String.t],
                       private_key         :: v[String.t]) :: String.t do
    expires_in_seconds = System.system_time(:second) + lifetime_in_seconds
    resource_url
    |> URI.parse()
    |> Map.update!(:query, fn query ->
      case query do
        nil   -> ""
        query -> query <> "&"
      end
      <> URI.encode_query(make_query_params(resource_url, expires_in_seconds, key_pair_id, private_key))
    end)
    |> URI.to_string()
  end

  defunp make_query_params(resource_url       :: v[String.t],
                           expires_in_seconds :: v[pos_integer],
                           key_pair_id        :: v[String.t],
                           private_key        :: v[String.t]) :: [{String.t, String.t}] do
    policy_statement =
      ~s|{\"Statement\":[{\"Resource\":\"#{resource_url}\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":#{expires_in_seconds}}}}]}|
    signature = create_signature(policy_statement, private_key)
    [
      {"Expires",     expires_in_seconds},
      {"Signature",   signature         },
      {"Key-Pair-Id", key_pair_id       },
    ]
  end

  defunp create_signature(policy_statement :: v[String.t], private_key :: v[String.t]) :: String.t do
    :public_key.sign(policy_statement, :sha, decode_rsa_key(private_key))
    |> Base.encode64()
    # Replace characters that are invalid in a URL query string with characters that are valid.
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-creating-signed-url-canned-policy.html
    |> String.replace("+", "-")
    |> String.replace("=", "_")
    |> String.replace("/", "~")
  end

  defp decode_rsa_key(rsa_key) do
    [pem_entry] = :public_key.pem_decode(rsa_key)
    :public_key.pem_entry_decode(pem_entry)
  end
end
