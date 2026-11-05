## In-process account ledger.
##
## Holds one `StateDB` value and uses the ledger procedures in
## `core_engine/state_management`. Nothing is written to disk.
## Each `newMemoryAccountStore` is an independent ledger.

import ../core_engine/state_management

type
  MemoryAccountStore* = ref object
    state: StateDB

proc newMemoryAccountStore*(): MemoryAccountStore =
  MemoryAccountStore(state: newStateDB())

proc loadState*(store: MemoryAccountStore): StateDB =
  ## Returns the current ledger. `StateDB` is a value, so the caller gets a copy.
  store.state

proc saveState*(store: MemoryAccountStore, state: StateDB) =
  ## Replaces the in-process ledger. Does not touch the filesystem.
  store.state = state

proc closeState*(store: MemoryAccountStore) =
  ## No flush. The ledger disappears with this process.
  discard store
