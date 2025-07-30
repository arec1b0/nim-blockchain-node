import unittest
import ../../src/cryptography/key_management
import ../../src/cryptography/signature_verification
import ../../src/cryptography/zk_proofs

suite "Cryptography Layer Tests":

  test "Key Management: generate and sign":
    let keyPair = generateKeyPair()
    check keyPair.publicKey.len > 0
    check keyPair.privateKey.len > 0
    let signature = signMessage(keyPair.privateKey, "test_message")
    check signature.len > 0
    check verifySignature(keyPair.publicKey, "test_message", signature)

  test "Signature Verification: basic validation":
    let message = "secure_message"
    let signature = "signed_secure_message"
    check verifySignature("pub_dummy", message, signature) == true
    check verifySignature("pub_dummy", message, "invalid_signature") == false

  test "Zero-Knowledge Proofs: proof generation and verification":
    let data = "confidential_data"
    let proof = generateProof(data)
    check proof == "zk_proof_confidential_data"
    check verifyProof(data, proof) == true
    check verifyProof(data, "invalid_proof") == false
    
    # Test batch verification
    let proofs = @[(data, proof), ("other_data", generateProof("other_data"))]
    let results = batchVerifyProofs(proofs)
    check results.len == 2
    check results[0] == true
    check results[1] == true
