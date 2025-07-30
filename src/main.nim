## Main entry point for the Nim blockchain node.
## Initializes and coordinates all blockchain components.

import core_engine/[consensus, state_management, vm]
import storage/[blockchain_db, state_db, index_db]
import network/[mempool, block_propagation, p2p]
import std/times

proc initializeNode(): bool =
  ## Initializes all blockchain node components.
  echo "🚀 Starting Nim Blockchain Node..."
  
  # Initialize consensus engine
  var consensus = newConsensus()
  discard consensus.addValidator(1, 1000)
  discard consensus.addValidator(2, 1500)
  echo "✅ Consensus engine initialized with ", consensus.activeValidatorCount(), " validators"
  
  # Initialize storage components
  let blockchainDB = newBlockchainDB()
  let stateDB = newStateDB()
  let indexDB = newIndexDB()
  echo "✅ Storage systems initialized"
  
  # Initialize state management  
  var stateManager = newStateDB()
  stateManager.setBalance("genesis", 1000000)
  echo "✅ State management initialized with genesis balance"
  
  # Initialize virtual machine
  let vm = newVM(stateManager, 100000)
  echo "✅ Virtual machine initialized with gas limit: ", vm.gasLimit
  
  # Initialize network components
  let mempool = newMempool(5000)
  let network = newNetwork(50)
  echo "✅ Network systems initialized"
  
  # Add some sample transactions
  let tx1 = Transaction(
    id: "tx_001", 
    sender: "genesis",
    receiver: "user1", 
    amount: 100,
    fee: 10,
    nonce: 1
  )
  
  if mempool.addTransaction(tx1):
    echo "✅ Sample transaction added to mempool: ", tx1.id
  
  # Create and store a genesis block
  let genesisBlock = newBlock("genesis_block", 0, "Genesis block data")
  let status = propagateBlock(genesisBlock)
  
  if status.result == Success:
    if blockchainDB.addBlock(0, genesisBlock.data, genesisBlock.id, genesisBlock.timestamp):
      echo "✅ Genesis block stored at height 0"
      
      # Index the genesis block
      discard indexDB.indexTransaction("genesis_tx", 0, 0)
      echo "✅ Genesis transaction indexed"
    else:
      echo "⚠️ Failed to store genesis block"
      return false
  else:
    echo "⚠️ Genesis block propagation failed"
    return false
  
  echo "🎉 Blockchain node initialized successfully!"
  echo "📊 Node Status:"
  echo "   - Blockchain height: ", blockchainDB.getCurrentHeight()
  echo "   - Active validators: ", consensus.activeValidatorCount()
  echo "   - Mempool transactions: ", mempool.transactionCount()
  echo "   - Network peers: ", network.peerCount()
  
  true

proc main() =
  ## Main entry point for the blockchain node.
  if not initializeNode():
    echo "❌ Failed to initialize blockchain node"
    quit(1)
  
  echo "✅ Blockchain node is operational"

when isMainModule:
  main()
