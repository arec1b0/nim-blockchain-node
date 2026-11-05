## JSON snapshot of account balances and nonces.
##
## Path: `<dataDir>/accounts.json`
##
## Version 1 document:
##   format: "nim-node-accounts"
##   version: 1
##   accounts: array of {address, balance, nonce}, sorted by address
##   checksum: lowercase hex SHA-256 of the compact JSON of `accounts` only
##
## The checksum detects accidental edits. It is not authentication and it is
## not a crash-consistency proof.
##
## Writes go to `accounts.json.tmp` in the same directory, are flushed, then
## replace the destination (POSIX rename, or Windows MoveFileExW with
## replace and write-through). A failed load or a failed replace leaves any
## existing `accounts.json` in place. A leftover `.tmp` is not a store.
##
## This is not a durable database. Two processes can overwrite one snapshot.
## There is no file lock.

import std/[os, json, logging, strutils, algorithm, tables]
import nimcrypto/[sha2, utils]
import ../common/[types, result]
import ../core_engine/state_management

when defined(windows):
  import std/[winlean, widestrs]
else:
  # `std/posix` does not export `rename`. This is the same libc call Nim uses
  # for a same-directory replace: the destination is overwritten.
  proc posixRename(oldname, newname: cstring): cint {.
    importc: "rename", header: "<stdio.h>".}

type
  AccountStoreError* = enum
    asNone
    asEmpty
    asMalformed
    asVersionMismatch
    asChecksumMismatch
    asIo

  FileAccountStore* = ref object
    dataDir: string
    path: string
    state: StateDB

  OpenedFileAccountStore* = object
    store*: FileAccountStore
    fresh*: bool

  AccountRow = tuple
    address: string
    balance: int
    nonce: int

const
  AccountStoreFormat* = "nim-node-accounts"
  AccountStoreVersion* = 1

proc accountStoreFailure*(err: AccountStoreError): string =
  ## Actionable description. Does not include balances or file bodies.
  case err
  of asNone:
    "account store failed"
  of asEmpty:
    "account store file is empty"
  of asMalformed:
    "account store file is malformed"
  of asVersionMismatch:
    "account store version is not supported; supported version is 1"
  of asChecksumMismatch:
    "account store checksum does not match the accounts"
  of asIo:
    "account store file could not be read or written"

proc accountsSnapshotFile*(dataDir: string): string =
  dataDir / "accounts.json"

proc removeQuiet(path: string) =
  try:
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc replaceSnapshot(source, dest: string): bool =
  ## Replaces `dest` with `source` in the same directory.
  ## Returns false on failure. Does not delete `dest`.
  when defined(windows):
    let flags = MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH
    moveFileExW(newWideCString(source), newWideCString(dest), flags) != 0'i32
  else:
    posixRename(cstring(source), cstring(dest)) == 0'i32

proc checksumHex(payload: string): string =
  toHex(sha256.digest(payload).data, lowercase = true)

proc canonicalAccountsJson(state: StateDB): string =
  var rows: seq[AccountRow] = @[]
  for address, account in pairs(state.accounts):
    rows.add((address, int(account.balance), int(account.nonce)))
  rows.sort(proc(a, b: AccountRow): int = cmp(a.address, b.address))
  var arr = newJArray()
  for row in rows:
    var obj = newJObject()
    obj["address"] = newJString(row.address)
    obj["balance"] = newJInt(row.balance)
    obj["nonce"] = newJInt(row.nonce)
    arr.add(obj)
  $arr

proc snapshotDocument(state: StateDB): string =
  let payload = canonicalAccountsJson(state)
  var doc = newJObject()
  doc["format"] = newJString(AccountStoreFormat)
  doc["version"] = newJInt(AccountStoreVersion)
  doc["accounts"] = parseJson(payload)
  doc["checksum"] = newJString(checksumHex(payload))
  $doc

proc naturalField(node: JsonNode, found: var int): bool =
  if node.isNil or node.kind != JInt:
    return false
  let n = node.getBiggestInt
  if n < 0 or n > high(int):
    return false
  found = int(n)
  true

proc parseSnapshot(path, raw: string): Result[StateDB, AccountStoreError] =
  if raw.len == 0 or raw.strip().len == 0:
    return errResult(StateDB, asEmpty)
  var root: JsonNode
  try:
    root = parseJson(raw)
  except JsonParsingError:
    return errResult(StateDB, asMalformed)
  except CatchableError:
    return errResult(StateDB, asIo)
  if root.isNil or root.kind != JObject:
    return errResult(StateDB, asMalformed)

  let formatNode = root{"format"}
  if formatNode.isNil or formatNode.kind != JString or formatNode.getStr() != AccountStoreFormat:
    return errResult(StateDB, asMalformed)

  let versionNode = root{"version"}
  if versionNode.isNil or versionNode.kind != JInt:
    return errResult(StateDB, asMalformed)
  let version = versionNode.getBiggestInt
  if version != AccountStoreVersion:
    error("account store version mismatch path=" & path & " version=" & $version)
    return errResult(StateDB, asVersionMismatch)

  let accountsNode = root{"accounts"}
  if accountsNode.isNil or accountsNode.kind != JArray:
    return errResult(StateDB, asMalformed)

  var state = newStateDB()
  for item in accountsNode.items:
    if item.isNil or item.kind != JObject:
      return errResult(StateDB, asMalformed)
    let addressNode = item{"address"}
    if addressNode.isNil or addressNode.kind != JString:
      return errResult(StateDB, asMalformed)
    let address = addressNode.getStr()
    if address.len == 0 or address in state.accounts:
      return errResult(StateDB, asMalformed)
    var balance, nonce: int
    if not naturalField(item{"balance"}, balance) or not naturalField(item{"nonce"}, nonce):
      return errResult(StateDB, asMalformed)
    state.accounts[address] = Account(balance: Balance(balance), nonce: Nonce(nonce))

  let checksumNode = root{"checksum"}
  if checksumNode.isNil or checksumNode.kind != JString or checksumNode.getStr().len == 0:
    return errResult(StateDB, asMalformed)
  if checksumNode.getStr().toLowerAscii() != checksumHex(canonicalAccountsJson(state)):
    return errResult(StateDB, asChecksumMismatch)
  okResult(state, AccountStoreError)

proc writeSnapshot(path, dataDir, body: string): Status[AccountStoreError] =
  let tmp = path & ".tmp"
  var handle: File
  var opened = false
  try:
    createDir(dataDir)
    removeQuiet(tmp)
    opened = open(handle, tmp, fmWrite)
    if not opened:
      return errStatus(asIo)
    handle.write(body)
    handle.flushFile()
    handle.close()
    opened = false
    if not replaceSnapshot(tmp, path):
      removeQuiet(tmp)
      return errStatus(asIo)
    okStatus(AccountStoreError)
  except CatchableError:
    if opened:
      try:
        handle.close()
      except CatchableError:
        discard
    removeQuiet(tmp)
    errStatus(asIo)

proc openFileAccountStore*(dataDir: string): Result[OpenedFileAccountStore, AccountStoreError] =
  ## Missing file: empty ledger, `fresh = true`, and no file is created.
  ## Any other read problem returns an error and does not write.
  let path = accountsSnapshotFile(dataDir)
  if not fileExists(path):
    let store = FileAccountStore(dataDir: dataDir, path: path, state: newStateDB())
    return okResult(OpenedFileAccountStore(store: store, fresh: true), AccountStoreError)
  try:
    let raw = readFile(path)
    let parsed = parseSnapshot(path, raw)
    if not parsed.ok:
      return errResult(OpenedFileAccountStore, parsed.error)
    let store = FileAccountStore(dataDir: dataDir, path: path, state: parsed.value)
    okResult(OpenedFileAccountStore(store: store, fresh: false), AccountStoreError)
  except CatchableError:
    errResult(OpenedFileAccountStore, asIo)

proc currentState*(store: FileAccountStore): StateDB =
  store.state

proc saveState*(store: FileAccountStore, state: StateDB): Status[AccountStoreError] =
  ## Writes a new snapshot. The in-memory copy changes only after the replace.
  let written = writeSnapshot(store.path, store.dataDir, snapshotDocument(state))
  if written.ok:
    store.state = state
  written

proc closeState*(store: FileAccountStore): Status[AccountStoreError] =
  ## Does not write. `saveState` already flushed.
  discard store
  okStatus(AccountStoreError)
