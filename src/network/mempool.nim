## Transaction pool management for pending blockchain transactions.
## Handles transaction ordering, validation, and mempool operations.

import std/[tables, algorithm, times]

type
  TransactionId* = string
  Fee* = Natural
  
  Transaction* = object
    id*: TransactionId
    fee*: Fee
    timestamp*: int64  # When transaction was added to mempool
    size*: int        # Transaction size in bytes

  Mempool* = ref object
    transactions*: Table[TransactionId, Transaction]
    maxSize*: int     # Maximum number of transactions
    totalFees*: Fee   # Total fees in mempool

proc newMempool*(maxSize: int = 10000): Mempool =
  ## Creates a new transaction mempool.
  Mempool(
    transactions: initTable[TransactionId, Transaction](),
    maxSize: maxSize,
    totalFees: 0
  )

proc addTransaction*(pool: Mempool, tx: Transaction): bool =
  ## Adds a transaction to the mempool if not already present.
  if tx.id in pool.transactions:
    return false
    
  if pool.transactions.len >= pool.maxSize:
    return false
    
  pool.transactions[tx.id] = tx
  pool.totalFees += tx.fee
  true

proc removeTransaction*(pool: Mempool, txId: TransactionId): bool =
  ## Removes a transaction from the mempool.
  if txId in pool.transactions:
    let tx = pool.transactions[txId]
    pool.totalFees -= tx.fee
    pool.transactions.del(txId)
    return true
  false

proc hasTransaction*(pool: Mempool, txId: TransactionId): bool =
  ## Checks if a transaction exists in the mempool.
  txId in pool.transactions

proc getTransaction*(pool: Mempool, txId: TransactionId): Transaction =
  ## Retrieves a transaction by ID.
  pool.transactions.getOrDefault(txId)

proc getTransactionsByFee*(pool: Mempool, limit: int = 100): seq[Transaction] =
  ## Returns transactions ordered by fee (highest first).
  result = @[]
  for tx in pool.transactions.values:
    result.add(tx)
  
  result.sort(proc(a, b: Transaction): int = cmp(b.fee, a.fee))
  
  if result.len > limit:
    result = result[0..<limit]

proc transactionCount*(pool: Mempool): int =
  ## Returns the number of transactions in the mempool.
  pool.transactions.len

proc clear*(pool: Mempool) =
  ## Removes all transactions from the mempool.
  pool.transactions.clear()
  pool.totalFees = 0

proc estimateAverageFee*(pool: Mempool): float =
  ## Calculates the average transaction fee in the mempool.
  if pool.transactions.len == 0:
    return 0.0
  pool.totalFees.float / pool.transactions.len.float
