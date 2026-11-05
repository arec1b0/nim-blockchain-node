## Single signature-verification API for the VM and the mempool.
##
## Teaching placeholder. This is NOT Ed25519, NOT secp256k1, and NOT
## unforgeable. Do not describe it as production cryptography.
##
## Scheme name: `demo-sha256`
##   publicKey = hex(SHA-256(privateKeyBytes))
##   signature = hex(SHA-256(publicKeyBytes || messageBytes))
##
## The older signer hashed SHA-256(privateKeyBytes || message). A verifier
## that only has the public key cannot recompute that digest, so sign and
## verify did not form one check. This module is now the only check.
## Anyone who knows the public key can forge a demo signature. The check
## rejects missing and non-matching signatures only.
##
## ZK proofs are a separate placeholder and are not handled here.

import nimcrypto/[utils, sha2]
import ../common/[types, result]

const DemoSignatureScheme* = "demo-sha256"

type
  AuthError* = enum
    authNone
    authMissingPublicKey
    authMissingSignature
    authSenderKeyMismatch
    authInvalidSignature

proc messageBytes(message: string): seq[byte] =
  result = newSeq[byte](message.len)
  for i, ch in message:
    result[i] = byte(ord(ch))

proc demoSha256Signature*(publicKey: PublicKey, message: string): string =
  ## Demo signature for a known public key. Forgeable. Not Ed25519.
  let digest = sha256.digest(fromHex(publicKey) & messageBytes(message))
  toHex(digest.data)

proc verifySignature*(publicKey: PublicKey, message: string, signature: Signature): bool =
  ## Returns true only when `signature` matches `demoSha256Signature`.
  ## Empty inputs and non-hex public keys are rejected.
  ## Does not log key material or the signature.
  if publicKey.len == 0 or signature.len == 0:
    return false
  try:
    demoSha256Signature(publicKey, message) == signature
  except ValueError:
    false

proc addressFromPublicKey*(publicKey: PublicKey): Address =
  ## Educational account id: the first 8 hex characters of the public key.
  ## This is a truncation, not a hash designed for collision resistance.
  if publicKey.len == 0:
    return ""
  if publicKey.len <= 8:
    return publicKey
  publicKey[0 .. 7]

proc transactionSigningPayload*(tx: Transaction): string =
  ## Fields covered by the demo signature.
  ## Excludes `signature`, `publicKey`, `timestamp`, and `size`.
  ## Pipe-separated teaching encoding, not a production transaction hash.
  tx.id & "|" & tx.sender & "|" & tx.receiver & "|" & $tx.amount & "|" & $tx.fee & "|" & $tx.nonce

proc authorizeTransaction*(tx: Transaction): Status[AuthError] =
  ## Shared admission check used by the VM and the mempool.
  if tx.publicKey.len == 0:
    return errStatus(authMissingPublicKey)
  if tx.signature.len == 0:
    return errStatus(authMissingSignature)
  if tx.sender != addressFromPublicKey(tx.publicKey):
    return errStatus(authSenderKeyMismatch)
  if not verifySignature(tx.publicKey, transactionSigningPayload(tx), tx.signature):
    return errStatus(authInvalidSignature)
  okStatus(AuthError)

proc batchVerifySignatures*(verifications: seq[(PublicKey, string, Signature)]): seq[bool] =
  ## Verifies each triple with `verifySignature`.
  result = newSeq[bool](verifications.len)
  for i, item in verifications:
    let (pubKey, message, signature) = item
    result[i] = verifySignature(pubKey, message, signature)
