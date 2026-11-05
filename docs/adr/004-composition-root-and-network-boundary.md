# ADR 004: Shared Composition Root and Network Boundary

## Status

Accepted and Implemented

## Context

Prior to this work:
1. `main.nim` and `cli.nim` each wired `BlockchainNode` components separately.
2. Runtime defaults diverged across entry points:
   - Gas limit: `100,000` (`main.nim`) vs `1,000,000` (`cli.nim`)
   - Validators: 2 validators (`main.nim`) vs 1 validator (`cli.nim`)
   - Mempool capacity: `5,000` (`main.nim`) vs `10,000` (`cli.nim`)
   - Max peers: `50` (`main.nim`) vs `100` (`cli.nim`)
3. Block propagation in `block_propagation.nim` hardcoded `peersReached: 5` and did not accept a `Network` dependency.
4. Peer registration in `p2p.nim` stored `maxPeers` but never enforced it upon calling `addPeer`.

## Decision

### 1. Shared Node Composition Root (`src/node.nim`)
- Created `src/node.nim` defining `BlockchainNode` as a reference object (`ref object`) containing all node subsystems:
  - `config`: `NodeConfig`
  - `consensus`: `Consensus`
  - `accountState`: `StateDB`
  - `globalState`: `GlobalStateStore`
  - `blockchainDB`: `BlockchainDB`
  - `indexDB`: `IndexDB`
  - `mempool`: `Mempool`
  - `network`: `Network`
  - `vm`: `VM`
  - `accounts`: `AccountStore`
- Defined `newBlockchainNode(cfg: NodeConfig): Result[BlockchainNode, NodeInitError]` as the single construction factory used by both `main.nim` and `cli.nim`.
- Centralized node lifecycle helpers `close(node: BlockchainNode)` and `persistAccountState(node: BlockchainNode)`.

### 2. Centralized Configuration Defaults (`src/common/config.nim`)
- Extended `NodeConfig` to include:
  - `gasLimit`: Natural (`1,000,000`)
  - `mempoolCapacity`: int (`5,000`)
  - `maxPeers`: int (`50`)
  - `validators`: `seq[ValidatorConfig]` (defaulting to 2 active validators: id 1 with stake 1000, id 2 with stake 1500)
  - `storageBackend`: `StorageBackend` enum (`backendFile`, `backendMemory`)
- Kept configuration resolution deterministic: CLI flags take precedence over environment variables, which take precedence over defaults.

### 3. Network Boundary and Peer Limit Enforcement (`src/network/p2p.nim`)
- `addPeer(network: Network, address: PeerAddress): Result[PeerId, PeerAddError]` now enforces `network.peers.len >= network.maxPeers`.
- When full, `addPeer` returns `errResult(PeerId, peerAddMaxPeersReached)` and rejects the peer without replacing existing peers.
- Defined `SimulatedNetwork` as an alias for `Network` and provided `newSimulatedNetwork`.

### 4. Dependency Injection in Block Propagation (`src/network/block_propagation.nim`)
- `propagateBlock(network: Network, blk: Block): PropagationStatus` accepts the injected network dependency.
- Removed hardcoded `peersReached: 5`. `peersReached` now dynamically reports `network.connectedPeerCount()`.
- Simulated propagation latency is deterministic based on connected peers reached (`20 + reached * 10` ms).
- Defined `Broadcaster* = Network`.
- Added validation for network (`NetworkError` if nil) and block validity (`Failed` if invalid).

## Consequences

- Both `main.nim` and `cli.nim` now produce identical runtime configurations given identical inputs.
- Unexplained divergent defaults between `main` and CLI are eliminated.
- Network simulation accurately reflects connected peer count and enforces capacity limits.
- Existing CLI commands, JSON output shapes, and tests are preserved without regression.
