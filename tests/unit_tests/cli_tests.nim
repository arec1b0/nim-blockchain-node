import unittest
import ../../src/cli
import ../../src/core_engine/[consensus, state_management]
import ../../src/storage/blockchain_db
import std/[os, strutils]

suite "CLI Tests":

  setup:
    # Initialize a test blockchain node for each test
    discard initializeBlockchainNode()

  test "Node initialization":
    # Test that the node initializes properly
    check initializeBlockchainNode() == true

  test "Account creation and balance checking":
    # Create an account through CLI functions (would need to refactor CLI to make functions testable)
    let testAddress = "test_addr"
    node.accountState.setBalance(testAddress, 500)
    
    check node.accountState.getBalance(testAddress) == 500
    check node.accountState.getNonce(testAddress) == 0

  test "Transfer functionality":
    # Setup test accounts
    let fromAddr = "alice"
    let toAddr = "bob"
    
    node.accountState.setBalance(fromAddr, 1000)
    node.accountState.setBalance(toAddr, 100)
    
    # Test transfer
    let initialFromBalance = node.accountState.getBalance(fromAddr)
    let initialToBalance = node.accountState.getBalance(toAddr)
    
    # This would require refactoring transferFunds to be testable
    # For now, test the underlying components
    let success = node.accountState.decreaseBalance(fromAddr, 200)
    check success == true
    node.accountState.increaseBalance(toAddr, 200)
    
    check node.accountState.getBalance(fromAddr) == initialFromBalance - 200
    check node.accountState.getBalance(toAddr) == initialToBalance + 200

  test "Block operations":
    # Test blockchain operations
    let success = node.blockchainDB.addBlock(1, "test block data", "hash123", 1000)
    check success == true
    check node.blockchainDB.getCurrentHeight() == 1
    
    let block = node.blockchainDB.getBlock(1)
    check block.isSome
    check block.get.data == "test block data"

  test "Mempool operations":
    # Test mempool functionality
    let tx = Transaction(
      id: "test_tx",
      sender: "alice",
      receiver: "bob", 
      amount: 100,
      fee: 10,
      nonce: 1
    )
    
    check node.mempool.addTransaction(tx) == true
    check node.mempool.hasTransaction("test_tx") == true
    check node.mempool.transactionCount() == 1