import std/logging
import state_management
import ../common/[types, result]
import ../cryptography/signature_verification

type
  Gas* = Natural

  VM* = object
    state*: StateDB
    gasLimit*: Gas
    gasUsed*: Gas

  TxError* = enum
    txNone
    txZeroAmount
    txMissingPublicKey
    txMissingSignature
    txSenderKeyMismatch
    txInvalidSignature
    txInsufficientBalance
    txBadNonce
    txEmptyReceiver
    txGasLimitExceeded
    txDebitFailed

const GasPerTransaction* = 21000.Gas

proc newVM*(state: StateDB, gasLimit: Gas): VM =
  VM(state: state, gasLimit: gasLimit, gasUsed: 0)

proc authToTxError(err: AuthError): TxError =
  case err
  of authNone, authInvalidSignature: txInvalidSignature
  of authMissingPublicKey: txMissingPublicKey
  of authMissingSignature: txMissingSignature
  of authSenderKeyMismatch: txSenderKeyMismatch

proc rejectTx(id: string, reason: TxError): Status[TxError] =
  # Reason is an enum name. The signature and key are not logged.
  debug("transaction rejected id=" & shortId(id) & " reason=" & $reason)
  errStatus(reason)

proc validateTransaction*(vm: VM, tx: Transaction): Status[TxError] =
  ## Rejects unsigned and invalid demo signatures before balance or nonce checks.
  ## Balance changes happen only in `applyTransaction` after this returns ok.
  let auth = authorizeTransaction(tx)
  if not auth.ok:
    return rejectTx(tx.id, authToTxError(auth.error))
  if tx.receiver.len == 0:
    return rejectTx(tx.id, txEmptyReceiver)
  if tx.amount == 0:
    return rejectTx(tx.id, txZeroAmount)
  let senderBalance = vm.state.getBalance(tx.sender)
  if senderBalance < tx.amount + tx.fee:
    return rejectTx(tx.id, txInsufficientBalance)
  let expectedNonce = vm.state.getNonce(tx.sender) + 1
  if tx.nonce != expectedNonce:
    return rejectTx(tx.id, txBadNonce)
  okStatus(TxError)

proc checkGasLimit*(vm: VM, gasRequired: Gas): bool =
  vm.gasUsed + gasRequired <= vm.gasLimit

proc applyTransaction*(vm: var VM, tx: Transaction): Status[TxError] =
  if not vm.checkGasLimit(GasPerTransaction):
    return rejectTx(tx.id, txGasLimitExceeded)
  let valid = vm.validateTransaction(tx)
  if not valid.ok:
    return valid
  if not vm.state.decreaseBalance(tx.sender, tx.amount + tx.fee):
    return rejectTx(tx.id, txDebitFailed)
  vm.state.increaseBalance(tx.receiver, tx.amount)
  discard vm.state.incrementNonce(tx.sender)
  vm.gasUsed += GasPerTransaction
  okStatus(TxError)

proc resetGas*(vm: var VM, newGasLimit: Gas) =
  vm.gasLimit = newGasLimit
  vm.gasUsed = 0

proc remainingGas*(vm: VM): Gas =
  vm.gasLimit - vm.gasUsed

proc gasUtilization*(vm: VM): float =
  if vm.gasLimit == 0: 0.0 else: vm.gasUsed.float / vm.gasLimit.float

proc executeBatch*(vm: var VM, transactions: seq[Transaction]): seq[Status[TxError]] =
  result = newSeq[Status[TxError]](transactions.len)
  for i, tx in transactions:
    result[i] = vm.applyTransaction(tx)

proc getState*(vm: VM): StateDB =
  vm.state
