# POIDH v3 — Security Analysis, Spec Compliance, and v2 Comparison

This document maps the implemented `PoidhV3` rebuild in this repository to the **POIDH v3 Security Analysis & Rebuild Specification** (Dec 17, 2025) and summarizes the key differences vs. the exploited v2 design described in that spec.

It is **not** a professional audit. It is an implementation-level report intended to make review, indexing, and verification easier.

## Key Links (from the spec)

- Original exploit TX: https://basescan.org/tx/0x0545a4e5800632ba2194fb9349264ff7f3d3bb18d28ee168d57369b14422f11f
- Whitehack TX: https://basescan.org/tx/0xdd1cb64cded3abcd5078773d7d6075780674c052a83a3d22b9c7f9538b1178b3
- Post-mortem: https://words.poidh.xyz/poidh-december-8th-exploit
- v2 repo: https://github.com/picsoritdidnthappen/poidh-contracts
- v1 repo: https://github.com/kaspotz/pics-or-it

## Scope

This report covers:

- `src/PoidhV3.sol` (bounty logic, voting, escrow accounting, pull withdrawals)
- `src/PoidhClaimNFT.sol` (claim NFT minted to escrow, transferred without callback)
- Deploy script + tests, where relevant to security claims

## Protocol Overview (v3 as implemented)

### Preserved core mechanics

- **Solo bounties**: issuer funds a bounty and later accepts a claim directly.
- **Open bounties**: issuer funds a bounty, others can contribute, claim selection is via a vote.
- **Claims**: anyone (except issuer) can create a claim; a claim NFT is minted.
- **Voting**: 48h `votingPeriod` (configurable) and **>50% by weight** to pass.
- **Fee**: 2.5% (`FEE_BPS = 250`) routed to `treasury`.

### Deliberate behavior changes (vs. v2 described in the spec)

1. **All value movement is pull-based**: payouts/refunds accrue to `pendingWithdrawals`, and users (and treasury) call `withdraw()`. No more inline `.call{value: ...}` to arbitrary recipients.
2. **Open bounty cancellation is constant-time**: `cancelOpenBounty()` closes the bounty and refunds the issuer’s contribution; contributors individually claim refunds with `claimRefundFromCancelledOpenBounty()`.
3. **Claim NFT semantics are “mint to escrow”**: claim NFT is minted to the POIDH contract (escrow) at claim creation, then transferred to bounty issuer on acceptance using `transferFrom` (not `safeTransferFrom`).
4. **Once external funding happens, voting is always required**: `everHadExternalContributor[bountyId]` prevents “withdraw-to-solo then direct accept” edge cases.

## v2 Vulnerabilities (from the spec) and v3 Fixes

### 2.1 ERC721 callback reentrancy in `_acceptClaim()` (blackhat)

**Spec’s root cause**: v2 used an ERC721 `safeTransfer` to a potentially-contract issuer before the bounty state was fully finalized and without enforcing `claim.accepted` on entry. The callback allowed re-entry to accept repeatedly and drain `bounty.amount`.

**v3 mitigation summary**

- **State finalization is complete before external calls**:
  - `bounty.amount = 0`
  - `claim.accepted = true`
  - voting state cleared (if applicable)
- **No value transfer occurs in `_acceptClaim()`** (pull-only).
- **No ERC721 receiver callback**:
  - Claim NFT is transferred with `transferFrom`, not `safeTransferFrom`.
  - Claim NFT is minted with `_mint`, not `_safeMint`.
- **ReentrancyGuard applied at the public entrypoints** and the only external call to an untrusted receiver is `withdraw()`, which is also guarded.

**Implementation references**

- Acceptance flow: `PoidhV3.acceptClaim()` / `PoidhV3._acceptClaim()` in `src/PoidhV3.sol`
- NFT transfer uses `transferFrom`: `src/PoidhV3.sol` (`poidhNft.transferFrom(...)`)
- NFT minted to escrow via `_mint`: `PoidhClaimNFT.mintToEscrow()` in `src/PoidhClaimNFT.sol`

### 2.2 `cancelOpenBounty()` reentrancy (whitehack)

**Spec’s root cause**: v2 refunded participants in a loop using `.call` without clearing participant slots/amounts until after all calls completed, enabling reentrancy cross-calls and/or double refunds.

**v3 mitigation summary**

- **No refund loop with external calls exists**.
- `cancelOpenBounty()`:
  - closes the bounty immediately (effects),
  - refunds only the issuer’s slot immediately (effects → credit pending),
  - emits event.
- Contributors individually claim refunds after cancellation (`claimRefundFromCancelledOpenBounty()`), which:
  - clears that contributor’s slot and amount (effects),
  - credits `pendingWithdrawals` (effects),
  - does **no external calls**.

This removes both:
- the “refund loop reentrancy” surface, and
- the “gas grief / unbounded loop” DoS risk.

**Implementation references**

- `PoidhV3.cancelOpenBounty()` in `src/PoidhV3.sol`
- `PoidhV3.claimRefundFromCancelledOpenBounty()` in `src/PoidhV3.sol`

### 2.3 Additional concerns listed in the spec

| Spec concern | v3 status | Notes |
|---|---|---|
| Cross-function reentrancy | Mitigated | Pull payments remove most external calls; external-facing state changers are `nonReentrant`. |
| Permissionless `resolveVote()` | Preserved | `resolveVote()` can be called by anyone after the deadline; state machine is robust to caller identity. |
| No minimum bounty amount | Fixed | `MIN_BOUNTY_AMOUNT` enforced on bounty creation. |
| Unbounded arrays / iteration DoS | Mitigated | `MAX_PARTICIPANTS` bounds contributor lists; no participant refund loop exists; pagination helpers exist for reads. |

## Spec Compliance Matrix (v3 requirements)

| Requirement (spec §3.1) | Implemented | Where |
|---|---:|---|
| Reentrancy protection | Yes | `ReentrancyGuard` + `nonReentrant` on external state-changing functions in `src/PoidhV3.sol`. |
| Strict CEI | Yes | All flows do checks → state updates → external calls; most flows have **no external calls** except `withdraw()` and ERC721 `transferFrom`. |
| Solidity ^0.8.20+ + custom errors | Yes | `pragma ^0.8.24` and custom errors in `src/PoidhV3.sol` / `src/PoidhClaimNFT.sol`. |
| Ownable2Step | Yes | `Ownable2Step` used in both contracts. |
| Pull payments | Yes | `pendingWithdrawals` + `withdraw()` in `src/PoidhV3.sol`. |
| Gas limits / bounded iterations | Yes | `MAX_PARTICIPANTS`; cancellation avoids loops; read helpers are paginated. |

## Architecture Notes (spec §3.2)

The spec suggested a separate `PoidhVault` contract. This implementation **inlines** vault behavior into `PoidhV3`:

- `PoidhV3` holds funds (native token) and maintains a ledger `pendingWithdrawals`.
- `withdraw()` is the only generic ETH exit.

Security-wise, this still satisfies the same goals (pull over push), while reducing cross-contract complexity. If you want a separate vault later, the current `pendingWithdrawals` ledger is the natural seam to extract.

## Critical Function Mapping (spec §3.3)

### `_acceptClaim()` (spec §3.3.1)

Matches the spec’s required properties:

- checks `claim.accepted`
- checks `bounty.amount <= balance`
- **zeros `bounty.amount`** before any external interaction
- uses pull payments
- uses `transferFrom` (no ERC721 callback)

### `withdraw()` (spec §3.3.2)

Implements “withdraw pattern” exactly:

- checks amount > 0
- zeros storage
- then `.call{value: amount}("")`
- emits `Withdrawal`

### `withdrawFromOpenBounty()` (spec §3.3.3)

Implemented with:

- contributor slot clearing (address/amount) before crediting pending
- no external calls
- `nonReentrant`

### `cancelOpenBounty()` (spec §3.3.4)

The spec’s example loops over all contributors and credits pending; this implementation instead:

- closes the bounty and refunds the issuer immediately
- requires contributors to claim refunds individually

This is a stricter DoS-resistant design: no single call risks running out of gas due to a large contributor list.

## NFT Contract Considerations (spec §3.5)

This implementation follows the spec’s recommendation to deploy a **fresh v3 claim NFT** contract and to avoid callbacks:

- `PoidhClaimNFT.mintToEscrow()` uses `_mint` (not `_safeMint`).
- `PoidhV3._acceptClaim()` uses `transferFrom` (not `safeTransferFrom`).

## Events (spec “better events”)

The v3 events are intentionally more indexer-friendly:

- Critical IDs and addresses are `indexed` (bountyId, claimId, issuers, voters).
- `ClaimAccepted` includes `bountyAmount`, `payout`, and `fee` for transparent accounting.
- New events added for voting lifecycle and pull-based movements:
  - `VotingStarted`, `VoteCast`, `VotingResolved`
  - `Withdrawal`, `RefundClaimed`

Indexers consuming v2 events must update to the new event schema.

## Testing, Coverage, and Fuzzing (spec §4)

### What exists in this repo

- Unit tests: `test/PoidhV3.unit.t.sol`
- Fuzz tests: `test/PoidhV3.fuzz.t.sol`
- Invariants: `test/PoidhV3.invariant.t.sol`
- Coverage-focused tests (edge paths): `test/PoidhV3.coverage.t.sol`
- Deploy script test (coverage + wiring): `test/Deploy.t.sol`
- NFT tests: `test/PoidhClaimNFT.t.sol`

### Coverage status

Run:

```bash
forge coverage --exclude-tests
```

This repo targets **100% coverage** for source contracts (`src/`) and the deploy script.

### “Hours of fuzzing”

Foundry supports a long-running profile without changing code:

```bash
FOUNDRY_PROFILE=long forge test
```

Profiles are defined in `foundry.toml`:

- default: fuzz runs 256, invariant runs 256, depth 500
- long: fuzz runs 10,000, invariant runs 2,000, depth 1,000

For multi-hour fuzzing, run the `long` profile repeatedly (or increase runs/depth further) and keep the machine stable (disable sleep).

## Deployment Checklist (implementation reality)

Implemented:

- NFT deployed and wired to POIDH via `setPoidh()` (deploy script).
- Ownership can be transferred to a multisig (commented in deploy script).

Recommended before mainnet:

- Run Slither + review any findings.
- Run a long fuzz pass for multiple hours (increase `FOUNDRY_PROFILE=long` parameters as needed).
- Get an external audit focused on: state machine, griefing, tokenURI trust assumptions, and any downstream integrations.

