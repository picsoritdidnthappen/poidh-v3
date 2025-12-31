# POIDH v3 Audit Handoff Package

This is the “minimum complete” package we send to external auditors.

## 0) Repository + Commit

- Repo: this repository
- Target commit: **fill in commit hash at handoff time**

Policy:
- Freeze code at the agreed commit.
- Any post-freeze changes must be explicitly communicated, re-diffed, and re-reviewed.

## 1) Scope

In-scope contracts:
- `src/PoidhV3.sol` (core escrow + voting)
- `src/PoidhClaimNFT.sol` (claim NFT minter + escrow transfer target)
- `src/interfaces/IPoidhClaimNFT.sol`

In-scope scripts (recommended):
- `script/Deploy.s.sol` (deployment wiring, ownership transfer flow)

Out-of-scope (unless explicitly requested):
- Frontend, indexers/subgraphs, metadata hosting, UI business logic

## 2) How To Run Locally

Prereqs:
- Foundry installed

Commands:
```bash
forge test
forge coverage --exclude-tests
FOUNDRY_PROFILE=long forge test
```

Optional:
```bash
# Monte Carlo simulations (writes to cache/)
forge script script/Simulate.s.sol:Simulate --sig "runVoting(uint256,uint256,uint256,uint256)" -- 1 1000 25 6000
forge script script/Simulate.s.sol:Simulate --sig "runSlotExhaustion()"
```

## 3) System Overview (Mental Model)

### Contracts

- `PoidhV3`:
  - Holds ETH escrow for bounties (`bounties[bountyId].amount`).
  - Holds claim NFTs in escrow (`PoidhClaimNFT` mints claim NFTs to `PoidhV3`).
  - Uses pull-payments (`pendingWithdrawals` + `withdraw()`).
  - Voting for open bounties uses snapshotted weights at vote start.

- `PoidhClaimNFT`:
  - Minimal ERC721URIStorage.
  - Mints with `_mint` (not `_safeMint`) to avoid ERC721Receiver callback surface.
  - Owner controls which POIDH contract is authorized to mint via `setPoidh()`.

### Invariants we care about

- ETH conservation: total owed via `pendingWithdrawals` + open bounty amounts must never exceed `address(PoidhV3).balance`.
- CEI / reentrancy: state finalized before external interactions; all state-changing externals are `nonReentrant`.
- Voting lifecycle: once vote starts, join/withdraw is blocked via `VotingOngoing` gating; vote weights fixed at snapshot.
- Claim NFT lifecycle: minted to escrow, transferred to bounty issuer only on acceptance.

## 4) Known “By Design” Tradeoffs / Limitations

These are currently documented as *griefing vectors* and may require product decisions:
- “Force voting” via dust join (external contributor flips open-bounty rules)
- Participant cap fill / temporary join blocking (`MAX_PARTICIPANTS`; vacated slots are reused)
- Claim spam (unbounded `createClaim`)

Primary evidence:
- `test/PoidhV3.griefing.t.sol`
- `script/Simulate.s.sol`
- `docs/product/KNOWN_ISSUES.md`

## 5) Specific Auditor Focus Requests

Please pay extra attention to:

1. State machine correctness
   - Bounty cancellation / acceptance / vote resolution interactions
   - Edge cases around “vote state cleared” and re-submission

2. Reentrancy & external interaction ordering
   - `withdraw()` / `withdrawTo()`
   - `PoidhV3._acceptClaim()` ERC721 transfer ordering

3. Economic correctness
   - Fee computation and rounding
   - Accounting for open bounty joins/withdraws/refunds

4. Griefing surface
   - Participant cap fill / slot reuse conditions
   - Storage growth vectors (claims)

## 6) Deliverables We Expect

- Issue list with severity + exploit narrative + recommended fixes
- Code-level patch suggestions (or PR review notes)
- Final report for public release (optional)
