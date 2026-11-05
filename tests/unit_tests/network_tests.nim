import unittest
import ../../src/common/types
import ../../src/network/p2p
import ../../src/network/mempool
import ../../src/network/block_propagation
import ../../src/cryptography/key_management

proc signedSample(id: string, fee: int, size: int): Transaction =
  let keys = generateKeyPair()
  signedTransaction(
    Transaction(id: id, receiver: "r", amount: 1, fee: fee.Balance, nonce: 1, size: size),
    keys
  )

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
    let tx = signedSample("tx1", 100, 250)
    check mempool.addTransaction(tx).ok
    check mempool.hasTransaction("tx1") == true
    let duplicate = mempool.addTransaction(tx)
    check not duplicate.ok
    check duplicate.error == maDuplicate
    check mempool.removeTransaction("tx1") == true
    check mempool.hasTransaction("tx1") == false

    let tx2 = signedSample("tx2", 200, 250)
    let tx3 = signedSample("tx3", 50, 250)
    check mempool.addTransaction(tx2).ok
    check mempool.addTransaction(tx3).ok
    let orderedTxs = mempool.getTransactionsByFee(10)
    check orderedTxs[0].fee >= orderedTxs[1].fee

  test "Mempool: rejects unsigned and invalid signatures":
    let mempool = newMempool(100)
    let keys = generateKeyPair()
    var unsigned = signedTransaction(Transaction(
      id: "unsigned", receiver: "bob", amount: 5, fee: 1, nonce: 1), keys)
    unsigned.signature = ""
    let missing = mempool.addTransaction(unsigned)
    check not missing.ok
    check missing.error == maMissingSignature
    check mempool.transactionCount() == 0

    var invalid = signedSample("bad", 1, 10)
    invalid.signature = "00"
    let rejected = mempool.addTransaction(invalid)
    check not rejected.ok
    check rejected.error == maInvalidSignature
    check not mempool.hasTransaction("bad")

  test "Block Propagation: basic propagation":
    let blk = newBlock("block123", 1, "block_data")
    let status = propagateBlock(blk)
    check status.result == Success
    check status.peersReached > 0
