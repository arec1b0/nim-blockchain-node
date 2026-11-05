## Transaction index storage facade and memory-backed implementation.
## Provides an abstract boundary for transaction location indexing using canonical domain types.
## Decouples node subsystems from concrete indexing table implementations.

import std/[options]
import ../common/types
import index_db

export types.TransactionId, types.BlockHeight
export index_db.TransactionLocation

type
  IndexStore* = ref object
    name*: string
    indexTxImpl*: proc(txId: TransactionId, blockHeight: BlockHeight, txIndex: int): bool {.closure.}
    getTxLocImpl*: proc(txId: TransactionId): Option[TransactionLocation] {.closure.}
    getBlockTxsImpl*: proc(blockHeight: BlockHeight): seq[TransactionId] {.closure.}
    hasTxImpl*: proc(txId: TransactionId): bool {.closure.}
    removeTxImpl*: proc(txId: TransactionId): bool {.closure.}
    isBlockIndexedImpl*: proc(blockHeight: BlockHeight): bool {.closure.}
    getIndexedBlockCountImpl*: proc(): int {.closure.}
    getTxCountImpl*: proc(): int {.closure.}
    clearImpl*: proc() {.closure.}
    rawDBImpl*: proc(): IndexDB {.closure.}

  MemoryIndexStore* = ref object
    db*: IndexDB

proc newMemoryIndexStore*(db: IndexDB = newIndexDB()): MemoryIndexStore =
  ## Creates a new in-memory index store.
  MemoryIndexStore(db: if db.isNil: newIndexDB() else: db)

proc indexTransaction*(store: MemoryIndexStore, txId: TransactionId, blockHeight: BlockHeight,
                       txIndex: int = 0): bool =
  ## Indexes a transaction to its block location in the memory store.
  if store.isNil or store.db.isNil: false
  else: store.db.indexTransaction(txId, blockHeight, txIndex)

proc getTransactionLocation*(store: MemoryIndexStore, txId: TransactionId): Option[TransactionLocation] =
  ## Retrieves the location of a transaction.
  if store.isNil or store.db.isNil: none(TransactionLocation)
  else: store.db.getTransactionLocation(txId)

proc getBlockTransactions*(store: MemoryIndexStore, blockHeight: BlockHeight): seq[TransactionId] =
  ## Returns all transaction IDs in a specific block.
  if store.isNil or store.db.isNil: @[]
  else: store.db.getBlockTransactions(blockHeight)

proc hasTransaction*(store: MemoryIndexStore, txId: TransactionId): bool =
  ## Checks if a transaction is indexed.
  if store.isNil or store.db.isNil: false
  else: store.db.hasTransaction(txId)

proc removeTransaction*(store: MemoryIndexStore, txId: TransactionId): bool =
  ## Removes a transaction from the index.
  if store.isNil or store.db.isNil: false
  else: store.db.removeTransaction(txId)

proc isBlockIndexed*(store: MemoryIndexStore, blockHeight: BlockHeight): bool =
  ## Checks if a block has been indexed.
  if store.isNil or store.db.isNil: false
  else: store.db.isBlockIndexed(blockHeight)

proc getIndexedBlockCount*(store: MemoryIndexStore): int =
  ## Returns the number of indexed blocks.
  if store.isNil or store.db.isNil: 0
  else: store.db.getIndexedBlockCount()

proc getTransactionCount*(store: MemoryIndexStore): int =
  ## Returns the total number of indexed transactions.
  if store.isNil or store.db.isNil: 0
  else: store.db.getTransactionCount()

proc clear*(store: MemoryIndexStore) =
  ## Clears all transaction indexes.
  if not store.isNil and not store.db.isNil:
    store.db.clear()

proc rawDB*(store: MemoryIndexStore): IndexDB =
  ## Exposes the underlying IndexDB instance.
  if store.isNil: nil else: store.db

proc toIndexStore*(mem: MemoryIndexStore): IndexStore =
  ## Wraps a MemoryIndexStore into an IndexStore facade.
  if mem.isNil:
    return IndexStore(name: "NilMemoryIndexStore")
  IndexStore(
    name: "MemoryIndexStore",
    indexTxImpl: proc(txId: TransactionId, blockHeight: BlockHeight, txIndex: int): bool =
      mem.indexTransaction(txId, blockHeight, txIndex),
    getTxLocImpl: proc(txId: TransactionId): Option[TransactionLocation] =
      mem.getTransactionLocation(txId),
    getBlockTxsImpl: proc(blockHeight: BlockHeight): seq[TransactionId] =
      mem.getBlockTransactions(blockHeight),
    hasTxImpl: proc(txId: TransactionId): bool =
      mem.hasTransaction(txId),
    removeTxImpl: proc(txId: TransactionId): bool =
      mem.removeTransaction(txId),
    isBlockIndexedImpl: proc(blockHeight: BlockHeight): bool =
      mem.isBlockIndexed(blockHeight),
    getIndexedBlockCountImpl: proc(): int =
      mem.getIndexedBlockCount(),
    getTxCountImpl: proc(): int =
      mem.getTransactionCount(),
    clearImpl: proc() =
      mem.clear(),
    rawDBImpl: proc(): IndexDB =
      mem.rawDB()
  )

converter toIndexStoreConv*(mem: MemoryIndexStore): IndexStore =
  ## Implicit converter allowing MemoryIndexStore to be used as an IndexStore.
  mem.toIndexStore()

proc newIndexStore*(mem: MemoryIndexStore = newMemoryIndexStore()): IndexStore =
  ## Creates a new IndexStore facade backed by MemoryIndexStore.
  mem.toIndexStore()

proc indexTransaction*(store: IndexStore, txId: TransactionId, blockHeight: BlockHeight,
                       txIndex: int = 0): bool =
  ## Indexes a transaction through the facade.
  if store.isNil or store.indexTxImpl.isNil: false
  else: store.indexTxImpl(txId, blockHeight, txIndex)

proc getTransactionLocation*(store: IndexStore, txId: TransactionId): Option[TransactionLocation] =
  ## Retrieves transaction location through the facade.
  if store.isNil or store.getTxLocImpl.isNil: none(TransactionLocation)
  else: store.getTxLocImpl(txId)

proc getBlockTransactions*(store: IndexStore, blockHeight: BlockHeight): seq[TransactionId] =
  ## Returns transaction IDs for a block through the facade.
  if store.isNil or store.getBlockTxsImpl.isNil: @[]
  else: store.getBlockTxsImpl(blockHeight)

proc hasTransaction*(store: IndexStore, txId: TransactionId): bool =
  ## Checks if a transaction is indexed through the facade.
  if store.isNil or store.hasTxImpl.isNil: false
  else: store.hasTxImpl(txId)

proc removeTransaction*(store: IndexStore, txId: TransactionId): bool =
  ## Removes a transaction through the facade.
  if store.isNil or store.removeTxImpl.isNil: false
  else: store.removeTxImpl(txId)

proc isBlockIndexed*(store: IndexStore, blockHeight: BlockHeight): bool =
  ## Checks if a block is indexed through the facade.
  if store.isNil or store.isBlockIndexedImpl.isNil: false
  else: store.isBlockIndexedImpl(blockHeight)

proc getIndexedBlockCount*(store: IndexStore): int =
  ## Returns number of indexed blocks through the facade.
  if store.isNil or store.getIndexedBlockCountImpl.isNil: 0
  else: store.getIndexedBlockCountImpl()

proc getTransactionCount*(store: IndexStore): int =
  ## Returns total indexed transactions through the facade.
  if store.isNil or store.getTxCountImpl.isNil: 0
  else: store.getTxCountImpl()

proc clear*(store: IndexStore) =
  ## Clears indexes through the facade.
  if not store.isNil and not store.clearImpl.isNil:
    store.clearImpl()

proc rawDB*(store: IndexStore): IndexDB =
  ## Returns the underlying IndexDB instance if available.
  if store.isNil or store.rawDBImpl.isNil: nil
  else: store.rawDBImpl()
