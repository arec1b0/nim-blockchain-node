## Transaction pool management for pending blockchain transactions.
## Handles transaction ordering, validation, and mempool operations.
##
## Admission boundary: `addTransaction` calls `authorizeTransaction` (the same
## demo signature API the VM uses) and rejects unsigned or invalid signatures.
## It does not check balance, nonce, amount, or gas. Those remain in
## `vm.validateTransaction`, which calls the same authorization API again.

import std/[tables, algorithm, times, logging]
import ../common/[types, result]
import ../cryptography/signature_verification

type
  Fee* = Balance

  MempoolAdmitError* = enum
    maNone
    maDuplicate
    maFull
    maMissingPublicKey
    maMissingSignature
    maSenderKeyMismatch
    maInvalidSignature

  Mempool* = ref object
    transactions*: Table[TransactionId, Transaction]
    maxSize*: int
    totalFees*: Fee

proc newMempool*(maxSize: int = 10000): Mempool =
  ## Creates a new transaction mempool.
  Mempool(
    transactions: initTable[TransactionId, Transaction](),
    maxSize: maxSize,
    totalFees: 0
  )

proc rejectAdmit(id: string, reason: MempoolAdmitError): Status[MempoolAdmitError] =
  debug("mempool rejected id=" & shortId(id) & " reason=" & $reason)
  errStatus(reason)

proc authToAdmit(err: AuthError): MempoolAdmitError =
  case err
  of authNone, authInvalidSignature: maInvalidSignature
  of authMissingPublicKey: maMissingPublicKey
  of authMissingSignature: maMissingSignature
  of authSenderKeyMismatch: maSenderKeyMismatch

proc addTransaction*(pool: Mempool, tx: Transaction): Status[MempoolAdmitError] =
  ## Admits a transaction only when the demo signature authorizes `sender`.
  let auth = authorizeTransaction(tx)
  if not auth.ok:
    return rejectAdmit(tx.id, authToAdmit(auth.error))
  if tx.id in pool.transactions:
    return rejectAdmit(tx.id, maDuplicate)
  if pool.transactions.len >= pool.maxSize:
    return rejectAdmit(tx.id, maFull)

  var stored = tx
  if stored.timestamp == 0:
    stored.timestamp = getTime().toUnix

  pool.transactions[stored.id] = stored
  pool.totalFees += stored.fee
  okStatus(MempoolAdmitError)

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
    result = result[0 ..< limit]

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
