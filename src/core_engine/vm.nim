import state_management

type
  TransactionId* = string
  Gas* = Natural
  
  Transaction* = object
    id*: TransactionId
    sender*: Address  
    receiver*: Address
    amount*: Balance
    fee*: Balance
    nonce*: Nonce

  VM* = object
    state*: StateDB
    gasLimit*: Gas
    gasUsed*: Gas

const GasPerTransaction* = 21000.Gas

proc newVM*(state: StateDB, gasLimit: Gas): VM =
  VM(state: state, gasLimit: gasLimit, gasUsed: 0)

proc validateTransaction*(vm: VM, tx: Transaction): bool =
  # Check basic transaction validity
  if tx.amount == 0:
    return false
  
  # Check sender has sufficient balance
  let senderBalance = vm.state.getBalance(tx.sender)
  if senderBalance < tx.amount + tx.fee:
    return false
    
  # Check nonce sequence
  let expectedNonce = vm.state.getNonce(tx.sender) + 1
  if tx.nonce != expectedNonce:
    return false
    
  true

proc checkGasLimit*(vm: VM, gasRequired: Gas): bool =
  vm.gasUsed + gasRequired <= vm.gasLimit

proc applyTransaction*(vm: var VM, tx: Transaction): bool =
  # Check gas limit
  if not vm.checkGasLimit(GasPerTransaction):
    return false
    
  # Validate transaction
  if not vm.validateTransaction(tx):
    return false
    
  # Execute transaction
  if not vm.state.decreaseBalance(tx.sender, tx.amount + tx.fee):
    return false
    
  vm.state.increaseBalance(tx.receiver, tx.amount)
  discard vm.state.incrementNonce(tx.sender)
  vm.gasUsed += GasPerTransaction
  
  true

proc resetGas*(vm: var VM, newGasLimit: Gas) =
  vm.gasLimit = newGasLimit
  vm.gasUsed = 0

proc remainingGas*(vm: VM): Gas =
  vm.gasLimit - vm.gasUsed

proc gasUtilization*(vm: VM): float =
  if vm.gasLimit == 0: 0.0 else: vm.gasUsed.float / vm.gasLimit.float

proc executeBatch*(vm: var VM, transactions: seq[Transaction]): seq[bool] =
  result = newSeq[bool](transactions.len)
  for i, tx in transactions:
    result[i] = vm.applyTransaction(tx)

proc getState*(vm: VM): StateDB =
  vm.state
