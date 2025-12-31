# Emergency Procedures (No Onchain Pause)

POIDH v3 has no admin pause and no “sweep” function by design. Emergency response is therefore:

1) **coordination + communication**, and
2) using the *limited levers that do exist* (notably `PoidhClaimNFT.setPoidh()`), and
3) helping users move funds using normal flows (cancel + withdraw).

## Emergency Levers (What You Can Actually Do)

### Onchain levers

- `PoidhClaimNFT.setPoidh(newPoidh)` (owner-only)
  - Can **stop new claim creation** in the current PoidhV3 by pointing `poidh` away from it.
  - Can migrate mint authority to a patched Poidh contract.

Notes:
- `setPoidh(address(0))` is rejected; plan a “shutdown” address if you need to halt minting.
- This lever exists only if the NFT owner key is accessible (prefer a Safe multisig).

### Offchain levers

- Pause/disable frontend flows (create/join/claim/accept).
- Pin incident banner + force acknowledgements.
- Coordinate comms (Discord/Twitter/blog) with clear user instructions.
- Rate-limit / gate claim submission in the UI (mitigates “claim spam” even if onchain allows it).

## Immediate Response Checklist (First 60 Minutes)

- [ ] Triage: confirm if issue is real (repro tx, chain data, logs).
- [ ] Classify severity (see `docs/operations/INCIDENT_RESPONSE.md`).
- [ ] Freeze UI (at minimum: disable “create bounty” and “create claim”).
- [ ] Notify core team + multisig signers.
- [ ] Decide whether to use `setPoidh` (halt claims vs migrate).
- [ ] Draft public message with concrete user actions (cancel bounties / withdraw).

## User Fund Safety Guidance (If Funds May Be At Risk)

Because funds are escrowed in `PoidhV3`, the safest “get funds out” path is via normal flows:

- Issuers:
  - Cancel solo bounties via `cancelSoloBounty(bountyId)`
  - Cancel open bounties via `cancelOpenBounty(bountyId)`
  - Then withdraw credited funds via `withdraw()` / `withdrawTo()`

- Contributors (open bounties):
  - If issuer cancels: `claimRefundFromCancelledOpenBounty(bountyId)` then `withdraw()`
  - If not voting: `withdrawFromOpenBounty(bountyId)` then `withdraw()`

## Suggested “Stop Claim Minting” Action (If Needed)

If the incident involves claim creation (spam, malformed NFTs, mint-bug), you can stop new claim
mints by moving mint authority away from the active contract:

```bash
cast send $POIDH_NFT "setPoidh(address)" $NEW_POIDH_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $MULTISIG_EXECUTOR_PK
```

Operational note:
- Prefer executing this via the Safe multisig UI rather than a raw private key.

