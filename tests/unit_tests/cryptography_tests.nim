import unittest
import ../../src/cryptography/key_management
import ../../src/cryptography/signature_verification
import ../../src/cryptography/keystore
import ../../src/cryptography/zk_proofs
import std/os

suite "Cryptography Layer Tests":

  test "Key management: demo SHA-256 sign and verify":
    let keyPair = generateKeyPair()
    check keyPair.publicKey.len > 0
    check keyPair.privateKey.len > 0
    check keyPair.publicKey != keyPair.privateKey
    check DemoSignatureScheme == "demo-sha256"
    let signature = signMessage(keyPair.privateKey, "test_message")
    check verifySignature(keyPair.publicKey, "test_message", signature)
    check not verifySignature(keyPair.publicKey, "other_message", signature)
    check not verifySignature(keyPair.publicKey, "test_message", "")
    # The old string-prefix placeholder must not verify.
    check not verifySignature(keyPair.publicKey, "test_message", "signed_test_message")

  test "Signature verification: batch":
    let keys = generateKeyPair()
    let okSig = signMessage(keys.privateKey, "m1")
    let results = batchVerifySignatures(@[
      (keys.publicKey, "m1", okSig),
      (keys.publicKey, "m1", "nope")
    ])
    check results.len == 2
    check results[0] == true
    check results[1] == false

  test "Keystore: roundtrip and refusal to overwrite":
    let dir = getTempDir() / "nimnode-ks-unit"
    if dirExists(dir):
      removeDir(dir)
    let keys = generateKeyPair()
    let address = addressFromPublicKey(keys.publicKey)
    check saveKeystore(dir, address, keys.publicKey, keys.privateKey).ok
    let again = saveKeystore(dir, address, keys.publicKey, keys.privateKey)
    check not again.ok
    check again.error == ksExists
    let loaded = loadKeystore(dir, address)
    check loaded.ok
    check loaded.value.address == address
    check loaded.value.publicKey == keys.publicKey
    check loaded.value.privateKey == keys.privateKey
    let missing = loadKeystore(dir, "missing1")
    check not missing.ok
    check missing.error == ksMissing
    let unsafe = loadKeystore(dir, "../secret")
    check not unsafe.ok
    check unsafe.error == ksUnsafePath
    if dirExists(dir):
      removeDir(dir)

  test "Zero-Knowledge Proofs: proof generation and verification":
    let data = "confidential_data"
    let proof = generateProof(data)
    check proof == "zk_proof_confidential_data"
    check verifyProof(data, proof) == true
    check verifyProof(data, "invalid_proof") == false

    let proofs = @[(data, proof), ("other_data", generateProof("other_data"))]
    let results = batchVerifyProofs(proofs)
    check results.len == 2
    check results[0] == true
    check results[1] == true
