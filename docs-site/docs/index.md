---
page: true
---

# POIDH v3 Documentation

A **security-focused rebuild** of the POIDH v2 bounty contracts featuring solo and open bounties with weighted voting and pull-payments.

## Overview

POIDH v3 is a decentralized bounty protocol built on Ethereum that enables:

- **Solo Bounties**: Direct issuer-claimant relationships with immediate acceptance
- **Open Bounties**: Multi-contributor funding with community-driven voting
- **Weighted Voting**: Contribution-weighted decision making
- **Pull Payments**: Secure withdrawal system preventing reentrancy attacks
- **Claim NFTs**: Non-fungible tokens representing bounty claims

## Key Security Improvements

::: tip Security First
v3 addresses critical vulnerabilities from v2 through architectural improvements including ReentrancyGuard, strict CEI patterns, pull-based payments, and callback-free NFT transfers.
:::

## Quick Start

```bash
# Install dependencies
forge install

# Run tests
forge test -vvv

# Run coverage
forge coverage --exclude-tests

# Deploy (configure environment variables first)
forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast
```

## Architecture Highlights

```
┌─────────────────────────────────────────────────────────────┐
│                      PoidhV3 Contract                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Solo Bounties│  │Open Bounties │  │  Claim NFTs  │      │
│  │              │  │              │  │              │      │
│  │ • Create     │  │ • Create     │  │ • Mint       │      │
│  │ • Claim      │  │ • Contribute │  │ • Escrow     │      │
│  │ • Accept     │  │ • Vote       │  │ • Transfer   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Pull Payment System (Withdrawals)           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps

- Explore the [architecture](/architecture) to understand the system design
- Review [state machines](/state-machines) for protocol flows
- Study [security considerations](/security) for threat models
- Check the [API reference](/api) for contract interfaces
