import unittest
import ../../src/core_engine/consensus
import ../../src/core_engine/state_management
import ../../src/core_engine/vm
import ../../src/storage/blockchain_db
import ../../src/storage/state_db
import ../../src/storage/index_db
import ../../src/network/mempool
import ../../src/network/block_propagation
import std/options

suite "Blockchain Node Integration Tests":

  test "End-to-end block creation and propagation":
    # Initialize Core Components
    var consensus = newConsensus()
    discard consensus.addValidator(1, 1000)
    discard consensus.addValidator(2, 1500)

    # Initialize Storage and Network Components
    let globalStateDB = newStateDB()
    let accountStateDB = newStateDB()
    let blockchainDB = newBlockchainDB()
    let indexDB = newIndexDB()
    let mempool = newMempool()

    # Initialize account states
    accountStateDB.setBalance("Alice", 1000)
    accountStateDB.setBalance("Bob", 500)

    # Initialize VM
    var vm = newVM(accountStateDB, 100000)

    # Simulate adding transaction to mempool
    let tx = Transaction(id: "tx999", sender: "Alice", receiver: "Bob", 
                        amount: 100, fee: 10, nonce: 1)
    check mempool.addTransaction(tx) == true

    # Execute transaction in VM
    check vm.applyTransaction(tx) == true

    # Create and propagate block
    let blk = newBlock("blk999", 1, "tx999 included")
    let status = propagateBlock(blk)
    check status.result == Success

    # Save block to BlockchainDB
    check blockchainDB.addBlock(1, blk.data, blk.id, blk.timestamp) == true
    
    let storedBlock = blockchainDB.getBlock(1)
    check storedBlock.isSome
    check storedBlock.get.data == "tx999 included"

    # Index the transaction
    check indexDB.indexTransaction("tx999", 1, 0) == true

    # Update global state
    check globalStateDB.setState("accountA", 500)
    check globalStateDB.getState("accountA") == 500

    # Verify final states
    check accountStateDB.getBalance("Alice") == 890  # 1000 - 100 - 10
    check accountStateDB.getBalance("Bob") == 600    # 500 + 100
    check blockchainDB.getCurrentHeight() == 1
    check consensus.activeValidatorCount() == 2
