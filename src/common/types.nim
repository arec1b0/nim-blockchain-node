## Canonical domain types shared across layers.
## This module is a leaf dependency: it must not import core, network, storage, or crypto.

type
  Address* = string
  Balance* = Natural
  Nonce* = Natural
  TransactionId* = string
  PublicKey* = string
  PrivateKey* = string
  Signature* = string

  Transaction* = object
    id*: TransactionId
    sender*: Address
    receiver*: Address
    amount*: Balance
    fee*: Balance
    nonce*: Nonce
    ## Mempool metadata (ignored by signature payload and VM execution).
    timestamp*: int64
    size*: int
    ## Demo-scheme public key. Not an Ed25519 key.
    publicKey*: PublicKey
    ## Demo-scheme signature over `transactionSigningPayload`. Empty means unsigned.
    signature*: Signature

proc shortId*(id: string): string =
  ## Short non-secret label safe to write in logs.
  if id.len <= 12: id else: id[0 .. 11]
