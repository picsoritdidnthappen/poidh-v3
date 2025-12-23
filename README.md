# POIDH v3 – Secure Rebuild (Foundry)

This is a **security-focused rebuild** of the POIDH v2 bounty contracts (solo + open bounties),
based on the v2 onchain source and the accompanying security specification.

## Quick start

```bash
forge --version
forge install --no-git OpenZeppelin/openzeppelin-contracts
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

## Deploy

Example (edit addresses/params inside the script):

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --private-key <PK> --broadcast --verify
```

Note: `POIDH_START_CLAIM_INDEX` must be `>= 1` (claimId `0` is reserved as a sentinel).

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
