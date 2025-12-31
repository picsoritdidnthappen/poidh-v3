# POIDH v3 Full Security Review, Known Vectors, and v2 Comparison

This document is a security-focused, implementation-level review of the v3 contracts in this repository:

- what happened in the v2 exploit class (Dec 8, 2025),
- what was changed in v3 (code + architecture),
- which attack vectors are mitigated (with test evidence),
- which vectors remain (economic griefing / liveness / MEV / admin risk), and
- how v3 differs from the exploited v2 design described in the POIDH v3 rebuild spec.

It is **not** a professional audit.

## Key Links (external)

- Original exploit TX (Base): https://basescan.org/tx/0x0545a4e5800632ba2194fb9349264ff7f3d3bb18d28ee168d57369b14422f11f
- Whitehack TX (Base): https://basescan.org/tx/0xdd1cb64cded3abcd5078773d7d6075780674c052a83a3d22b9c7f9538b1178b3
- Post-mortem: https://words.poidh.xyz/poidh-december-8th-exploit
- v2 repo: https://github.com/picsoritdidnthappen/poidh-contracts

## Scope (what this doc covers)

Contracts:

- `src/PoidhV3.sol` (bounty creation, funding, voting, claim acceptance, pull payments)
- `src/PoidhClaimNFT.sol` (claim NFT minted to escrow, transferred without callback)

Evidence:

- Unit tests and red-team tests in `test/`
- Fuzzing/invariants configured in `foundry.toml`
- Monte Carlo simulation harness in `script/Simulate.s.sol` (writes to `cache/simulations/`)

This doc does **not** review offchain UI/indexers, NFT metadata hosting, or deployment operations beyond footguns and trust assumptions.

## Glossary / mental model

- **Bounty issuer**: the creator/funder of a bounty.
- **Solo bounty**: only the issuer funds; issuer accepts claims directly.
- **Open bounty**: multiple contributors; claim acceptance is normally via voting.
- **Claim issuer**: address submitting a claim (mints a claim NFT).
- **Escrow**: v3 holds funds and claim NFTs in the `PoidhV3` contract until resolution.
- **Pull payments**: ETH is never “pushed” to arbitrary recipients inside core flows; it is credited to `pendingWithdrawals` and later claimed via `withdraw()` / `withdrawTo()`.

## What happened in v2 (high level)

The v2 exploit class described in the spec (and reproduced in `test/PoidhV3.attack.t.sol`) centered on **reentrancy during external calls** combined with **incomplete state finalization**:

1. **ERC721 callback reentrancy during claim acceptance (blackhat theft)**
   - v2 transferred/moved the claim NFT using `safeTransfer*` to an issuer that might be a contract.
   - That transfer invoked an `onERC721Received` callback on the issuer contract.
   - During the callback, the attacker re-entered the acceptance path while the bounty’s balance/state was not fully finalized.
   - Root causes (per spec): missing “claim already accepted” check and failing to zero the bounty amount before external interactions.

2. **Refund-loop reentrancy during open-bounty cancellation (whitehack rescue)**
   - v2 refunded participants by iterating and performing `.call{value: ...}("")` in a loop.
   - Participant accounting was not cleared before the external call(s), and the bounty was not marked closed until after the loop.
   - A malicious participant could re-enter and trigger cross-function interactions leading to double refunds.

The v3 rebuild focuses on removing the entire class of “external callbacks before state finalization” and “push-based refunds in loops”.

## v3 architecture and design goals

v3 (as implemented here) preserves the protocol’s core behavior (solo bounties, open bounties, voting, 2.5% fee) while enforcing modern Solidity safety properties:

### Design invariants v3 aims to enforce

1. **Checks-Effects-Interactions (CEI)**: all state is finalized before interacting with untrusted code.
2. **ReentrancyGuard on state-changers**: all external, state-changing entrypoints are `nonReentrant`.
3. **Pull payments**: the only generic ETH exits are `withdraw()` / `withdrawTo()`.
4. **ERC721 callbacks avoided**:
   - `PoidhClaimNFT` mints with `_mint` (not `_safeMint`)
   - `PoidhV3` transfers claim NFTs with `transferFrom` (not `safeTransferFrom`)

### Core mechanics preserved (vs. v2 product behavior)

- **Solo bounties**: issuer funds and later accepts a claim directly.
- **Open bounties**: issuer funds, others may contribute (up to a cap), claims are accepted via voting.
- **Voting**: default 48h period, >50% by weight to pass.
- **Fee**: 2.5% (`FEE_BPS = 250`) routed to immutable `treasury` (withdraws via pull payments).

### Deliberate behavior changes in v3 (vs. v2 described in the spec)

1. **All value movement is pull-based** (`pendingWithdrawals` + `withdraw()` / `withdrawTo()`).
2. **Open bounty cancellation is constant-time**:
   - issuer refund happens immediately,
   - contributors claim refunds individually (`claimRefundFromCancelledOpenBounty()`).
3. **Claim NFTs are escrowed**: minted to `PoidhV3`, transferred to bounty issuer only upon acceptance.
4. **Once external funding happens, voting is always required**:
   - `everHadExternalContributor[bountyId]` prevents “withdraw-to-solo then direct accept”.
   - This closes a correctness hole but introduces an intentional griefing tradeoff (see “Known vectors”).
5. **ClaimId `0` is reserved as a sentinel**:
   - `bountyCurrentVotingClaim[bountyId] == 0` means “no active vote”.
   - The constructor requires a non-zero `_startClaimIndex` so real claim IDs start at `>= 1` (indexer footgun if assumed otherwise).

## v2 vs v3 comparison matrix (what changed and why)

This table compares the exploited v2 design described in the spec to v3 as implemented in this repo.

| Area | v2 (spec-described) | v3 (this repo) | Security impact |
|---|---|---|---|
| Claim acceptance external calls | `safeTransfer*` used in acceptance (ERC721 callback surface) | `transferFrom` used; NFT minted with `_mint` | Removes ERC721 callback reentrancy vector |
| Acceptance state finalization | Incomplete (per spec): bounty amount not zeroed; accepted flag not enforced on entry | `bounty.amount = 0` and `claim.accepted = true` set before any external interaction | Prevents replay/recursive payout |
| Value transfers | Push-based `.call{value: ...}` in multiple flows (accept, cancel) | Pull-only via `pendingWithdrawals` + `withdraw()` / `withdrawTo()` | Greatly reduces interaction surface |
| Open bounty cancel refunds | Refund loop with external calls | No external refund loop; issuer refunded, contributors self-claim refunds | Eliminates loop reentrancy + gas-limit DoS |
| Voting double-vote prevention | Typical patterns require looping/resetting `hasVoted` | `voteRound` + `lastVotedRound` mapping | No O(n) resets; prevents double voting per round |
| Voting liveness | Resolution might be issuer-only (varies by design) | Permissionless `resolveVote()` | Removes “issuer must be online” dependency |
| Minimum bounty amount | No minimum (per spec concern) | Enforced `MIN_BOUNTY_AMOUNT` on bounty creation | Reduces dust spam of bounties |
| Participant growth | Unbounded arrays (spec concern) | `MAX_PARTICIPANTS` cap; vacated slots are reused | Bounds contributor list size; “cap fill” griefing still exists while capital is locked |
| Treasury configuration | Often mutable | Immutable `treasury` | Reduces governance/upgrade risk; increases misconfig risk |
| Vote state representation | Typically separate boolean state | `bountyCurrentVotingClaim==0` sentinel; claimId `0` reserved | Simplifies vote-state checks; introduces deploy/indexer footgun |

## Spec compliance (quick map)

This repo was built to match the POIDH v3 rebuild spec’s *security properties* (even where the architecture differs).

| Spec requirement | Implemented | Where / notes |
|---|---:|---|
| Reentrancy protection | Yes | `ReentrancyGuard` + `nonReentrant` on state-changing entrypoints in `src/PoidhV3.sol` |
| Strict CEI | Yes | State is finalized before external calls; most flows have no external calls |
| Pull payments | Yes | `pendingWithdrawals` + `withdraw()` / `withdrawTo()` in `src/PoidhV3.sol` |
| Bounded iteration / gas safety | Partial | `MAX_PARTICIPANTS` caps participants; cancellation avoids refund loops; claim spam remains possible |
| Ownable2Step | Partial | `PoidhClaimNFT` uses `Ownable2Step` (for `setPoidh()` ownership). `PoidhV3` has no owner/admin surface. |
| NFT callback avoidance | Yes | `_mint` + `transferFrom` in `src/PoidhClaimNFT.sol` / `src/PoidhV3.sol` |

Note: the spec suggested a separate vault; this implementation keeps escrow + ledger inside `PoidhV3` to reduce cross-contract complexity.

## v2 exploit vectors (theft-class) and how v3 blocks them

These are vectors that lead to theft in v2 (per spec) and are explicitly tested in v3.

| Vector | v2 risk | v3 mitigation | Evidence |
|---|---|---|---|
| ERC721 callback reentrancy on accept | Callback re-enters while bounty not finalized | Finalize state first + `transferFrom` + `_mint` | `test/PoidhV3.attack.t.sol` (`test_attack_erc721_callback_reentrancy_BLOCKED`) |
| Refund-loop reentrancy on cancelOpenBounty | Loop sends ETH before clearing state | No ETH sends in loop; contributor refunds are pull-claimed | `test/PoidhV3.attack.t.sol` (`test_attack_cancel_loop_reentrancy_BLOCKED`) |
| Cross-function reentrancy | Re-enter different function during callback/receive | Pull payments + `nonReentrant` on state-changers | `test/PoidhV3.attack.t.sol` (`test_attack_cross_function_reentrancy_BLOCKED`) |
| Withdraw reentrancy | Re-enter withdraw during ETH receive | `withdraw()` is `nonReentrant` and zeroes first | `test/PoidhV3.attack.t.sol` (`test_attack_withdraw_reentrancy_BLOCKED`) |
| Replay accepted claim | Accept same claim twice | `ClaimAlreadyAccepted` enforced | `test/PoidhV3.attack.t.sol` (`test_attack_replay_accepted_claim_BLOCKED`) |
| Accept claim on finalized bounty | Accept after bounty closed/claimed | `bountyChecks`/state guards | `test/PoidhV3.attack.t.sol` (`test_attack_claim_on_finalized_bounty_BLOCKED`) |
| Double vote in same round | Vote twice | `voteRound` + `lastVotedRound` | `test/PoidhV3.attack.t.sol` (`test_attack_double_vote_BLOCKED`) |
| Withdraw during voting | Withdraw to change weight mid-vote | `bountyChecks` blocks withdrawals while voting | `test/PoidhV3.attack.t.sol` (`test_attack_withdraw_during_voting_BLOCKED`) |
| Accept unauthorized | Non-issuer tries to accept | `WrongCaller` checks | `test/PoidhV3.attack.t.sol` (`test_attack_frontrun_claim_acceptance`) |

### Why v3’s approach works (the important part)

v3 does not rely on a single fix; it removes the entire “reenter while value exists” class by combining:

1. **State finalization before interactions**
2. **No ETH sends during business logic** (pull-only)
3. **No ERC721 receiver callbacks** (mint + transfer choices)
4. **ReentrancyGuard at all state-changing entrypoints**

## Known vectors that remain (non-theft): griefing, liveness, and MEV

These are real, expected risks in an open system. They don’t typically allow theft, but they can harm UX, liveness, or fairness.

### Confirmed griefing / DoS vectors

| Vector | Cost to attacker | Impact | Current status | Possible mitigations (tradeoffs) |
|---|---:|---|---|---|
| Minimum-contribution “force voting” | `MIN_CONTRIBUTION` + gas (principal recoverable) | Flips `everHadExternalContributor=true` forever; issuer can’t direct-accept | Confirmed (`test/PoidhV3.griefing.t.sol`) | Product decision: raise `MIN_CONTRIBUTION`, add refundable join bond, or allow issuer “close funding” window |
| Participant cap fill / temporary join blocking | `(MAX_PARTICIPANTS-1)*MIN_CONTRIBUTION` + gas (principal recoverable) | Blocks new joins while all slots are occupied | Confirmed (`test/PoidhV3.griefing.t.sol`, `script/Simulate.s.sol`) | Higher min join, join bond, close-funding window, or raise cap (more DoS surface) |
| Claim spam | Gas only | Unlimited claims bloat storage/indexers; can make UI unusable | Confirmed (`test/PoidhV3.griefing.t.sol`) | Claim bond; per-bounty claim cap; issuer “close submissions” switch; require minimum claim metadata constraints |
| Join-before-vote MEV | Must lock ETH | Attacker joins right before issuer starts vote, swings weight | Confirmed (`test/PoidhV3.griefing.t.sol`) | Snapshot-at-start is already implemented; remaining mitigation requires a product change (close-funding window / delay / bond) |

### MEV / timing and fairness

| Vector | Impact | Notes |
|---|---|---|
| Permissionless `resolveVote()` timing | Bots can resolve immediately after deadline | Usually acceptable; improves liveness |
| Whale dominance | 1 address can dominate voting by funding | This is inherent in 1p1v-by-weight; mitigations change product behavior (e.g., quadratic voting) |

### Self-DOS and edge-case risks

| Risk | Impact | Notes / mitigations |
|---|---|---|
| Receiver reverts on `withdraw()` | Funds stay pending forever for that contract | `withdrawTo(address payable)` is implemented to route to an EOA (caller-controlled) |
| Claim NFT “sink” issuers | Issuer is a contract that can’t transfer/handle NFTs | Mitigated: bounty creation is EOA-only (`msg.sender == tx.origin`) |
| Extra ETH sent to contract | Unattributed ETH could break accounting assumptions | Mitigated: `PoidhV3.receive()` reverts (`DirectEtherNotAccepted`) |

## Admin / trust / “open system” considerations

v3 reduces governance surface, but it is not “fully trustless” because the claim NFT contract has an owner that can rewire the authorized minter.

### Admin powers in this repo

| Control | Where | Power | Risk | How to minimize centralization |
|---|---|---|---|---|
| `setPoidh()` | `src/PoidhClaimNFT.sol` | Can change which POIDH contract can mint | Can brick claim creation; can mint from new POIDH | Transfer NFT ownership to multisig and/or renounce after wiring |

### What admin cannot do (in this design)

- There is no “admin withdraw” or “sweep user funds” path in `PoidhV3`.
- Funds can always exit via `cancel*`/`claimRefund*`/`withdraw()` / `withdrawTo()`.
- `treasury` is immutable (but that creates a deploy footgun).

## Tests, fuzzing, invariants, and simulations (evidence, not proof)

### Test suite overview

Test coverage is organized into these suites (see `forge test --summary` for current counts):

| Test Suite | Focus |
|---|---|
| `test/PoidhV3.unit.t.sol` | Core functionality |
| `test/PoidhV3.t.sol` | End-to-end happy paths |
| `test/PoidhV3.attack.t.sol` | v2 exploit reproduction (blocked) |
| `test/PoidhV3.griefing.t.sol` | Economic griefing & edge cases |
| `test/PoidhV3.coverage.t.sol` | Defensive branches + error paths |
| `test/PoidhV3.fuzz.t.sol` | Parameterized fuzzing |
| `test/PoidhV3.invariant.t.sol` | Stateful fuzzing / invariants |
| `test/PoidhClaimNFT.t.sol` | NFT contract |
| `test/Deploy.t.sol` | Deployment wiring |

### Attack test matrix (v2 exploit reproduction + security checks)

The most direct “what can go wrong” list lives in `test/PoidhV3.attack.t.sol`. Summary:

| Test | Vector / intent | v3 outcome |
|---|---|---|
| `test_attack_erc721_callback_reentrancy_BLOCKED` | ERC721 receiver callback reentrancy in acceptance | Blocked |
| `test_attack_cancel_loop_reentrancy_BLOCKED` | Refund-loop reentrancy on cancelOpenBounty | Blocked (no looped sends) |
| `test_attack_cross_function_reentrancy_BLOCKED` | Re-enter different function during callback | Blocked |
| `test_attack_withdraw_reentrancy_BLOCKED` | Re-enter `withdraw()` during ETH receive | Blocked |
| `test_attack_double_vote_BLOCKED` | Vote twice in same round | Blocked |
| `test_attack_withdraw_during_voting_BLOCKED` | Withdraw contribution during active vote | Blocked |
| `test_attack_replay_accepted_claim_BLOCKED` | Accept same claim twice | Blocked |
| `test_attack_claim_on_finalized_bounty_BLOCKED` | Create/accept claim after bounty finalized | Blocked |
| `test_nft_uses_transferFrom_not_safeTransferFrom` | Ensure NFT transfer does not invoke ERC721Receiver | Verified |
| `test_attack_frontrun_claim_acceptance` | Non-issuer tries to accept claim | Blocked |
| `test_attack_spam_claims_griefing` | Claim spam as a griefing vector | Documented (possible) |
| `test_attack_fee_overflow` | Large amount fee math | Safe |
| `test_attack_zero_amount_edge_cases` | Zero/dust amount edge cases | Blocked |
| `test_attack_issuer_self_claim` | Issuer claims own bounty | Blocked |
| `test_attack_claim_nonexistent_bounty` | Claim on invalid bountyId | Blocked |
| `test_attack_accept_nonexistent_claim` | Accept invalid claimId | Blocked |
| `test_attack_vote_weight_manipulation` | Withdraw/rejoin manipulation around voting | Blocked |
| `test_attack_early_vote_resolution` | Resolve vote before deadline | Blocked |
| `test_attack_dos_max_participants` | Fill participant slots to cap | Enforced |

### Griefing/edge-case matrix (known limitations)

The “open-system” limitations are intentionally documented in `test/PoidhV3.griefing.t.sol`:

| Test | Vector / intent | Finding |
|---|---|---|
| `test_GRIEFING_minContribution_forces_voting` | Minimum join flips `everHadExternalContributor` forever | Confirmed griefing |
| `test_GRIEFING_join_before_vote_frontrun` | Join immediately before vote start | Confirmed griefing / MEV |
| `test_NO_PAUSE_contract_not_pausable` | No admin pause exists | Verified |
| `test_FOOTGUN_wrong_treasury_permanent_loss` | Immutable treasury misconfig | Confirmed footgun |
| `test_EDGE_CASE_contracts_cannot_create_bounties` | Contracts cannot create bounties | Verified |
| `test_DOS_claim_spam` | Spam claims (storage/indexer bloat) | Confirmed DoS vector |
| `test_DOS_participant_slot_exhaustion` | Fill participant slots to cap (while occupied) | Confirmed DoS vector |
| `test_SELF_DOS_receiver_revert` | Receiver reverts on withdraw | Self-DoS (funds stuck pending) |
| `test_MEV_vote_resolution_timing` | Permissionless resolve timing | Acceptable / informational |
| `test_EDGE_CASE_issuer_contribution_matters` | Issuer cannot withdraw from open bounty | Verified |
| `test_EDGE_CASE_vote_weight_after_withdraw` | Withdrawn contributors can’t vote | Verified |
| `test_EDGE_CASE_multiple_claims_accept_any` | Issuer can accept any valid claim | Verified |

Run everything:

```bash
forge test -vvv
```

### Fuzzing & invariants profiles

Profiles are defined in `foundry.toml`:

- default: fuzz runs 256, invariant runs 256, depth 500
- long: fuzz runs 10,000, invariant runs 2,000, depth 1,000
- overnight: fuzz runs 100,000, invariant runs 50,000, depth 10,000 (very slow)

Run long fuzzing / invariants:

```bash
FOUNDRY_PROFILE=long forge test
```

What the invariants assert (high-level):

- **No “ghost payouts”**: if a bounty is claimed, it is finalized (`amount == 0`), the claim is marked accepted, and the NFT is delivered to the bounty issuer.
- **Escrow accounting consistency**: for *active* open bounties, `bounty.amount` matches the sum of `participantAmounts`.
- **Voting state consistency**: vote trackers are either fully empty (no active vote) or reference a real, unaccepted claim for that bounty.
- **No pending withdrawals to `address(0)`**: prevents accidental crediting to the zero address.

### Coverage (high signal for missed branches)

```bash
forge coverage --exclude-tests
```

### Monte Carlo simulations

The simulation script runs many “toy” voting rounds and writes JSONL + a summary to `cache/simulations/`:

```bash
# args: seed runs participants yesBps(0..10000)
forge script script/Simulate.s.sol:Simulate --sig "runVoting(uint256,uint256,uint256,uint256)" -- 1 1000 25 6000

forge script script/Simulate.s.sol:Simulate --sig "runSlotExhaustion()"
```

This is not a replacement for formal verification, but it is a good way to sanity-check outcomes and explore design tradeoffs (vote thresholds, weight distributions, sybil scenarios).

## Production readiness (practical checklist)

If “production ready” includes not just theft-safety but also acceptable liveness/fairness for an open system, the remaining decisions are mostly **product/security tradeoffs**:

1. Decide whether to mitigate:
   - minimum-contribution “force voting”,
   - claim spam,
   - participant cap fill / temporary join blocking,
   - join-before-vote MEV.
2. Decide the governance stance:
   - multisig + timelock (recommended),
   - eventual ownership renounce for `PoidhClaimNFT` (optional, but makes incident response harder).
3. Run static analysis (Slither) + long fuzzing repeatedly; then get an external audit focused on:
   - state machine correctness,
   - griefing/liveness,
   - metadata/URI assumptions,
   - integration surfaces (frontends/indexers).
