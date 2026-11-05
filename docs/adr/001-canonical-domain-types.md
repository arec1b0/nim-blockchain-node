# ADR 001: Canonical Domain Types and Composition Root Direction

## Status

Accepted (fully implemented)

## Context

The codebase defined incompatible duplicates of core domain concepts:

- Two `Transaction` types (VM transfer shape vs mempool fee/size entry)
- Two `StateDB` / `newStateDB` APIs (account ledger vs global key-value store)
- Divergent node construction in `main.nim` and `cli.nim`
- Duplicate `BlockHeight`, `BlockData`, `BlockHash`, and `Block` definitions across storage and network layers

These collisions blocked a coherent transaction lifecycle and made imports ambiguous.

## Decision

### Domain type ownership

Canonical blockchain domain types live in `src/common/types.nim`:

- `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`
- `BlockHeight`, `BlockHash`, `BlockData`, `BlockId`, `Block`, `newBlock`

`common/types` is a leaf module: it must not depend on core, network, storage, or crypto.

`Transaction` is the single type used by both the VM and the mempool. Transfer fields (`sender`, `receiver`, `amount`, `fee`, `nonce`) are authoritative for execution. Mempool metadata (`timestamp`, `size`) is stored on the same object; the VM ignores those fields. The mempool sets `timestamp` when it is zero on insert.

`Block` is the single canonical block domain type shared across layers. Storage-specific DTOs (`StoredBlock` in `blockchain_db.nim`, `TransactionLocation` in `index_db.nim`) remain separate, but reference canonical types. See [ADR 006](006-consolidated-block-domain-types.md) for details.

### Account ledger vs global KV store

| Concern | Type | Module |
|---------|------|--------|
| Account balances and nonces | `StateDB` / `newStateDB()` | `core_engine/state_management.nim` |
| Global key-value state | `GlobalStateStore` / `newGlobalStateStore()` | `storage/state_db.nim` |

Storage-specific DTOs remain outside `common/types`.

### Composition root (implemented in ADR 004)

A single composition root (`src/node.nim`) owns:

- `BlockchainNode` construction
- A typed `NodeConfig` for defaults (gas limit, validators, mempool size, peer limits)
- Shared initialization used by both `main.nim` and `cli.nim`

Entry points only parse input, call the composition root, and expose their interfaces.

### Intended transaction lifecycle (implemented in ADR 005)

```
submit -> mempool validation -> block inclusion -> VM execution -> storage/index update
```

Signature verification is unified in [ADR 002](002-signature-authorization.md). `Block` / `BlockHeight` consolidation is implemented in [ADR 006](006-consolidated-block-domain-types.md).

## Consequences

- VM and mempool share one `Transaction` type; pool callers may omit transfer fields (zero defaults).
- CLI can type `accountState` and `globalState` distinctly without name collision.
- `Block` and `BlockHeight` are canonical in `src/common/types.nim`, eliminating duplicate definitions and import qualification workarounds.
- Centralized node composition is fully realized in `src/node.nim`.
- Canonical transaction lifecycle is enforced via `node.submitAndExecuteTransaction`.
- Account-ledger `StateDB` remains a value type; callers read balances from `vm.state` or `node.accountState` after execution.
