## Demo key generation and signing.
##
## Verification does not live here. `verifySignature` used to be exported from
## this module and from `signature_verification.nim` with different behavior.
## That duplicate was removed. Call `signature_verification.verifySignature`.
##
## The signer is the SHA-256 teaching placeholder (`demo-sha256`), not Ed25519.
## See `signature_verification.nim` for the formula and its limits.
## This module does not log private keys.

import nimcrypto/[utils, sysrand, sha2]
import ../common/types
import signature_verification

type
  KeyPair* = object
    publicKey*: PublicKey
    privateKey*: PrivateKey

proc publicKeyFromPrivate*(privateKey: PrivateKey): PublicKey =
  ## publicKey = hex(SHA-256(privateKeyBytes)). Not an elliptic-curve key.
  let digest = sha256.digest(fromHex(privateKey))
  toHex(digest.data)

proc generateKeyPair*(): KeyPair =
  ## Random 32-byte seed encoded as hex. The public key is a SHA-256 digest
  ## of those bytes, not an Ed25519 public key.
  var privateKeyBytes: array[32, byte]
  let written = randomBytes(privateKeyBytes)
  if written != privateKeyBytes.len:
    raise newException(IOError, "random source failed")
  let privateKey = toHex(privateKeyBytes)
  KeyPair(
    publicKey: publicKeyFromPrivate(privateKey),
    privateKey: privateKey
  )

proc signMessage*(privateKey: PrivateKey, message: string): Signature =
  ## Demo signature. Not Ed25519. See `DemoSignatureScheme`.
  try:
    let publicKey = publicKeyFromPrivate(privateKey)
    demoSha256Signature(publicKey, message)
  except ValueError:
    raise newException(ValueError, "cannot sign: private key encoding is invalid")

proc signedTransaction*(base: Transaction, keys: KeyPair): Transaction =
  ## Copy of `base` signed by `keys`.
  ## Overwrites sender, publicKey, and signature. Other fields are kept.
  result = base
  result.publicKey = keys.publicKey
  result.sender = addressFromPublicKey(keys.publicKey)
  result.signature = signMessage(keys.privateKey, transactionSigningPayload(result))
