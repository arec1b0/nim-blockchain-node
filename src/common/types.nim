## Canonical domain types shared across layers.
## This module is a leaf dependency: it must not import core, network, or storage.

type
  Address* = string
  Balance* = Natural
  Nonce* = Natural
  TransactionId* = string

  Transaction* = object
    id*: TransactionId
    sender*: Address
    receiver*: Address
    amount*: Balance
    fee*: Balance
    nonce*: Nonce
    ## Mempool metadata (ignored by VM validation/execution).
    timestamp*: int64
    size*: int
