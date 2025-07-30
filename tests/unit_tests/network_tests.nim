import unittest
import ../../src/network/p2p
import ../../src/network/mempool
import ../../src/network/block_propagation

suite "Network Layer Tests":

  test "P2P: peer management":
    let network = newNetwork(10)
    let peerId = network.addPeer("192.168.1.10")
    check network.peerCount() == 1
    check network.connectPeer(peerId) == true
    check network.connectedPeerCount() == 1
    check network.disconnectPeer(peerId) == true
    check network.connectedPeerCount() == 0

  test "Mempool: transaction management":
    let mempool = newMempool(100)
    let tx = Transaction(id: "tx1", fee: 100, timestamp: 0, size: 250)
    check mempool.addTransaction(tx) == true
    check mempool.hasTransaction("tx1") == true
    check mempool.addTransaction(tx) == false  # Duplicate insertion
    check mempool.removeTransaction("tx1") == true
    check mempool.hasTransaction("tx1") == false
    
    # Test fee-based ordering
    let tx2 = Transaction(id: "tx2", fee: 200, timestamp: 0, size: 250)
    let tx3 = Transaction(id: "tx3", fee: 50, timestamp: 0, size: 250)
    discard mempool.addTransaction(tx2)
    discard mempool.addTransaction(tx3)
    let orderedTxs = mempool.getTransactionsByFee(10)
    check orderedTxs[0].fee >= orderedTxs[1].fee

  test "Block Propagation: basic propagation":
    let blk = newBlock("block123", 1, "block_data")
    let status = propagateBlock(blk)
    check status.result == Success
    check status.peersReached > 0
