import unittest
import ../../src/common/types
import ../../src/common/result
import ../../src/network/p2p
import ../../src/network/mempool
import ../../src/network/block_propagation
import ../../src/cryptography/key_management
import ../../src/cryptography/signature_verification

proc signedSample(id: string, fee: int, size: int): Transaction =
  let keys = generateKeyPair()
  signedTransaction(
    Transaction(id: id, receiver: "r", amount: 1, fee: fee.Balance, nonce: 1, size: size),
    keys
  )

suite "Network Layer Tests":

  test "P2P: peer management and maxPeers enforcement":
    let network = newNetwork(2)
    let p1 = network.addPeer("192.168.1.10")
    check p1.ok
    check network.peerCount() == 1
    check network.connectPeer(p1.value) == true
    check network.connectedPeerCount() == 1

    let p2 = network.addPeer("192.168.1.11")
    check p2.ok
    check network.peerCount() == 2

    # Reaching maxPeers rejects new peers with clear error without replacement
    let p3 = network.addPeer("192.168.1.12")
    check not p3.ok
    check p3.error == peerAddMaxPeersReached
    check network.peerCount() == 2

    check network.disconnectPeer(p1.value) == true
    check network.connectedPeerCount() == 0

    check network.removePeer(p2.value) == true
    check network.peerCount() == 1

    # Now that a slot is free, adding succeeds again
    let p4 = network.addPeer("192.168.1.13")
    check p4.ok
    check network.peerCount() == 2

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

  test "Mempool: rejects wrong-key and sender/publicKey mismatch":
    let mempool = newMempool(100)
    let owner = generateKeyPair()
    let other = generateKeyPair()
    var wrongKey = Transaction(
      id: "wrong-key",
      sender: addressFromPublicKey(owner.publicKey),
      receiver: "bob",
      amount: 5,
      fee: 1,
      nonce: 1,
      publicKey: owner.publicKey
    )
    wrongKey.signature = signMessage(other.privateKey, transactionSigningPayload(wrongKey))
    let badSig = mempool.addTransaction(wrongKey)
    check not badSig.ok
    check badSig.error == maInvalidSignature

    var mismatch = signedTransaction(Transaction(
      id: "mismatch", receiver: "bob", amount: 5, fee: 1, nonce: 1), owner)
    mismatch.sender = "otheracct"
    let badSender = mempool.addTransaction(mismatch)
    check not badSender.ok
    check badSender.error == maSenderKeyMismatch
    check mempool.transactionCount() == 0

  test "Block Propagation: uses injected network and reflects connected peers":
    let network = newNetwork(10)
    let blk = newBlock("block123", 1, "block_data")

    # With 0 connected peers, propagation succeeds with 0 peers reached
    let statusEmpty = propagateBlock(network, blk)
    check statusEmpty.result == Success
    check statusEmpty.peersReached == 0
    check statusEmpty.propagationTime == 0

    # Add 3 peers, connect 2 of them
    let p1 = network.addPeer("10.0.0.1").value
    let p2 = network.addPeer("10.0.0.2").value
    discard network.addPeer("10.0.0.3")
    check network.connectPeer(p1)
    check network.connectPeer(p2)
    check network.connectedPeerCount() == 2

    # Propagate through the injected network
    let status = propagateBlock(network, blk)
    check status.result == Success
    check status.peersReached == 2
    check status.propagationTime == 40 # 20 base + 2 * 10

  test "Block Propagation: simulated propagation is deterministic":
    let network = newSimulatedNetwork(5)
    let blk = newBlock("block_det", 2, "deterministic_test")
    let p1 = network.addPeer("192.168.1.1").value
    check network.connectPeer(p1)

    let s1 = propagateBlock(network, blk)
    let s2 = propagateBlock(network, blk)
    check s1.result == s2.result
    check s1.peersReached == s2.peersReached
    check s1.propagationTime == s2.propagationTime
    check s1.peersReached == 1
    check s1.propagationTime == 30 # 20 base + 1 * 10

  test "Block Propagation: validates block and network boundaries":
    let network = newNetwork(5)
    let validBlk = newBlock("blk1", 1, "data")
    let nilStatus = propagateBlock(nil, validBlk)
    check nilStatus.result == NetworkError
    check nilStatus.peersReached == 0

    let invalidBlk = Block(id: "", height: 0, data: "")
    check propagateBlock(network, invalidBlk).result == Failed

    # Broadcast to connected peers and retry logic
    let p1 = network.addPeer("10.0.0.1").value
    check network.connectPeer(p1)
    let broadcasts = broadcastToAllPeers(network, validBlk)
    check broadcasts.len == 1
    check broadcasts[0].result == Success

    let retryStatus = propagateBlockWithRetry(network, validBlk)
    check retryStatus.result == Success
    check retryStatus.peersReached == 1
