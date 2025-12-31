# Incident Response Plan

This is the process document; for “what to do right now”, see:
- `docs/operations/EMERGENCY_PROCEDURES.md`

## Severity Rubric

| Severity | Definition | Examples |
|---|---|---|
| Critical | funds at risk or confirmed loss | theft vector, permanent lock, `setPoidh` hijack |
| High | protocol-wide breakage / severe liveness impact | claim acceptance broken, mass stuck withdrawals |
| Medium | degraded UX / griefing at scale | claim spam wave, participation DoS |
| Low | minor bug or informational | UI edge case, docs issue |

## Roles (Fill In Before Mainnet)

- Incident commander:
- Onchain lead (contracts / Foundry):
- Ops lead (monitoring / infra):
- Comms lead (public updates):
- Multisig coordinator:

## Workflow

### 1) Detect

Inputs:
- Defender/Tenderly alerts
- user reports
- researcher disclosure (see `SECURITY.md`)

### 2) Triage

- Confirm chain/network + contract address.
- Identify affected functionality (create/join/claim/vote/withdraw).
- Determine blast radius (single bounty vs global).

### 3) Contain

- Freeze UI flows.
- If applicable, execute `PoidhClaimNFT.setPoidh()` to halt/migrate claim minting.
- Provide user instructions for safe exit (cancel + withdraw).

### 4) Eradicate / Fix

- Patch in a new contract version (no upgrades assumed).
- Validate with tests + (ideally) fork test.
- Deploy to testnet first, then mainnet with standard checklist.

### 5) Recover

- Update UI to new addresses.
- Monitor for recurrence.
- Publish final status + next steps.

### 6) Postmortem

Create a postmortem within 72h:
- timeline
- root cause
- detection gaps
- action items (code + process)

## Comms Cadence (Suggested)

- Critical/High: initial notice within 30 minutes, updates every 2–4 hours until resolved.
- Medium: initial notice within 4 hours, daily updates until resolved.

