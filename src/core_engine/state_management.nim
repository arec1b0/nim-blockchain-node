import std/tables

type
  Address* = string
  Balance* = Natural
  Nonce* = Natural
  
  Account* = object
    balance*: Balance
    nonce*: Nonce

  StateDB* = object
    accounts*: Table[Address, Account]

proc newStateDB*(): StateDB =
  StateDB(accounts: initTable[Address, Account]())

proc ensureAccount*(s: var StateDB, address: Address) =
  if address notin s.accounts:
    s.accounts[address] = Account(balance: 0, nonce: 0)

proc hasAccount*(s: StateDB, address: Address): bool =
  address in s.accounts

proc getBalance*(s: StateDB, address: Address): Balance =
  if address in s.accounts: s.accounts[address].balance else: 0

proc setBalance*(s: var StateDB, address: Address, amount: Balance) =
  s.ensureAccount(address)
  s.accounts[address].balance = amount

proc increaseBalance*(s: var StateDB, address: Address, amount: Balance) =
  if amount == 0:
    return
  s.ensureAccount(address)
  s.accounts[address].balance += amount

proc decreaseBalance*(s: var StateDB, address: Address, amount: Balance): bool =
  if amount == 0:
    return true
  if address notin s.accounts:
    return false
  if s.accounts[address].balance < amount:
    return false
  s.accounts[address].balance -= amount
  true

proc getNonce*(s: StateDB, address: Address): Nonce =
  if address in s.accounts: s.accounts[address].nonce else: 0

proc incrementNonce*(s: var StateDB, address: Address): Nonce =
  s.ensureAccount(address)
  inc s.accounts[address].nonce
  s.accounts[address].nonce

proc resetAccount*(s: var StateDB, address: Address): bool =
  if address in s.accounts:
    s.accounts[address] = Account(balance: 0, nonce: 0)
    return true
  false

proc deleteAccount*(s: var StateDB, address: Address): bool =
  if address in s.accounts:
    s.accounts.del(address)
    return true
  false

proc totalSupply*(s: StateDB): Balance =
  result = 0
  for account in s.accounts.values:
    result += account.balance

proc accountCount*(s: StateDB): int =
  s.accounts.len
