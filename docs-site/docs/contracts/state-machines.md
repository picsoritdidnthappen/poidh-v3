# State Machines

## Bounty Lifecycle States

```mermaid
stateDiagram-v2
    [*] --> Creating: createSoloBounty() / createOpenBounty()
    Creating --> Active: Funded & Minted
    Active --> Claimed: claimSoloBounty() / claimOpenBounty()
    Active --> Cancelled: cancelSoloBounty() / cancelOpenBounty()
    Claimed --> Voting: Open bounty only
    Voting --> Accepted: Yes votes > No votes
    Voting --> Rejected: No votes >= Yes votes
    Accepted --> Resolved: Payments credited
    Rejected --> Active: Claim rejected
    Cancelled --> Refundable: withdraw() available
    Resolved --> [*]: All funds withdrawn
    Refundable --> [*]: All funds withdrawn
    
    note right of Active
        Bounty is open for claims
        - Solo: Anyone can claim
        - Open: Contributors can join
    end note
    
    note right of Voting
        Weighted voting period
        - Duration: votingPeriod
        - Weight = contribution amount
    end note
    
    note right of Accepted
        Claim accepted
        - Bounty amount zeroed
        - Claim NFT marked accepted
        - Withdrawals credited
    end note
```

## Solo Bounty State Machine

```mermaid
stateDiagram-v2
    [*] --> Funded: issuer creates bounty
    Funded --> Claimed: claimant submits claim
    Claimed --> Accepted: issuer accepts claim
    Claimed --> Funded: issuer rejects (claim remains)
    Accepted --> Completed: funds withdrawn
    
    state Funded {
        [*] --> Active
        Active --> Cancelled: issuer cancels
    }
    
    state Claimed {
        [*] --> Pending
        Pending --> Accepted: issuer accepts
        Pending --> Pending: issuer rejects
    }
    
    state Accepted {
        [*] --> Withdrawable
        Withdrawable --> Completed: withdraw() called
    }
    
    note right of Funded
        State: bounty.claimer == address(0)
        Amount: bounty.amount > 0
        Action: acceptSoloClaim()
    end note
    
    note right of Accepted
        State: bounty.claimer == claimant
        Amount: bounty.amount == 0
        Claim: claim.accepted == true
        Action: withdraw()
    end note
```

## Open Bounty State Machine

```mermaid
stateDiagram-v2
    [*] --> Funded: issuer creates with initial amount
    Funded --> Contributing: contributors join
    Contributing --> Contributing: more contributors join
    Contributing --> Voting: claim submitted
    Voting --> Voting: voting period active
    Voting --> Accepted: vote passes
    Voting --> Rejected: vote fails
    Rejected --> Contributing: new claims allowed
    Accepted --> Distributable: all withdrawals credited
    Distributable --> [*]: all funds withdrawn
    
    state Contributing {
        [*] --> Open
        Open --> Full: MAX_PARTICIPANTS reached
        Full --> Open: slots free up
    }
    
    state Voting {
        [*] --> Active
        Active --> Calculating: deadline reached
        Calculating --> Result: tally complete
    }
    
    state Accepted {
        [*] --> Ready
        Ready --> Ready: participants withdraw
    }
    
    note right of Contributing
        Max 150 participants
        Index 0 = issuer
        Slots reusable after withdrawal
    end note
    
    note right of Voting
        Duration: 2 days (configurable)
        Weight: contribution amount
        Threshold: simple majority
    end note
```

## Claim NFT State Machine

```mermaid
stateDiagram-v2
    [*] --> Minted: claim created
    Minted --> Escrowed: transferred to PoidhV3
    Escrowed --> Accepted: claim accepted
    Escrowed --> Rejected: claim rejected
    Escrowed --> Cancelled: bounty cancelled
    Accepted --> IssuerTransferred: returned to bounty issuer
    Rejected --> ClaimantTransferred: returned to claimant
    Cancelled --> ClaimantTransferred: returned to claimant
    IssuerTransferred --> [*]
    ClaimantTransferred --> [*]
    
    note right of Escrowed
        Held in PoidhV3 contract
        No callbacks (transferFrom)
        Non-reentrant
    end note
    
    note right of Accepted
        Transferred to bounty issuer
        Marks completion
        Proof of work
    end note
    
    note right of Rejected
        Returned to claimant
        Can resubmit
        No penalty
    end note
```

## Withdrawal State Machine

```mermaid
stateDiagram-v2
    [*] --> Credited: funds added to pendingWithdrawals
    Credited --> PartiallyWithdrawn: partial withdraw()
    Credited --> FullyWithdrawn: full withdraw()
    PartiallyWithdrawn --> FullyWithdrawn: remaining withdrawn
    FullyWithdrawn --> [*]
    
    state Credited {
        [*] --> Available
        Available --> Available: multiple sources
    }
    
    state PartiallyWithdrawn {
        [*] --> Remaining
        Remaining --> Remaining: more withdraws
    }
    
    note right of Credited
        Mapping: pendingWithdrawals[address]
        Sources: 
        - Accepted claim payout
        - Contribution refund
        - Bounty cancellation refund
        - Fee credits
    end note
    
    note right of PartiallyWithdrawn
        User can withdraw multiple times
        Each call reduces balance
        Non-reentrant protected
    end note
```

## Participant Slot State Machine

```mermaid
stateDiagram-v2
    [*] --> Available: bounty created
    Available --> Occupied: contributor joins
    Occupied --> Available: contributor withdraws
    Occupied --> Available: bounty resolved
    
    state Available {
        [*] --> FreeSlot: slot <= MAX_PARTICIPANTS
        FreeSlot --> ReusedSlot: from free stack
    }
    
    state Occupied {
        [*] --> Active
        Active --> Withdrawing: user withdraws
        Withdrawing --> Freed: slot freed
    }
    
    note right of Available
        Total slots: 150
        Index 0: issuer (always occupied)
        Indices 1-149: contributors
    end note
    
    note right of Occupied
        Mapping: contributorIndexPlus1[bountyId][address]
        Value 0 = not in bounty
        Value > 0 = index + 1 in array
    end note
```

## Transaction Flow States

### Create Solo Bounty

```mermaid
stateDiagram-v2
    [*] --> Validation: check amount >= MIN_BOUNTY_AMOUNT
    Validation --> Effects: update state
    Effects --> Mint: create bounty record
    Mint --> Emission: emit BountyCreated event
    Emission --> [*]: complete
    
    note right of Validation
        require(msg.value >= MIN_BOUNTY_AMOUNT)
        require(bytes(name).length > 0)
    end note
    
    note right of Effects
        bounties.push()
        bountyCounter++
        userBounties[msg.sender].push(id)
    end note
```

### Vote on Open Bounty Claim

```mermaid
stateDiagram-v2
    [*] --> Validation: check voting conditions
    Validation --> Effect: record vote
    Effect --> Update: update totals
    Update --> Emission: emit Voted event
    Emission --> Complete: check deadline
    Complete --> [*]
    
    state Validation {
        [*] --> CheckBounty: bounty exists
        CheckBounty --> CheckClaim: claim exists
        CheckClaim --> CheckParticipant: caller is participant
        CheckParticipant --> CheckVoting: voting active
    }
    
    state Effect {
        [*] --> YesNo: direction
        YesNo --> Weighted: by contribution
    }
    
    note right of Validation
        Must be participant
        Voting must be active
        Cannot revote
    end note
    
    note right of Effect
        votes[bountyId][claimId].yes += contribution
        OR
        votes[bountyId][claimId].no += contribution
    end note
```

## Error State Transitions

```mermaid
stateDiagram-v2
    [*] --> Attempting: user action
    Attempting --> Success: all checks pass
    Attempting --> Reverted: check fails
    Reverted --> [*]: revert with error
    
    state Reverted {
        [*] --> InsufficientFunds
        [*] --> Unauthorized
        [*] --> InvalidState
        [*] --> ReentrancyDetected
    }
    
    note right of Reverted
        Common revert reasons:
        - "Not issuer"
        - "Invalid claim"
        - "Voting not active"
        - "Already claimed"
        - "ReentrancyGuard"
    end note
```
