# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Crypto do
  @doc """
  Checks equality of the given two binaries in constant-time to avoid [timing attacks](http://codahale.com/a-lesson-in-timing-attacks/).
  """
  defun secure_compare(left :: v[binary], right :: v[binary]) :: boolean do
    if byte_size(left) == byte_size(right) do
      secure_compare_impl(left, right, 0) == 0
    else
      false
    end
  end

  defp secure_compare_impl(<<x, left::binary>>, <<y, right::binary>>, acc) do
    use Bitwise, skip_operators: true
    secure_compare_impl(left, right, bor(acc, bxor(x, y)))
  end

  defp secure_compare_impl(<<>>, <<>>, acc) do
    acc
  end

  defmodule Aes do
    @moduledoc """
    Easy to use data encryption/decryption utilities.

    Both Counter (CTR) mode and Galois/Counter mode (GCM) are supported.
    When only secrecy of data is required, use CTR mode.
    If you need not only secrecy but also data integrity, use GCM.

    ## Deriving an AES key from given password

    The functions defined in this module accept arbitrary binary as password.
    To make an AES key (which is 128bit length) from a given password, the functions by default use MD5 hash algorithm.
    If you need to increase computational cost of key derivation and make attacks such as dictionary attacks more difficult,
    you may pass your own key derivation function.
    To implement your key derivation function you can use `:pbkdf2` library.

    ## Transparent handling of initialization vector

    When encrypting given data, the encrypt function generates a random initialization vector and prepends it to the encrypted data.
    The decrypt function extracts the initialization vector and use it to decrypt the rest.

    ## Associated Authenticated Data (AAD) for GCM

    For GCM you may pass AAD (arbitrary binary) as an additional argument.
    AAD is used only for generating/validating authentication tag; it doesn't affect resulting cipher text.

    AAD can be used to provide contextual information for the authentication of cipher text.
    For example, you could pass "login user ID" as AAD when encrypting/decrypting each user's data,
    This way, even when a malicious user who somehow copied another user's encrypted data and secret key into his own account,
    you could prevent him from decrypting the data because of the difference in AAD.

    If you don't have any suitable data for AAD you can pass an empty string (which is the default value).
    """

    alias Croma.Result, as: R

    @iv_len 16
    @auth_tag_len 16

    @type key128 :: <<_::_*128>>

    defun ctr128_encrypt(
            plain :: v[binary],
            password :: v[binary],
            key_derivation_fun :: (binary -> key128) \\ &md5/1
          ) :: binary do
      iv = :crypto.strong_rand_bytes(@iv_len)
      key = key_derivation_fun.(password)
      {_, encrypted} = :crypto.stream_init(:aes_ctr, key, iv) |> :crypto.stream_encrypt(plain)
      iv <> encrypted
    end

    defun ctr128_decrypt(
            encrypted :: v[binary],
            password :: v[binary],
            key_derivation_fun :: (binary -> key128) \\ &md5/1
          ) :: R.t(binary) do
      split_16(encrypted)
      |> R.map(fn {iv, enc} ->
        key = key_derivation_fun.(password)
        {_, plain} = :crypto.stream_init(:aes_ctr, key, iv) |> :crypto.stream_decrypt(enc)
        plain
      end)
    end

    defun gcm128_encrypt(
            plain :: v[binary],
            password :: v[binary],
            aad :: v[binary] \\ "",
            key_derivation_fun :: (binary -> key128) \\ &md5/1
          ) :: binary do
      iv = :crypto.strong_rand_bytes(@iv_len)
      key = key_derivation_fun.(password)

      {encrypted, auth_tag} =
        :crypto.block_encrypt(:aes_gcm, key, iv, {aad, plain, @auth_tag_len})

      iv <> auth_tag <> encrypted
    end

    defun gcm128_decrypt(
            encrypted :: v[binary],
            password :: v[binary],
            aad :: v[binary] \\ "",
            key_derivation_fun :: (binary -> key128) \\ &md5/1
          ) :: R.t(binary) do
      R.m do
        {iv, enc1} <- split_16(encrypted)
        {tag, enc2} <- split_16(enc1)
        key = key_derivation_fun.(password)

        case :crypto.block_decrypt(:aes_gcm, key, iv, {aad, enc2, tag}) do
          :error -> {:error, :decryption_failed}
          plain -> {:ok, plain}
        end
      end
    end

    defunp md5(password :: v[binary]) :: key128 do
      :crypto.hash(:md5, password)
    end

    defp split_16(<<iv::binary-size(16), rest::binary>>), do: {:ok, {iv, rest}}
    defp split_16(_), do: {:error, :invalid_input}
  end
end
