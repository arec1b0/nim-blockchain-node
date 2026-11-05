import unittest
import ../../src/common/types
import ../../src/core_engine/consensus
import ../../src/core_engine/state_management
import ../../src/core_engine/vm
import ../../src/cryptography/key_management
import ../../src/cryptography/signature_verification

suite "Core Engine Tests":

  test "Consensus - Validator Management":
    var cons = newConsensus()
    check cons.addValidator(1, 100)
    check cons.addValidator(2, 200)
    check cons.hasValidator(1)
    check cons.hasValidator(2)
    check cons.deactivateValidator(1)
    check not cons.isValidatorActive(1)
    check cons.removeValidator(2)
    check not cons.hasValidator(2)
    # Only inactive validator 1 remains; quorum requires at least one active validator.
    check cons.calculateQuorum() == 0

  test "State Management - Account Operations":
    var state = newStateDB()
    state.ensureAccount("0xA")
    check state.hasAccount("0xA")
    state.setBalance("0xA", 500)
    check state.getBalance("0xA") == 500
    check state.decreaseBalance("0xA", 200)
    check state.getBalance("0xA") == 300
    state.increaseBalance("0xA", 100)
    check state.getBalance("0xA") == 400
    discard state.incrementNonce("0xA")
    check state.getNonce("0xA") == 1
    check state.totalSupply() == 400

  test "VM - Transaction Execution":
    var state = newStateDB()
    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    state.setBalance(sender, 1000)
    state.setBalance("Bob", 500)
    var vm = newVM(state, 100000)
    let tx1 = signedTransaction(
      Transaction(id: "tx1", receiver: "Bob", amount: 100, fee: 10, nonce: 1), keys)
    let tx2 = signedTransaction(
      Transaction(id: "tx2", receiver: "Bob", amount: 900, fee: 10, nonce: 2), keys)
    check vm.applyTransaction(tx1).ok
    # StateDB is a value type: execution mutates vm.state, not the caller's copy.
    check vm.state.getBalance(sender) == 890
    check vm.state.getBalance("Bob") == 600
    let rejected = vm.applyTransaction(tx2)
    check not rejected.ok
    check rejected.error == txInsufficientBalance
    check vm.state.getBalance(sender) == 890
    check vm.gasUsed == 21000

  test "VM - rejects unsigned and invalid signatures":
    var state = newStateDB()
    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    state.setBalance(sender, 1000)
    var vm = newVM(state, 100000)

    var unsigned = Transaction(
      id: "unsigned",
      sender: sender,
      receiver: "Bob",
      amount: 10,
      fee: 1,
      nonce: 1,
      publicKey: keys.publicKey
    )
    let missing = vm.validateTransaction(unsigned)
    check not missing.ok
    check missing.error == txMissingSignature
    check not vm.applyTransaction(unsigned).ok
    check vm.state.getBalance(sender) == 1000
    check vm.gasUsed == 0

    var invalid = unsigned
    invalid.signature = "00"
    let bad = vm.validateTransaction(invalid)
    check not bad.ok
    check bad.error == txInvalidSignature
    check not vm.applyTransaction(invalid).ok
    check vm.state.getBalance(sender) == 1000

    var mismatched = signedTransaction(unsigned, keys)
    mismatched.sender = "otheracct"
    let mismatch = vm.validateTransaction(mismatched)
    check not mismatch.ok
    check mismatch.error == txSenderKeyMismatch

    var tampered = signedTransaction(unsigned, keys)
    tampered.amount = 11
    check vm.validateTransaction(tampered).error == txInvalidSignature
    check vm.state.getBalance(sender) == 1000

    let good = signedTransaction(unsigned, keys)
    check vm.validateTransaction(good).ok
    check vm.applyTransaction(good).ok
    check vm.state.getBalance(sender) == 989
    check vm.gasUsed == 21000
