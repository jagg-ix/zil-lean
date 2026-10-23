/-!
# SHA-256

FIPS 180-4 SHA-256 over bytes, in Lean. Used for transport attestation, hash-chained control events, receipts and
release attestations, so their digests are the ones any other SHA-256 implementation computes.
-/

namespace Zil.Crypto.Sha256

/-- Round constants: the first 32 bits of the fractional parts of the cube roots of the first 64 primes. -/
private def roundConstants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

/-- Initial hash value: the first 32 bits of the fractional parts of the square roots of the first 8 primes. -/
private def initialState : Array UInt32 := #[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

private def rotr (x : UInt32) (n : UInt32) : UInt32 := (x >>> n) ||| (x <<< (32 - n))

private def bigSigma0 (x : UInt32) : UInt32 := rotr x 2 ^^^ rotr x 13 ^^^ rotr x 22
private def bigSigma1 (x : UInt32) : UInt32 := rotr x 6 ^^^ rotr x 11 ^^^ rotr x 25
private def smallSigma0 (x : UInt32) : UInt32 := rotr x 7 ^^^ rotr x 18 ^^^ (x >>> 3)
private def smallSigma1 (x : UInt32) : UInt32 := rotr x 17 ^^^ rotr x 19 ^^^ (x >>> 10)
private def choose (x y z : UInt32) : UInt32 := (x &&& y) ^^^ (~~~x &&& z)
private def majority (x y z : UInt32) : UInt32 := (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

/-- The 32-bit big-endian word starting at byte `offset` of `data`. -/
private def wordAt (data : ByteArray) (offset : Nat) : UInt32 :=
  (data.get! offset).toUInt32 <<< 24 ||| (data.get! (offset + 1)).toUInt32 <<< 16 |||
  (data.get! (offset + 2)).toUInt32 <<< 8 ||| (data.get! (offset + 3)).toUInt32

/-- Process one 64-byte block starting at `offset`. -/
private def processBlock (state : Array UInt32) (data : ByteArray) (offset : Nat) : Array UInt32 := Id.run do
  let mut w : Array UInt32 := Array.mkEmpty 64
  for t in [0:16] do
    w := w.push (wordAt data (offset + 4 * t))
  for t in [16:64] do
    w := w.push (smallSigma1 w[t - 2]! + w[t - 7]! + smallSigma0 w[t - 15]! + w[t - 16]!)
  let mut a := state[0]!
  let mut b := state[1]!
  let mut c := state[2]!
  let mut d := state[3]!
  let mut e := state[4]!
  let mut f := state[5]!
  let mut g := state[6]!
  let mut h := state[7]!
  for t in [0:64] do
    let t1 := h + bigSigma1 e + choose e f g + roundConstants[t]! + w[t]!
    let t2 := bigSigma0 a + majority a b c
    h := g
    g := f
    f := e
    e := d + t1
    d := c
    c := b
    b := a
    a := t1 + t2
  return #[state[0]! + a, state[1]! + b, state[2]! + c, state[3]! + d,
           state[4]! + e, state[5]! + f, state[6]! + g, state[7]! + h]

/-- The message padded to a multiple of 64 bytes: a one bit, zeros, then the bit length as 64 big-endian bits. -/
private def pad (data : ByteArray) : ByteArray := Id.run do
  let bitLength : UInt64 := data.size.toUInt64 * 8
  let mut padded := data.push 0x80
  while padded.size % 64 != 56 do
    padded := padded.push 0
  for i in [0:8] do
    padded := padded.push ((bitLength >>> ((7 - i).toUInt64 * 8)) &&& 0xff).toUInt8
  return padded

/-- The 32-byte SHA-256 digest of `data`. -/
def digest (data : ByteArray) : ByteArray := Id.run do
  let padded := pad data
  let mut state := initialState
  for block in [0:padded.size / 64] do
    state := processBlock state padded (block * 64)
  let mut out := ByteArray.empty
  for word in state do
    out := out.push (word >>> 24).toUInt8
    out := out.push (word >>> 16).toUInt8
    out := out.push (word >>> 8).toUInt8
    out := out.push word.toUInt8
  return out

private def hexDigit (n : UInt8) : Char :=
  if n < 10 then Char.ofNat (48 + n.toNat) else Char.ofNat (87 + n.toNat)

/-- Lowercase hexadecimal text of `bytes`. -/
def toHex (bytes : ByteArray) : String :=
  bytes.foldl (fun acc byte => acc.push (hexDigit (byte >>> 4)) |>.push (hexDigit (byte &&& 0x0f))) ""

/-- Lowercase hex SHA-256 of `data`, 64 characters. -/
def hex (data : ByteArray) : String := toHex (digest data)

/-- `sha256:` followed by the hex digest, the form every ZIL record carries. -/
def prefixed (data : ByteArray) : String := "sha256:" ++ hex data

/-- The prefixed digest of the UTF-8 bytes of `text`. -/
def ofText (text : String) : String := prefixed text.toUTF8

end Zil.Crypto.Sha256
