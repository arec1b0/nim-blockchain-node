## Blockchain state database for managing global state variables.
## Provides key-value storage for blockchain state information.

import std/[tables, options]

type
  StateKey* = string
  StateValue* = int
  
  StateEntry* = object
    value*: StateValue
    lastModified*: int64  # Block height when last modified
  
  StateDB* = ref object
    states*: Table[StateKey, StateEntry]
    version*: int64  # Current state version/block height

proc newStateDB*(version: int64 = 0): StateDB =
  ## Creates a new state database.
  StateDB(
    states: initTable[StateKey, StateEntry](),
    version: version
  )

proc setState*(db: StateDB, key: StateKey, value: StateValue, 
              blockHeight: int64 = 0): bool =
  ## Sets a state value for the given key.
  let height = if blockHeight > 0: blockHeight else: db.version
  db.states[key] = StateEntry(
    value: value,
    lastModified: height
  )
  true

proc getState*(db: StateDB, key: StateKey): StateValue =
  ## Retrieves a state value by key, returns 0 if not found.
  if key in db.states:
    db.states[key].value
  else:
    0

proc getStateEntry*(db: StateDB, key: StateKey): Option[StateEntry] =
  ## Retrieves the full state entry with metadata.
  if key in db.states:
    some(db.states[key])
  else:
    none(StateEntry)

proc hasState*(db: StateDB, key: StateKey): bool =
  ## Checks if a state key exists.
  key in db.states

proc deleteState*(db: StateDB, key: StateKey): bool =
  ## Deletes a state entry.
  if key in db.states:
    db.states.del(key)
    return true
  false

proc getAllStates*(db: StateDB): Table[StateKey, StateEntry] =
  ## Returns a copy of all state entries.
  db.states

proc getStateKeys*(db: StateDB): seq[StateKey] =
  ## Returns all state keys.
  result = @[]
  for key in db.states.keys:
    result.add(key)

proc getStatesModifiedAfter*(db: StateDB, blockHeight: int64): seq[(StateKey, StateEntry)] =
  ## Returns states modified after the given block height.
  result = @[]
  for key, entry in db.states.pairs:
    if entry.lastModified > blockHeight:
      result.add((key, entry))

proc updateVersion*(db: StateDB, newVersion: int64) =
  ## Updates the state database version.
  db.version = newVersion

proc getVersion*(db: StateDB): int64 =
  ## Returns the current state version.
  db.version

proc stateCount*(db: StateDB): int =
  ## Returns the number of state entries.
  db.states.len

proc clear*(db: StateDB) =
  ## Clears all state data.
  db.states.clear()
  db.version = 0
