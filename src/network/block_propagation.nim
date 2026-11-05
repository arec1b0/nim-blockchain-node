## Block propagation and network distribution for blockchain consensus.
## Handles block broadcasting across the peer-to-peer network.

import std/[logging]
import ../common/types
import p2p

export types.Block, types.BlockId, types.BlockData, types.BlockHeight, types.BlockHash, types.newBlock

type
  PropagationResult* = enum
    Success, Failed, Timeout, NetworkError

  PropagationStatus* = object
    result*: PropagationResult
    peersReached*: int
    propagationTime*: int64  # milliseconds

  Broadcaster* = Network

proc validateBlockForPropagation*(blk: Block): bool =
  ## Validates a block before propagation.
  blk.id.len > 0 and blk.data.len > 0

proc propagateBlock*(network: Network, blk: Block): PropagationStatus =
  ## Propagates a block across the injected peer-to-peer network.
  ## Reaches all currently connected peers with deterministic simulated latency.
  if network.isNil:
    return PropagationStatus(result: NetworkError, peersReached: 0, propagationTime: 0)
  if not validateBlockForPropagation(blk):
    return PropagationStatus(result: Failed, peersReached: 0, propagationTime: 0)

  debug("propagating block id=" & blk.id & " height=" & $blk.height)
  let reached = network.connectedPeerCount()
  let timeMs = if reached > 0: int64(20 + reached * 10) else: 0.int64
  PropagationStatus(
    result: Success,
    peersReached: reached,
    propagationTime: timeMs
  )

proc propagateBlock*(blk: Block): PropagationStatus {.deprecated: "use propagateBlock(network, blk)".} =
  ## Deprecated fallback creating an empty simulated network.
  let fallbackNet = newNetwork()
  propagateBlock(fallbackNet, blk)

proc broadcastToAllPeers*(network: Network, blk: Block): seq[PropagationStatus] =
  ## Broadcasts block to all currently connected peers in the injected network.
  result = @[]
  if network.isNil or not validateBlockForPropagation(blk):
    return result
  for peer in network.getConnectedPeers():
    result.add(PropagationStatus(result: Success, peersReached: 1, propagationTime: 30))

proc propagateBlockWithRetry*(network: Network, blk: Block, maxRetries: int = 3): PropagationStatus =
  ## Propagates block with retry logic for failed attempts.
  for attempt in 1..maxRetries:
    let status = propagateBlock(network, blk)
    if status.result == Success:
      return status
    debug("propagation attempt " & $attempt & " failed, retrying")
  PropagationStatus(result: Failed, peersReached: 0, propagationTime: 0)

when isMainModule:
  addHandler(newConsoleLogger(useStderr = true))
  let testNet = newNetwork()
  let testBlock = newBlock("test_block_123", 1, "Sample block data")
  let status = propagateBlock(testNet, testBlock)
  info("propagation result " & $status.result)
