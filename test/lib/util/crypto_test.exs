# Copyright(c) 2015-2023 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.CryptoTest do
  use Croma.TestCase

  test "secure_compare/2" do
    assert Crypto.secure_compare("", "")
    assert Crypto.secure_compare("a", "a")
    assert Crypto.secure_compare("ac", "ac")
    refute Crypto.secure_compare("", "a")
    refute Crypto.secure_compare("a", "")
    refute Crypto.secure_compare("a", "b")
    refute Crypto.secure_compare("ac", "bc")
  end
end

defmodule Antikythera.Crypto.AesTest do
  use Croma.TestCase
  use ExUnitProperties

  property "ctr128_encrypt and decrypt with MD5" do
    check all({data, pw} <- {binary(), binary()}) do
      assert Aes.ctr128_encrypt(data, pw) |> Aes.ctr128_decrypt(pw) == {:ok, data}
    end
  end

  property "ctr128_encrypt and decrypt with pbkdf2" do
    check all({data, pw, salt} <- {binary(), binary(), binary()}) do
      kdf = fn pw ->
        :crypto.pbkdf2_hmac(:sha, pw, salt, 100, 16)
      end

      assert Aes.ctr128_encrypt(data, pw, kdf) |> Aes.ctr128_decrypt(pw, kdf) == {:ok, data}
    end
  end

  property "gcm128_encrypt and decrypt with MD5" do
    check all({data, pw} <- {binary(), binary()}) do
      assert Aes.gcm128_encrypt(data, pw) |> Aes.gcm128_decrypt(pw) == {:ok, data}
    end
  end

  property "gcm128_encrypt and decrypt with pbkdf2" do
    check all({data, pw, salt} <- {binary(), binary(), binary()}) do
      kdf = fn pw ->
        :crypto.pbkdf2_hmac(:sha, pw, salt, 100, 16)
      end

      assert Aes.gcm128_encrypt(data, pw, "aad", kdf) |> Aes.gcm128_decrypt(pw, "aad", kdf) ==
               {:ok, data}
    end
  end

  property "gcm128_decrypt should return error for modified data" do
    check all({data, pw} <- {binary(), binary()}) do
      enc = Aes.gcm128_encrypt(data, pw, "aad")
      assert Aes.gcm128_decrypt(enc <> "a", pw, "aad") == {:error, :decryption_failed}
      assert Aes.gcm128_decrypt(enc, pw <> "a", "aad") == {:error, :decryption_failed}
      assert Aes.gcm128_decrypt(enc, pw, "incorrect_aad") == {:error, :decryption_failed}
    end
  end
end
