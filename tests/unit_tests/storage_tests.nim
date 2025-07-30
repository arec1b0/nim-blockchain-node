import unittest
import ../../src/storage/blockchain_db
import ../../src/storage/state_db
import ../../src/storage/index_db
import std/options

suite "Storage Layer Tests":

  test "BlockchainDB: block storage and retrieval":
    let chainDB = newBlockchainDB()
    check chainDB.addBlock(1, "BlockData1", "hash1", 1000) == true
    check chainDB.addBlock(1, "BlockDataDuplicate", "hash2", 2000) == false  # duplicates prevented
    
    let block = chainDB.getBlock(1)
    check block.isSome
    check block.get.data == "BlockData1"
    
    let nonExistent = chainDB.getBlock(2)
    check nonExistent.isNone

  test "StateDB: state update and retrieval":
    let stateDB = newStateDB()
    check stateDB.setState("account1", 100)
    check stateDB.getState("account1") == 100
    check stateDB.getState("unknown") == 0  # default value when not found
    check stateDB.hasState("account1") == true
    check stateDB.deleteState("account1") == true
    check stateDB.hasState("account1") == false

  test "IndexDB: indexing transactions":
    let indexDB = newIndexDB()
    check indexDB.indexTransaction("tx123", 10, 0) == true
    
    let location = indexDB.getTransactionLocation("tx123")
    check location.isSome
    check location.get.blockHeight == 10
    
    let nonExistent = indexDB.getTransactionLocation("tx999")
    check nonExistent.isNone
    
    # Test block transaction listing
    discard indexDB.indexTransaction("tx124", 10, 1)
    let blockTxs = indexDB.getBlockTransactions(10)
    check blockTxs.len == 2
