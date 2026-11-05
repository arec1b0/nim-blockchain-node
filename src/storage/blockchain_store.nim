## Blockchain storage facade and memory-backed implementation.
## Provides an abstract boundary for immutable block storage using canonical domain types.
## Decouples node subsystems from concrete database table implementations.

import std/[options]
import ../common/types
import blockchain_db

export types.Block, types.BlockHeight, types.BlockHash, types.BlockData, types.BlockId, types.hash
export blockchain_db.StoredBlock, blockchain_db.toStoredBlock, blockchain_db.toBlock

type
  BlockchainStore* = ref object
    name*: string
    addBlockImpl*: proc(blk: Block): bool {.closure.}
    getBlockImpl*: proc(height: BlockHeight): Option[Block] {.closure.}
    getBlockByHashImpl*: proc(hash: BlockHash): Option[Block] {.closure.}
    hasBlockImpl*: proc(height: BlockHeight): bool {.closure.}
    hasBlockWithHashImpl*: proc(hash: BlockHash): bool {.closure.}
    getCurrentHeightImpl*: proc(): BlockHeight {.closure.}
    getLatestBlockImpl*: proc(): Option[Block] {.closure.}
    getBlockCountImpl*: proc(): int {.closure.}
    getBlockRangeImpl*: proc(startHeight, endHeight: BlockHeight): seq[Block] {.closure.}
    rawDBImpl*: proc(): BlockchainDB {.closure.}

  MemoryBlockchainStore* = ref object
    db*: BlockchainDB

proc newMemoryBlockchainStore*(db: BlockchainDB = newBlockchainDB()): MemoryBlockchainStore =
  ## Creates a new in-memory blockchain store.
  MemoryBlockchainStore(db: if db.isNil: newBlockchainDB() else: db)

proc addBlock*(store: MemoryBlockchainStore, blk: Block): bool =
  ## Adds a canonical domain Block to the memory store.
  if store.isNil or store.db.isNil: return false
  store.db.addBlock(blk)

proc addBlock*(store: MemoryBlockchainStore, height: BlockHeight, data: BlockData,
               hash: BlockHash = "", timestamp: int64 = 0): bool =
  ## Adds a block using individual primitive attributes.
  if store.isNil or store.db.isNil: return false
  store.db.addBlock(height, data, hash, timestamp)

proc getBlock*(store: MemoryBlockchainStore, height: BlockHeight): Option[Block] =
  ## Retrieves a block by height as a canonical domain Block.
  if store.isNil or store.db.isNil: return none(Block)
  let stored = store.db.getBlock(height)
  if stored.isSome:
    some(stored.get.toBlock())
  else:
    none(Block)

proc getBlockByHash*(store: MemoryBlockchainStore, hash: BlockHash): Option[Block] =
  ## Retrieves a block by hash as a canonical domain Block.
  if store.isNil or store.db.isNil: return none(Block)
  let stored = store.db.getBlockByHash(hash)
  if stored.isSome:
    some(stored.get.toBlock())
  else:
    none(Block)

proc hasBlock*(store: MemoryBlockchainStore, height: BlockHeight): bool =
  ## Checks if a block exists at the given height.
  if store.isNil or store.db.isNil: false
  else: store.db.hasBlock(height)

proc hasBlockWithHash*(store: MemoryBlockchainStore, hash: BlockHash): bool =
  ## Checks if a block with the given hash exists.
  if store.isNil or store.db.isNil: false
  else: store.db.hasBlockWithHash(hash)

proc getCurrentHeight*(store: MemoryBlockchainStore): BlockHeight =
  ## Returns the current blockchain height.
  if store.isNil or store.db.isNil: 0
  else: store.db.getCurrentHeight()

proc getLatestBlock*(store: MemoryBlockchainStore): Option[Block] =
  ## Returns the latest block as a canonical domain Block.
  if store.isNil or store.db.isNil: return none(Block)
  let stored = store.db.getLatestBlock()
  if stored.isSome:
    some(stored.get.toBlock())
  else:
    none(Block)

proc getBlockCount*(store: MemoryBlockchainStore): int =
  ## Returns the total number of stored blocks.
  if store.isNil or store.db.isNil: 0
  else: store.db.getBlockCount()

proc getBlockRange*(store: MemoryBlockchainStore, startHeight, endHeight: BlockHeight): seq[Block] =
  ## Returns canonical domain Blocks in the specified height range.
  result = @[]
  if store.isNil or store.db.isNil: return
  for s in store.db.getBlockRange(startHeight, endHeight):
    result.add(s.toBlock())

proc rawDB*(store: MemoryBlockchainStore): BlockchainDB =
  ## Exposes the underlying BlockchainDB instance.
  if store.isNil: nil else: store.db

proc getStoredBlock*(store: MemoryBlockchainStore, height: BlockHeight): Option[StoredBlock] =
  ## Returns the storage DTO directly if needed.
  if store.isNil or store.db.isNil: none(StoredBlock)
  else: store.db.getBlock(height)

proc toBlockchainStore*(mem: MemoryBlockchainStore): BlockchainStore =
  ## Wraps a MemoryBlockchainStore into a BlockchainStore facade.
  if mem.isNil:
    return BlockchainStore(name: "NilMemoryBlockchainStore")
  BlockchainStore(
    name: "MemoryBlockchainStore",
    addBlockImpl: proc(blk: Block): bool = mem.addBlock(blk),
    getBlockImpl: proc(height: BlockHeight): Option[Block] = mem.getBlock(height),
    getBlockByHashImpl: proc(hash: BlockHash): Option[Block] = mem.getBlockByHash(hash),
    hasBlockImpl: proc(height: BlockHeight): bool = mem.hasBlock(height),
    hasBlockWithHashImpl: proc(hash: BlockHash): bool = mem.hasBlockWithHash(hash),
    getCurrentHeightImpl: proc(): BlockHeight = mem.getCurrentHeight(),
    getLatestBlockImpl: proc(): Option[Block] = mem.getLatestBlock(),
    getBlockCountImpl: proc(): int = mem.getBlockCount(),
    getBlockRangeImpl: proc(startHeight, endHeight: BlockHeight): seq[Block] = mem.getBlockRange(startHeight, endHeight),
    rawDBImpl: proc(): BlockchainDB = mem.rawDB()
  )

converter toBlockchainStoreConv*(mem: MemoryBlockchainStore): BlockchainStore =
  ## Implicit converter allowing MemoryBlockchainStore to be used as a BlockchainStore.
  mem.toBlockchainStore()

proc newBlockchainStore*(mem: MemoryBlockchainStore = newMemoryBlockchainStore()): BlockchainStore =
  ## Creates a new BlockchainStore facade backed by MemoryBlockchainStore.
  mem.toBlockchainStore()

proc addBlock*(store: BlockchainStore, blk: Block): bool =
  ## Adds a canonical domain Block through the facade.
  if store.isNil or store.addBlockImpl.isNil: false
  else: store.addBlockImpl(blk)

proc addBlock*(store: BlockchainStore, height: BlockHeight, data: BlockData,
               hash: BlockHash = "", timestamp: int64 = 0): bool =
  ## Adds a block using primitive attributes through the facade.
  let blockHash = if hash.len > 0: hash else: "hash_" & $height
  store.addBlock(newBlock(blockHash, height, data, "", timestamp))

proc getBlock*(store: BlockchainStore, height: BlockHeight): Option[Block] =
  ## Retrieves a block by height through the facade.
  if store.isNil or store.getBlockImpl.isNil: none(Block)
  else: store.getBlockImpl(height)

proc getBlockByHash*(store: BlockchainStore, hash: BlockHash): Option[Block] =
  ## Retrieves a block by hash through the facade.
  if store.isNil or store.getBlockByHashImpl.isNil: none(Block)
  else: store.getBlockByHashImpl(hash)

proc hasBlock*(store: BlockchainStore, height: BlockHeight): bool =
  ## Checks if a block exists at the given height through the facade.
  if store.isNil or store.hasBlockImpl.isNil: false
  else: store.hasBlockImpl(height)

proc hasBlockWithHash*(store: BlockchainStore, hash: BlockHash): bool =
  ## Checks if a block with the given hash exists through the facade.
  if store.isNil or store.hasBlockWithHashImpl.isNil: false
  else: store.hasBlockWithHashImpl(hash)

proc getCurrentHeight*(store: BlockchainStore): BlockHeight =
  ## Returns current height through the facade.
  if store.isNil or store.getCurrentHeightImpl.isNil: 0
  else: store.getCurrentHeightImpl()

proc getLatestBlock*(store: BlockchainStore): Option[Block] =
  ## Returns the latest block through the facade.
  if store.isNil or store.getLatestBlockImpl.isNil: none(Block)
  else: store.getLatestBlockImpl()

proc getBlockCount*(store: BlockchainStore): int =
  ## Returns total block count through the facade.
  if store.isNil or store.getBlockCountImpl.isNil: 0
  else: store.getBlockCountImpl()

proc getBlockRange*(store: BlockchainStore, startHeight, endHeight: BlockHeight): seq[Block] =
  ## Returns a range of blocks through the facade.
  if store.isNil or store.getBlockRangeImpl.isNil: @[]
  else: store.getBlockRangeImpl(startHeight, endHeight)

proc rawDB*(store: BlockchainStore): BlockchainDB =
  ## Returns the underlying BlockchainDB instance if available.
  if store.isNil or store.rawDBImpl.isNil: nil
  else: store.rawDBImpl()

proc getStoredBlock*(store: BlockchainStore, height: BlockHeight): Option[StoredBlock] =
  ## Returns the StoredBlock DTO through the facade.
  let blkOpt = store.getBlock(height)
  if blkOpt.isSome:
    some(blkOpt.get.toStoredBlock())
  else:
    none(StoredBlock)
