# Known Issues & Product Decisions (v3)

This document tracks “known issues” that are *not* straightforward code bugs; they are tradeoffs
in an open system and require product decisions.

Evidence:
- `test/PoidhV3.griefing.t.sol`
- `script/Simulate.s.sol`

## 1) “Force voting” via dust join

### What happens

Once an open bounty ever has a non-issuer contributor, `everHadExternalContributor[bountyId]`
becomes true and the issuer can no longer direct-accept claims (must go through voting).

This can be triggered cheaply by joining with the minimum allowed amount and then withdrawing.

Current parameterization in this repo:
- `MIN_CONTRIBUTION = 0.00001 ether`

### Impact

- Increases time-to-resolution (must do 48h vote flow)
- UX degradation and potential issuer abandonment

### Options

1) Raise minimum join amount
2) Add a join bond (refundable on withdrawal)
3) Allow issuer to “close funding” after a delay
4) Change state machine: only require voting if there is *active* external stake

### Decision (TBD)

- Chosen mitigation:
- Parameter values (if any):
- Rationale:

## 2) Participant slot exhaustion

### What happens

`MAX_PARTICIPANTS` caps `participants[bountyId].length` (including the issuer at index `0`).
Withdrawn/refunded participants leave holes (`address(0)`), but v3 tracks vacated indices in a
free-list (`freeParticipantSlots`) and **reuses them for new joins**.

This means the “permanent hole exhaustion” problem is mitigated: if users withdraw, new addresses
can still join by reusing empty slots even though the array length stays at `MAX_PARTICIPANTS`.

### Impact

- Locks out legitimate contributors (open bounty becomes effectively closed to new participants)

### Options

Remaining griefing surface:
- An attacker can still fill *all* slots by keeping capital locked (up to `MAX_PARTICIPANTS - 1`
  external addresses), temporarily blocking new joins until they withdraw/cancel/resolve.

Options:
1) Require higher minimum join amount increases the cost to occupy all slots
2) Add a join bond (refundable) adds real economic cost to occupying slots
3) Allow issuer “close funding” window product/UX change
4) Raise cap increases gas and DoS surface

### Decision (Current expectation)

- Treat as v4-level change unless product decides otherwise.

## 3) Claim spam (unbounded createClaim)

### What happens

Anyone (except the issuer) can create unlimited claims on any active bounty.

### Impact

- Storage growth (claims array + bountyClaims array)
- Indexer / UI degradation
- Issuer overload

### Options

1) Issuer “close submissions” switch per bounty
2) Claim bond (refundable on acceptance)
3) Per-bounty claim cap
4) UI-only throttling (helps UX but not onchain state growth)

### Decision (TBD)

- Chosen mitigation:
- Rationale:
