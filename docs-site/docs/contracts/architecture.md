# Architecture

## System Overview

POIDH v3 is a smart contract system that manages bounty creation, funding, claiming, and resolution through two primary bounty types: **solo** and **open**.

## Core Components

```mermaid
graph TB
    subgraph "PoidhV3 Core Contract"
        A[Bounty Manager]
        B[Claim Manager]
        C[Voting Engine]
        D[Payment System]
        E[NFT Escrow]
    end
    
    subgraph "External Systems"
        F[Users]
        G[PoidhClaimNFT]
        H[Treasury]
    end
    
    F --> A
    F --> B
    A --> E
    B --> E
    E --> G
    C --> D
    D --> F
    D --> H
    
    style A fill:#4f46e5
    style B fill:#7c3aed
    style C fill:#2563eb
    style D fill:#059669
    style E fill:#dc2626
```

## Data Structures

### Bounty

```solidity
struct Bounty {
    uint256 id;              // Unique identifier
    address issuer;          // Creator address
    string name;             // Bounty name
    string description;      // Details
    uint256 amount;          // Total funding (wei)
    address claimer;         // 0=active, issuer=cancelled, other=accepted
    uint256 createdAt;       // Timestamp
    uint256 claimId;         // Accepted claim ID
}
```

### Claim

```solidity
struct Claim {
    uint256 id;              // Unique identifier
    address issuer;          // Claimant address
    uint256 bountyId;        // Associated bounty
    address bountyIssuer;    // Bounty creator
    string name;             // Claim name
    string description;      // Details
    uint256 createdAt;       // Timestamp
    bool accepted;           // Acceptance status
}
```

### Votes

```solidity
struct Votes {
    uint256 yes;             // Total YES votes (weighted)
    uint256 no;              // Total NO votes (weighted)
    uint256 deadline;        // Voting end timestamp
}
```

## System Flows

### Solo Bounty Flow

```mermaid
sequenceDiagram
    participant I as Issuer
    participant C as Claimant
    participant P as PoidhV3
    participant N as NFT Contract
    
    I->>P: createSoloBounty()
    Note over I,P: Deposit ETH
    P->>P: Mint bounty NFT to issuer
    
    C->>P: claimSoloBounty(bountyId)
    C->>N: Mint claim NFT
    N->>P: Transfer to escrow
    P->>P: Lock claim NFT
    
    I->>P: acceptSoloClaim(bountyId, claimId)
    P->>P: Update bounty.claimer
    P->>P: Set bounty.amount = 0
    P->>P: Set claim.accepted = true
    P->>P: Credit claimant withdrawals
    
    C->>P: withdraw()
    P->>C: Send ETH
    P->>I: returnClaimNFTToIssuer()
    N->>I: Transfer claim NFT
```

### Open Bounty Flow

```mermaid
sequenceDiagram
    participant I as Issuer
    participant C1 as Contributor 1
    participant C2 as Contributor 2
    participant Cl as Claimant
    participant P as PoidhV3
    
    I->>P: createOpenBounty()
    Note over I,P: Deposit initial ETH
    
    C1->>P: joinOpenBounty(bountyId)
    Note over C1,P: Deposit contribution
    P->>P: Add to participants[]
    
    C2->>P: joinOpenBounty(bountyId)
    Note over C2,P: Deposit contribution
    
    Cl->>P: claimOpenBounty(bountyId)
    Note over Cl,P: Mint & lock claim NFT
    
    P->>P: Start voting period
    
    loop Voting Phase
        C1->>P: vote(bountyId, claimId, true)
        Note over C1,P: Weight = contribution
        C2->>P: vote(bountyId, claimId, false)
    end
    
    P->>P: Tally votes
    alt Yes > No
        P->>P: Accept claim
        P->>P: Credit claimant
        P->>P: Credit all contributors
    else No >= Yes
        P->>P: Reject claim
        P->>P: Unlock claim NFT
    end
```

## Key Design Patterns

### 1. Checks-Effects-Interactions (CEI)

All external functions follow strict CEI ordering:

```solidity
function example() external nonReentrant {
    // 1. CHECKS
    require(condition, "error");
    
    // 2. EFFECTS
    stateVariable = newValue;
    emit Event();
    
    // 3. INTERACTIONS
    externalCall();
}
```

### 2. Pull Payments

No direct ETH transfers to users:

```solidity
// Instead of:
payable(recipient).transfer(amount);

// We use:
pendingWithdrawals[recipient] += amount;
// User calls withdraw() later
```

### 3. NFT Escrow

Claim NFTs are held in-contract:

```solidity
// Mint directly to contract
poidhNft.mint(address(this), ...);

// Transfer without callback
poidhNft.transferFrom(address(this), recipient, tokenId);
```

## Storage Layout

```
┌─────────────────────────────────────────────┐
│         State Variables                     │
├─────────────────────────────────────────────┤
│ Bounty[] bounties                           │
│ Claim[] claims                              │
│ uint256 bountyCounter                       │
│ uint256 claimCounter                        │
├─────────────────────────────────────────────┤
│         Mappings                            │
├─────────────────────────────────────────────┤
│ userBounties[address] → bountyIds[]         │
│ userClaims[address] → claimIds[]            │
│ bountyClaims[bountyId] → claimIds[]         │
│ participants[bountyId] → addresses[]        │
│ participantAmounts[bountyId] → amounts[]    │
│ pendingWithdrawals[address] → amount        │
│ votes[bountyId][claimId] → Votes           │
└─────────────────────────────────────────────┘
```

## Gas Optimization

- **Counter caching**: `bountyCounter` and `claimCounter` prevent array length lookups
- **Slot reuse**: Free participant slots are reused via stack
- **Batch operations**: Multiple contributions in single transaction
- **Event emission**: Minimal events for gas efficiency
