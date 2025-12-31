# POIDH v3 Mainnet Readiness (Plan + Runbooks)

This document is a navigation + decision log for taking this repo from “tested” to “mainnet”.

## Current State (Repo Artifacts)

- Code: `src/PoidhV3.sol`, `src/PoidhClaimNFT.sol`
- Deploy script: `script/Deploy.s.sol`
- Evidence: tests in `test/`, simulations in `script/Simulate.s.sol`
- Internal docs:
  - `docs/POIDH_V3_SECURITY_REPORT.md`
  - `docs/ADMIN_ANALYSIS.md`
  - `docs/SCOPE_OF_WORK.md`

## Phase 1 Independent Audit

Goal: a reputable third-party review (Trail of Bits, OpenZeppelin, Spearbit, Cantina).

Primary handoff doc:
- `docs/audit/AUDIT_HANDOFF.md`

Audit focus (minimum):
- State machine correctness (bounty lifecycle + voting lifecycle)
- Reentrancy & external call ordering
- Economic security / accounting invariants
- Griefing surface (slot exhaustion, claim spam, “force voting”)

## Phase 2 Operational Readiness

Goal: monitoring, key management, and emergency procedures ready before mainnet.

Runbooks:
- Monitoring: `docs/operations/MONITORING.md`
- Emergency procedures: `docs/operations/EMERGENCY_PROCEDURES.md`
- Incident response: `docs/operations/INCIDENT_RESPONSE.md`

Key requirement:
- NFT owner key MUST be recoverable and ideally be a Safe multisig (see `docs/migrations/NFT_REDEPLOYMENT.md`).

## Phase 3 Product Decisions on Known Issues (Pre-Mainnet)

Goal: decide what is “acceptable by design” vs. what must be mitigated in v3.

Decision log lives in:
- `docs/product/KNOWN_ISSUES.md`

## Phase 4 Deployment (Testnet → Mainnet)

Goal: deterministic, repeatable deployment and post-deploy verification.

Checklist + runbook:
- `docs/deployment/TESTNET_TO_MAINNET_CHECKLIST.md`

## Phase 5 Ongoing Security (Post-Mainnet)

Goal: bug bounty + process maturity.

- Bug bounty: `docs/operations/BUG_BOUNTY.md`
- Vulnerability intake: `SECURITY.md`

