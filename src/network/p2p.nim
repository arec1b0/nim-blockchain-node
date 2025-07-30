## Peer-to-peer networking module for blockchain node communication.
## Manages network connections and peer discovery.

import std/tables

type
  PeerAddress* = string
  PeerId* = string
  
  ConnectionStatus* = enum
    Disconnected, Connecting, Connected, Failed
    
  Peer* = object
    id*: PeerId
    address*: PeerAddress
    status*: ConnectionStatus
    lastSeen*: int64  # Unix timestamp

  Network* = ref object
    peers*: Table[PeerId, Peer]
    maxPeers*: int

proc newNetwork*(maxPeers: int = 100): Network =
  ## Creates a new P2P network manager.
  Network(
    peers: initTable[PeerId, Peer](),
    maxPeers: maxPeers
  )

proc addPeer*(network: Network, address: PeerAddress): PeerId =
  ## Adds a new peer to the network and returns its ID.
  let peerId = "peer_" & $network.peers.len
  let peer = Peer(
    id: peerId,
    address: address,
    status: Connecting,
    lastSeen: 0
  )
  network.peers[peerId] = peer
  peerId

proc connectPeer*(network: Network, peerId: PeerId): bool =
  ## Marks a peer as connected.
  if peerId in network.peers:
    network.peers[peerId].status = Connected
    return true
  false

proc disconnectPeer*(network: Network, peerId: PeerId): bool =
  ## Disconnects a peer.
  if peerId in network.peers:
    network.peers[peerId].status = Disconnected
    return true
  false

proc removePeer*(network: Network, peerId: PeerId): bool =
  ## Removes a peer from the network.
  if peerId in network.peers:
    network.peers.del(peerId)
    return true
  false

proc getConnectedPeers*(network: Network): seq[Peer] =
  ## Returns all currently connected peers.
  result = @[]
  for peer in network.peers.values:
    if peer.status == Connected:
      result.add(peer)

proc peerCount*(network: Network): int =
  ## Returns total number of peers.
  network.peers.len

proc connectedPeerCount*(network: Network): int =
  ## Returns number of connected peers.
  network.getConnectedPeers().len
