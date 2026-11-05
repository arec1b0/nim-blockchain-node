## Plaintext file keystore for the educational prototype.
##
## NOT encrypted. NOT a production keystore. Anyone who can read the file
## has the private key. The demo signature scheme is also forgeable by
## anyone who knows the public key (see `signature_verification.nim`).
##
## Path: `<dataDir>/keystore/<address>.key`
##
## Format (UTF-8, one field per line):
##   version=1
##   scheme=demo-sha256
##   address=<address>
##   public_key=<hex public key>
##   private_key=<hex private key>
##   warning=plaintext-educational-keystore-not-encrypted
##
## Permissions: after writing, the file is set to owner read/write
## (`{fpUserRead, fpUserWrite}`, POSIX mode 0600) and the directory to
## owner-only on non-Windows hosts (0700). Nim's `setFilePermissions` on
## Windows only toggles the read-only file attribute. It does not install
## an owner-only ACL, so the file may remain readable by other local users.
## That Windows limitation is accepted for this prototype.
##
## Procedures in this module do not log private keys, public keys, or file bodies.

import std/[os, strutils]
import ../common/[types, result]
import signature_verification

type
  KeystoreError* = enum
    ksNone
    ksMissing
    ksMalformed
    ksUnsafePath
    ksExists
    ksIo

  StoredKey* = object
    address*: Address
    publicKey*: PublicKey
    privateKey*: PrivateKey

proc isSafeKeyId(address: string): bool =
  if address.len == 0 or address.len > 128:
    return false
  for ch in address:
    if ch notin {'a' .. 'z', 'A' .. 'Z', '0' .. '9'}:
      return false
  true

proc keystoreFile*(dataDir: string, address: Address): string =
  dataDir / "keystore" / (address & ".key")

proc tightenFile(path: string) =
  setFilePermissions(path, {fpUserRead, fpUserWrite})

proc tightenDir(path: string) =
  when defined(windows):
    # POSIX directory modes are not available. See the module comment.
    discard path
  else:
    setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})

proc keystoreDocument(address: Address, publicKey: PublicKey, privateKey: PrivateKey): string =
  "version=1\n" &
    "scheme=" & DemoSignatureScheme & "\n" &
    "address=" & address & "\n" &
    "public_key=" & publicKey & "\n" &
    "private_key=" & privateKey & "\n" &
    "warning=plaintext-educational-keystore-not-encrypted\n"

proc removeQuiet(path: string) =
  try:
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc saveKeystore*(dataDir: string, address: Address, publicKey: PublicKey,
    privateKey: PrivateKey): Status[KeystoreError] =
  ## Writes a new key file. Refuses to overwrite an existing key.
  if not isSafeKeyId(address) or not isSafeKeyId(addressFromPublicKey(publicKey)):
    return errStatus(ksUnsafePath)
  if publicKey.len == 0 or privateKey.len == 0:
    return errStatus(ksMalformed)
  if addressFromPublicKey(publicKey) != address:
    return errStatus(ksMalformed)
  let dir = dataDir / "keystore"
  let path = keystoreFile(dataDir, address)
  if fileExists(path):
    return errStatus(ksExists)
  let body = keystoreDocument(address, publicKey, privateKey)
  let tmp = path & ".tmp"
  try:
    createDir(dir)
    tightenDir(dir)
    removeQuiet(tmp)
    writeFile(tmp, body)
    tightenFile(tmp)
    if fileExists(path):
      removeQuiet(tmp)
      return errStatus(ksExists)
    moveFile(tmp, path)
    okStatus(KeystoreError)
  except CatchableError:
    removeQuiet(tmp)
    errStatus(ksIo)

proc loadKeystore*(dataDir: string, address: Address): Result[StoredKey, KeystoreError] =
  ## Loads a key into memory for signing. Callers must not log `value.privateKey`.
  if not isSafeKeyId(address):
    return errResult(StoredKey, ksUnsafePath)
  let path = keystoreFile(dataDir, address)
  if not fileExists(path):
    return errResult(StoredKey, ksMissing)
  try:
    var
      versionField = ""
      schemeField = ""
      addressField = ""
      publicField = ""
      privateField = ""
    for rawLine in readFile(path).splitLines():
      let line = rawLine.strip()
      if line.len == 0 or line.startsWith("#"):
        continue
      let eq = line.find('=')
      if eq <= 0:
        continue
      let key = line[0 ..< eq].strip()
      let val = line[eq + 1 .. ^1].strip()
      case key
      of "version": versionField = val
      of "scheme": schemeField = val
      of "address": addressField = val
      of "public_key": publicField = val
      of "private_key": privateField = val
      else:
        discard
    if versionField != "1" or schemeField != DemoSignatureScheme:
      return errResult(StoredKey, ksMalformed)
    if addressField != address or publicField.len == 0 or privateField.len == 0:
      return errResult(StoredKey, ksMalformed)
    if addressFromPublicKey(publicField) != address:
      return errResult(StoredKey, ksMalformed)
    okResult(StoredKey(
      address: addressField,
      publicKey: publicField,
      privateKey: privateField
    ), KeystoreError)
  except CatchableError:
    errResult(StoredKey, ksIo)
