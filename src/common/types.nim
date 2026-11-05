## Canonical domain types shared across layers.
## This module is a leaf dependency: it must not import core, network, storage, or crypto.

import std/times

type
  Address* = string
  Balance* = Natural
  Nonce* = Natural
  TransactionId* = string
  PublicKey* = string
  PrivateKey* = string
  Signature* = string

  Transaction* = object
    id*: TransactionId
    sender*: Address
    receiver*: Address
    amount*: Balance
    fee*: Balance
    nonce*: Nonce
    ## Mempool metadata (ignored by signature payload and VM execution).
    timestamp*: int64
    size*: int
    ## Demo-scheme public key. Not an Ed25519 key.
    publicKey*: PublicKey
    ## Demo-scheme signature over `transactionSigningPayload`. Empty means unsigned.
    signature*: Signature

  # Canonical block domain types
  BlockHeight* = Natural
  BlockHash* = string
  BlockData* = string
  BlockId* = string

  Block* = object
    id*: BlockId
    height*: BlockHeight
    data*: BlockData
    timestamp*: int64
    previousHash*: BlockHash

proc newBlock*(id: BlockId, height: BlockHeight, data: BlockData,
              previousHash: BlockHash = "", timestamp: int64 = 0): Block =
  ## Creates a new canonical Block. If timestamp is 0, uses current unix time.
  Block(
    id: id,
    height: height,
    data: data,
    timestamp: if timestamp != 0: timestamp else: getTime().toUnix(),
    previousHash: previousHash
  )

proc shortId*(id: string): string =
  ## Short non-secret label safe to write in logs.
  if id.len <= 12: id else: id[0 .. 11]

proc hash*(blk: Block): BlockHash {.inline.} =
  ## Returns the canonical hash/ID of the block.
  blk.id
