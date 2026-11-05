## Account-store facade.
##
## Callers depend on this module, not on a concrete table. `openAccountStore`
## selects the backend from `dataDir` at runtime:
##
## - `:memory:` binds `MemoryAccountStore` (no files)
## - any other path binds `FileAccountStore` (`<dataDir>/accounts.json`)
##
## A Nim concept cannot hold that choice: concepts are resolved at compile time.
## The three closures are the swappable boundary for a later backend.
##
## `AccountStoreError` is declared next to the snapshot parser and re-exported
## here so initialization code imports one module.

import ../common/[result, config]
import ../core_engine/state_management
import memory_account_store
import file_account_store

export AccountStoreError, accountStoreFailure

type
  AccountStore* = ref object
    dataDir*: string
    fresh*: bool
    loadImpl: proc(): Result[StateDB, AccountStoreError] {.closure.}
    saveImpl: proc(state: StateDB): Status[AccountStoreError] {.closure.}
    closeImpl: proc(): Status[AccountStoreError] {.closure.}

  OpenedAccountStore* = object
    store*: AccountStore
    fresh*: bool

  PreparedLedger* = object
    store*: AccountStore
    state*: StateDB

proc loadAccounts*(store: AccountStore): Result[StateDB, AccountStoreError] =
  if store.isNil or store.loadImpl.isNil:
    return errResult(StateDB, asIo)
  store.loadImpl()

proc saveAccounts*(store: AccountStore, state: StateDB): Status[AccountStoreError] =
  if store.isNil or store.saveImpl.isNil:
    return errStatus(asIo)
  store.saveImpl(state)

proc closeAccountStore*(store: AccountStore): Status[AccountStoreError] =
  ## Closes the backend. File stores do not write again here.
  if store.isNil or store.closeImpl.isNil:
    return okStatus(AccountStoreError)
  store.closeImpl()

proc openAccountStore*(dataDir: string): Result[OpenedAccountStore, AccountStoreError] =
  ## Missing snapshot: `fresh` is true and no file is created.
  ## A bad snapshot returns an error and is left untouched.
  ## Each `:memory:` call is a new ledger.
  if isMemoryDataDir(dataDir):
    let memory = newMemoryAccountStore()
    let store = AccountStore(
      dataDir: dataDir,
      fresh: true,
      loadImpl: proc(): Result[StateDB, AccountStoreError] =
        okResult(memory.loadState(), AccountStoreError),
      saveImpl: proc(state: StateDB): Status[AccountStoreError] =
        memory.saveState(state)
        okStatus(AccountStoreError),
      closeImpl: proc(): Status[AccountStoreError] =
        memory.closeState()
        okStatus(AccountStoreError)
    )
    return okResult(OpenedAccountStore(store: store, fresh: true), AccountStoreError)

  let opened = openFileAccountStore(dataDir)
  if not opened.ok:
    return errResult(OpenedAccountStore, opened.error)
  let fileStore = opened.value.store
  let fresh = opened.value.fresh
  let store = AccountStore(
    dataDir: dataDir,
    fresh: fresh,
    loadImpl: proc(): Result[StateDB, AccountStoreError] =
      okResult(fileStore.currentState(), AccountStoreError),
    saveImpl: proc(state: StateDB): Status[AccountStoreError] =
      fileStore.saveState(state),
    closeImpl: proc(): Status[AccountStoreError] =
      fileStore.closeState()
  )
  okResult(OpenedAccountStore(store: store, fresh: fresh), AccountStoreError)

proc prepareAccountLedger*(dataDir: string): Result[PreparedLedger, AccountStoreError] =
  ## Loads an existing snapshot. A missing snapshot is seeded with genesis
  ## balance 1000000 and saved once. An existing snapshot, including an empty
  ## account list, is not reseeded. The caller closes `store`.
  let opened = openAccountStore(dataDir)
  if not opened.ok:
    return errResult(PreparedLedger, opened.error)
  let loaded = opened.value.store.loadAccounts()
  if not loaded.ok:
    discard opened.value.store.closeAccountStore()
    return errResult(PreparedLedger, loaded.error)
  var state = loaded.value
  if opened.value.fresh:
    state.setBalance("genesis", 1000000)
    let saved = opened.value.store.saveAccounts(state)
    if not saved.ok:
      discard opened.value.store.closeAccountStore()
      return errResult(PreparedLedger, saved.error)
  okResult(PreparedLedger(store: opened.value.store, state: state), AccountStoreError)
