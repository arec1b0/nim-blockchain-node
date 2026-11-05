## Blockchain global state store for key-value state variables.
## Provides versioned key-value storage for blockchain state information.
## Distinct from the account-ledger StateDB in core_engine/state_management.

import std/[tables, options]

type
  StateKey* = string
  StateValue* = int
  
  StateEntry* = object
    value*: StateValue
    lastModified*: int64  # Block height when last modified
  
  GlobalStateStore* = ref object
    states*: Table[StateKey, StateEntry]
    version*: int64  # Current state version/block height

proc newGlobalStateStore*(version: int64 = 0): GlobalStateStore =
  ## Creates a new global state store.
  GlobalStateStore(
    states: initTable[StateKey, StateEntry](),
    version: version
  )

proc setState*(db: GlobalStateStore, key: StateKey, value: StateValue, 
              blockHeight: int64 = 0): bool =
  ## Sets a state value for the given key.
  let height = if blockHeight > 0: blockHeight else: db.version
  db.states[key] = StateEntry(
    value: value,
    lastModified: height
  )
  true

proc getState*(db: GlobalStateStore, key: StateKey): StateValue =
  ## Retrieves a state value by key, returns 0 if not found.
  if key in db.states:
    db.states[key].value
  else:
    0

proc getStateEntry*(db: GlobalStateStore, key: StateKey): Option[StateEntry] =
  ## Retrieves the full state entry with metadata.
  if key in db.states:
    some(db.states[key])
  else:
    none(StateEntry)

proc hasState*(db: GlobalStateStore, key: StateKey): bool =
  ## Checks if a state key exists.
  key in db.states

proc deleteState*(db: GlobalStateStore, key: StateKey): bool =
  ## Deletes a state entry.
  if key in db.states:
    db.states.del(key)
    return true
  false

proc getAllStates*(db: GlobalStateStore): Table[StateKey, StateEntry] =
  ## Returns a copy of all state entries.
  db.states

proc getStateKeys*(db: GlobalStateStore): seq[StateKey] =
  ## Returns all state keys.
  result = @[]
  for key in db.states.keys:
    result.add(key)

proc getStatesModifiedAfter*(db: GlobalStateStore, blockHeight: int64): seq[(StateKey, StateEntry)] =
  ## Returns states modified after the given block height.
  result = @[]
  for key, entry in db.states.pairs:
    if entry.lastModified > blockHeight:
      result.add((key, entry))

proc updateVersion*(db: GlobalStateStore, newVersion: int64) =
  ## Updates the state store version.
  db.version = newVersion

proc getVersion*(db: GlobalStateStore): int64 =
  ## Returns the current state version.
  db.version

proc stateCount*(db: GlobalStateStore): int =
  ## Returns the number of state entries.
  db.states.len

proc clear*(db: GlobalStateStore) =
  ## Clears all state data.
  db.states.clear()
  db.version = 0
