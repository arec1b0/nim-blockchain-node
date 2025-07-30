import std/tables

type
  ValidatorId* = int
  Stake* = int
  
  Validator* = object
    id*: ValidatorId
    stake*: Stake
    active*: bool

  Consensus* = object
    validators*: Table[ValidatorId, Validator]

proc newConsensus*(): Consensus =
  Consensus(validators: initTable[ValidatorId, Validator]())

proc addValidator*(c: var Consensus, id: ValidatorId, stake: Stake): bool =
  if stake <= 0 or id in c.validators:
    return false
  c.validators[id] = Validator(id: id, stake: stake, active: true)
  true

proc deactivateValidator*(c: var Consensus, id: ValidatorId): bool =
  if id in c.validators:
    c.validators[id].active = false
    return true
  false

proc activateValidator*(c: var Consensus, id: ValidatorId): bool =
  if id in c.validators:
    c.validators[id].active = true
    return true
  false

proc removeValidator*(c: var Consensus, id: ValidatorId): bool =
  if id in c.validators:
    c.validators.del(id)
    return true
  false

proc activeValidatorCount*(c: Consensus): int =
  result = 0
  for validator in c.validators.values:
    if validator.active:
      inc result

proc calculateQuorum*(c: Consensus): int =
  let activeCount = c.activeValidatorCount()
  if activeCount == 0: 0 else: (activeCount div 2) + 1

proc hasQuorum*(c: Consensus, votes: seq[ValidatorId]): bool =
  var validVotes = 0
  for id in votes:
    if id in c.validators and c.validators[id].active:
      inc validVotes
  validVotes >= c.calculateQuorum()

proc getValidatorStake*(c: Consensus, id: ValidatorId): Stake =
  if id in c.validators: c.validators[id].stake else: 0

proc totalActiveStake*(c: Consensus): Stake =
  result = 0
  for validator in c.validators.values:
    if validator.active:
      result += validator.stake

proc hasValidator*(c: Consensus, id: ValidatorId): bool =
  id in c.validators

proc isValidatorActive*(c: Consensus, id: ValidatorId): bool =
  id in c.validators and c.validators[id].active
