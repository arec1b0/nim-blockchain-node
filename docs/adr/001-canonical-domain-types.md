# ADR 001: Canonical Domain Types and Composition Root Direction

## Status

Accepted (partially implemented)

## Context

The codebase defined incompatible duplicates of core domain concepts:

- Two `Transaction` types (VM transfer shape vs mempool fee/size entry)
- Two `StateDB` / `newStateDB` APIs (account ledger vs global key-value store)
- Divergent node construction in `main.nim` and `cli.nim`

These collisions blocked a coherent transaction lifecycle and made imports ambiguous.

## Decision

### Domain type ownership

Canonical blockchain domain types live in `src/common/types.nim`:

- `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`

`common/types` is a leaf module: it must not depend on core, network, storage, or entry points.

`Transaction` is the single type used by both the VM and the mempool. Transfer fields (`sender`, `receiver`, `amount`, `fee`, `nonce`) are authoritative for execution. Mempool metadata (`timestamp`, `size`) is stored on the same object; the VM ignores those fields. The mempool sets `timestamp` when it is zero on insert.

### Account ledger vs global KV store

| Concern | Type | Module |
|---------|------|--------|
| Account balances and nonces | `StateDB` / `newStateDB()` | `core_engine/state_management.nim` |
| Global key-value state | `GlobalStateStore` / `newGlobalStateStore()` | `storage/state_db.nim` |

Storage-specific DTOs remain outside `common/types`.

### Composition root (intended next step)

A single composition root (`src/node.nim` or `src/runtime.nim`) will own:

- `BlockchainNode` construction
- A typed `NodeConfig` for defaults (gas limit, validators, mempool size, peer limits)
- Shared initialization used by both `main.nim` and `cli.nim`

Entry points will only parse input, call the composition root, and expose their interfaces.

### Intended transaction lifecycle (follow-up)

```
submit -> mempool validation -> block inclusion -> VM execution -> storage/index update
```

Signature verification is unified in [ADR 002](002-signature-authorization.md). `Block` / `BlockHeight` consolidation remains deferred.

## Consequences

- VM and mempool share one `Transaction` type; pool callers may omit transfer fields (zero defaults).
- CLI can type `accountState` and `globalState` distinctly without name collision.
- Divergent hardcoded defaults in `main.nim` and `cli.nim` remain until the composition-root PR.
- Current CLI transfer path (VM then mempool) is unchanged and will be realigned in the lifecycle PR.
- Account-ledger `StateDB` remains a value type; callers must read balances from `vm.state` after execution.
- Crypto tests qualify `signature_verification.verifySignature` to avoid ambiguous imports until signature unification.
