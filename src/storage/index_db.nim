## Transaction indexing database for fast transaction lookups.
## Provides efficient mapping between transactions and their block locations.

import std/[tables, options, sets]

type
  TransactionId* = string
  BlockHeight* = Natural
  
  TransactionLocation* = object
    blockHeight*: BlockHeight
    transactionIndex*: int  # Position within the block
  
  IndexDB* = ref object
    txToBlock*: Table[TransactionId, TransactionLocation]
    blockToTxs*: Table[BlockHeight, seq[TransactionId]]  # Block to transaction list
    indexedBlocks*: HashSet[BlockHeight]

proc newIndexDB*(): IndexDB =
  ## Creates a new transaction index database.
  IndexDB(
    txToBlock: initTable[TransactionId, TransactionLocation](),
    blockToTxs: initTable[BlockHeight, seq[TransactionId]](),
    indexedBlocks: initHashSet[BlockHeight]()
  )

proc indexTransaction*(db: IndexDB, txId: TransactionId, blockHeight: BlockHeight, 
                      txIndex: int = 0): bool =
  ## Indexes a transaction to its block location.
  if txId in db.txToBlock:
    return false  # Transaction already indexed
    
  let location = TransactionLocation(
    blockHeight: blockHeight,
    transactionIndex: txIndex
  )
  
  db.txToBlock[txId] = location
  
  # Update block to transactions mapping
  if blockHeight notin db.blockToTxs:
    db.blockToTxs[blockHeight] = @[]
  db.blockToTxs[blockHeight].add(txId)
  
  db.indexedBlocks.incl(blockHeight)
  true

proc getTransactionLocation*(db: IndexDB, txId: TransactionId): Option[TransactionLocation] =
  ## Retrieves the location of a transaction.
  if txId in db.txToBlock:
    some(db.txToBlock[txId])
  else:
    none(TransactionLocation)

proc getBlockTransactions*(db: IndexDB, blockHeight: BlockHeight): seq[TransactionId] =
  ## Returns all transaction IDs in a specific block.
  db.blockToTxs.getOrDefault(blockHeight, @[])

proc hasTransaction*(db: IndexDB, txId: TransactionId): bool =
  ## Checks if a transaction is indexed.
  txId in db.txToBlock

proc removeTransaction*(db: IndexDB, txId: TransactionId): bool =
  ## Removes a transaction from the index.
  if txId notin db.txToBlock:
    return false
    
  let location = db.txToBlock[txId]
  db.txToBlock.del(txId)
  
  # Remove from block mapping
  if location.blockHeight in db.blockToTxs:
    let txList = db.blockToTxs[location.blockHeight]
    var newList: seq[TransactionId] = @[]
    for tx in txList:
      if tx != txId:
        newList.add(tx)
    
    if newList.len > 0:
      db.blockToTxs[location.blockHeight] = newList
    else:
      db.blockToTxs.del(location.blockHeight)
      db.indexedBlocks.excl(location.blockHeight)
  
  true

proc isBlockIndexed*(db: IndexDB, blockHeight: BlockHeight): bool =
  ## Checks if a block has been indexed.
  blockHeight in db.indexedBlocks

proc getIndexedBlockCount*(db: IndexDB): int =
  ## Returns the number of indexed blocks.
  db.indexedBlocks.len

proc getTransactionCount*(db: IndexDB): int =
  ## Returns the total number of indexed transactions.
  db.txToBlock.len

proc clear*(db: IndexDB) =
  ## Clears all indexes.
  db.txToBlock.clear()
  db.blockToTxs.clear()
  db.indexedBlocks.clear()
