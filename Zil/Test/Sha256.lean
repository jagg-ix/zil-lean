import Zil.Crypto.Sha256

open Zil.Crypto

/-! # SHA-256 test vectors (FIPS 180-4 and NIST examples) -/

#guard Sha256.hex "".toUTF8 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
#guard Sha256.hex "abc".toUTF8 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
#guard Sha256.hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".toUTF8 ==
  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
#guard Sha256.hex "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu".toUTF8 ==
  "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
-- padding boundaries: 55, 56, 63, 64 and 65 bytes
#guard Sha256.hex (ByteArray.mk (Array.replicate 55 0x61)) == "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"
#guard Sha256.hex (ByteArray.mk (Array.replicate 56 0x61)) == "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"
#guard Sha256.hex (ByteArray.mk (Array.replicate 63 0x61)) == "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"
#guard Sha256.hex (ByteArray.mk (Array.replicate 64 0x61)) == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
#guard Sha256.hex (ByteArray.mk (Array.replicate 65 0x61)) == "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"
-- multibyte UTF-8
#guard Sha256.ofText "é" == "sha256:" ++ Sha256.hex (ByteArray.mk #[0xc3, 0xa9])
#guard (Sha256.digest "abc".toUTF8).size == 32
#guard Sha256.ofText "" == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
