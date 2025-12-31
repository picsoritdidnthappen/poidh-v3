# POIDH v3 – Secure Rebuild (Foundry)

This is a **security-focused rebuild** of the POIDH v2 bounty contracts (solo + open bounties),
based on the v2 onchain source and the accompanying security specification.

## Quick start

```bash
forge --version
forge test -vvv
```

## Testing & fuzzing

```bash
# Unit + fuzz + invariants
forge test

# EXTENSIVE (very slow)
FOUNDRY_PROFILE=long forge test

# EXTENSIVE (override profile; very slow)
FOUNDRY_FUZZ_RUNS=10000 FOUNDRY_INVARIANT_RUNS=2000 FOUNDRY_INVARIANT_DEPTH=1000 forge test

# Optional mainnet-fork smoke test (skips if FORK_URL not set)
FORK_URL=<RPC_URL> forge test --match-contract PoidhV3ForkTest
```

## Coverage

```bash
forge coverage --exclude-tests
```

## Security report

- `docs/POIDH_V3_SECURITY_REPORT.md`
- `docs/README.md` (docs index)
- `docs/MAINNET_READINESS.md` (audit → ops → deployment plan)
- `SECURITY.md` (vulnerability reporting)

## Deploy

Example (edit addresses/params inside the script):

```bash
export POIDH_TREASURY=0x...
export POIDH_START_CLAIM_INDEX=1
# optional
export POIDH_MULTISIG=0x...
export POIDH_NFT_NAME="poidh claims v3"
export POIDH_NFT_SYMBOL="POIDH3"

forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --private-key <PK> --broadcast --verify
```

Note: `POIDH_START_CLAIM_INDEX` must be `>= 1` (claimId `0` is reserved as a sentinel).

## Simulations

Monte Carlo voting simulations (writes results under `cache/simulations/`):

```bash
# args: seed runs participants yesBps(0..10000)
forge script script/Simulate.s.sol:Simulate --sig "runVoting(uint256,uint256,uint256,uint256)" -- 1 1000 25 6000

# Demonstrate participant cap + slot reuse behavior
forge script script/Simulate.s.sol:Simulate --sig "runSlotExhaustion()"
```

## Key security changes (high level)

- ReentrancyGuard on all state-changing external functions.
- Strict CEI (checks/effects/interactions).
- **Pull payments**: all ETH/DEGEN value exits the contract via `withdraw()`.
- `bounty.amount` is zeroed on acceptance; `claim.accepted` is enforced.
- ERC721 callback vector removed by using `transferFrom` and an NFT that mints with `_mint` (not `_safeMint`).

## Compatibility notes

- The public structs and most function names match PoidhV2 (`createSoloBounty`, `createOpenBounty`, `joinOpenBounty`, etc.).
- Cancellation for open bounties is **constant-time**: it marks the bounty cancelled; contributors claim refunds individually via `claimRefundFromCancelledOpenBounty`, then call `withdraw()`.
- `resetVotingPeriod` is kept but **cannot** be used to discard a winning vote.

## License

MIT
