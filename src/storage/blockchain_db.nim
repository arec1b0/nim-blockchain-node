## Blockchain database for immutable block storage and retrieval.
## Provides efficient access to blockchain blocks by height.

import std/[tables, options]
import ../common/types

export types.BlockHeight, types.BlockData, types.BlockHash, types.Block

type
  StoredBlock* = object
    height*: BlockHeight
    data*: BlockData
    hash*: BlockHash
    timestamp*: int64

  BlockchainDB* = ref object
    blocks*: Table[BlockHeight, StoredBlock]
    blockHashes*: Table[BlockHash, BlockHeight]  # Hash to height mapping
    currentHeight*: BlockHeight

proc toStoredBlock*(blk: Block): StoredBlock =
  ## Converts a canonical domain Block into a storage DTO StoredBlock.
  StoredBlock(
    height: blk.height,
    data: blk.data,
    hash: blk.id,
    timestamp: blk.timestamp
  )

proc toBlock*(stored: StoredBlock, previousHash: BlockHash = ""): Block =
  ## Converts a storage DTO StoredBlock into a canonical domain Block.
  Block(
    id: stored.hash,
    height: stored.height,
    data: stored.data,
    timestamp: stored.timestamp,
    previousHash: previousHash
  )

proc newBlockchainDB*(): BlockchainDB =
  ## Creates a new blockchain database.
  BlockchainDB(
    blocks: initTable[BlockHeight, StoredBlock](),
    blockHashes: initTable[BlockHash, BlockHeight](),
    currentHeight: 0
  )

proc addBlock*(db: BlockchainDB, height: BlockHeight, data: BlockData, 
              hash: BlockHash = "", timestamp: int64 = 0): bool =
  ## Adds a new block to the blockchain database.
  if height in db.blocks:
    return false  # Block already exists
    
  let blockHash = if hash.len > 0: hash else: "hash_" & $height
  let storedBlock = StoredBlock(
    height: height,
    data: data,
    hash: blockHash,
    timestamp: timestamp
  )
  
  db.blocks[height] = storedBlock
  db.blockHashes[blockHash] = height
  
  if height > db.currentHeight:
    db.currentHeight = height
    
  true

proc addBlock*(db: BlockchainDB, blk: Block): bool =
  ## Convenience overload to add a canonical domain Block to the blockchain database.
  db.addBlock(blk.height, blk.data, blk.id, blk.timestamp)

proc getBlock*(db: BlockchainDB, height: BlockHeight): Option[StoredBlock] =
  ## Retrieves a block by height.
  if height in db.blocks:
    some(db.blocks[height])
  else:
    none(StoredBlock)

proc getBlockByHash*(db: BlockchainDB, hash: BlockHash): Option[StoredBlock] =
  ## Retrieves a block by hash.
  if hash in db.blockHashes:
    let height = db.blockHashes[hash]
    some(db.blocks[height])
  else:
    none(StoredBlock)

proc hasBlock*(db: BlockchainDB, height: BlockHeight): bool =
  ## Checks if a block exists at the given height.
  height in db.blocks

proc hasBlockWithHash*(db: BlockchainDB, hash: BlockHash): bool =
  ## Checks if a block with the given hash exists.
  hash in db.blockHashes

proc getLatestBlock*(db: BlockchainDB): Option[StoredBlock] =
  ## Returns the latest block in the chain.
  if db.currentHeight > 0:
    db.getBlock(db.currentHeight)
  else:
    none(StoredBlock)

proc getCurrentHeight*(db: BlockchainDB): BlockHeight =
  ## Returns the current blockchain height.
  db.currentHeight

proc getBlockCount*(db: BlockchainDB): int =
  ## Returns the total number of blocks.
  db.blocks.len

proc getBlockRange*(db: BlockchainDB, startHeight, endHeight: BlockHeight): seq[StoredBlock] =
  ## Returns blocks in the specified height range.
  result = @[]
  for height in startHeight..min(endHeight, db.currentHeight):
    if height in db.blocks:
      result.add(db.blocks[height])
