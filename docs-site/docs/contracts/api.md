# API Reference

## Contract: PoidhV3

### State Variables

#### Configuration

```solidity
uint256 public constant FEE_BPS = 250; // 2.5%
uint256 public constant BPS_DENOM = 10_000;
uint256 public constant MAX_PARTICIPANTS = 150;

uint256 public immutable MIN_BOUNTY_AMOUNT;
uint256 public immutable MIN_CONTRIBUTION;
uint256 public votingPeriod = 2 days;
address public immutable treasury;
IPoidhClaimNFT public immutable poidhNft;
```

#### Counters

```solidity
uint256 public bountyCounter;
uint256 public claimCounter;
```

#### Mappings

```solidity
mapping(address => uint256[]) public userBounties;
mapping(address => uint256[]) public userClaims;
mapping(uint256 => uint256[]) public bountyClaims;
mapping(uint256 => address[]) public participants;
mapping(uint256 => uint256[]) public participantAmounts;
mapping(uint256 => mapping(address => uint256)) public pendingWithdrawals;
```

### Core Functions

#### createSoloBounty

Creates a solo bounty where only the issuer provides funding.

```solidity
function createSoloBounty(
    string calldata name,
    string calldata description
) external payable nonReentrant returns (uint256 bountyId)
```

**Parameters:**
- `name`: Bounty name
- `description`: Bounty details

**Requirements:**
- `msg.value >= MIN_BOUNTY_AMOUNT`
- Non-empty name

**Returns:**
- `bountyId`: Unique bounty identifier

**Events:**
- `BountyCreated(uint256 indexed bountyId, address indexed issuer, string name, uint256 amount)`

---

#### claimSoloBounty

Submits a claim for a solo bounty.

```solidity
function claimSoloBounty(
    uint256 bountyId,
    string calldata name,
    string calldata description
) external nonReentrant returns (uint256 claimId)
```

**Parameters:**
- `bountyId`: Target bounty
- `name`: Claim name
- `description`: Claim details

**Requirements:**
- Bounty must be active
- Bounty must not have pending claim

**Returns:**
- `claimId`: Unique claim identifier

**Events:**
- `ClaimSubmitted(uint256 indexed claimId, uint256 indexed bountyId, address indexed issuer)`

---

#### acceptSoloClaim

Accepts a claim for a solo bounty (issuer only).

```solidity
function acceptSoloClaim(
    uint256 bountyId,
    uint256 claimId
) external nonReentrant
```

**Parameters:**
- `bountyId`: Target bounty
- `claimId`: Claim to accept

**Requirements:**
- Caller must be bounty issuer
- Claim must belong to bounty
- Bounty must be active

**Effects:**
- Accepts claim
- Zeroes bounty amount
- Credits claimant withdrawal
- Transfers claim NFT to issuer

**Events:**
- `ClaimAccepted(uint256 indexed claimId, uint256 indexed bountyId)`

---

#### cancelSoloBounty

Cancels a solo bounty (issuer only).

```solidity
function cancelSoloBounty(uint256 bountyId) external nonReentrant
```

**Parameters:**
- `bountyId`: Target bounty

**Requirements:**
- Caller must be bounty issuer
- Bounty must be active

**Effects:**
- Marks bounty as cancelled
- Credits issuer withdrawal

**Events:**
- `BountyCancelled(uint256 indexed bountyId)`

---

### Open Bounty Functions

#### createOpenBounty

Creates an open bounty with multiple contributors.

```solidity
function createOpenBounty(
    string calldata name,
    string calldata description
) external payable nonReentrant returns (uint256 bountyId)
```

**Parameters:**
- `name`: Bounty name
- `description`: Bounty details

**Requirements:**
- `msg.value >= MIN_BOUNTY_AMOUNT`

**Returns:**
- `bountyId`: Unique bounty identifier

---

#### joinOpenBounty

Contributes to an open bounty.

```solidity
function joinOpenBounty(uint256 bountyId) 
    external 
    payable 
    nonReentrant 
    returns (uint256 participantIndex)
```

**Parameters:**
- `bountyId`: Target bounty

**Requirements:**
- Bounty must be active
- `msg.value >= MIN_CONTRIBUTION`
- Participant slots available
- Not already participant

**Returns:**
- `participantIndex`: Index in participants array

**Events:**
- `ContributionAdded(uint256 indexed bountyId, address indexed contributor, uint256 amount)`

---

#### claimOpenBounty

Submits a claim for an open bounty.

```solidity
function claimOpenBounty(
    uint256 bountyId,
    string calldata name,
    string calldata description
) external nonReentrant returns (uint256 claimId)
```

**Parameters:**
- `bountyId`: Target bounty
- `name`: Claim name
- `description`: Claim details

**Requirements:**
- Must be contributor
- No active voting

**Effects:**
- Starts voting period
- Mints claim NFT to escrow

---

#### vote

Votes on an active claim (participants only).

```solidity
function vote(
    uint256 bountyId,
    uint256 claimId,
    bool yes
) external nonReentrant
```

**Parameters:**
- `bountyId`: Target bounty
- `claimId`: Claim to vote on
- `yes`: True for yes, false for no

**Requirements:**
- Must be participant
- Voting must be active
- Haven't voted yet

**Effects:**
- Adds weighted vote (weight = contribution)

**Events:**
- `Voted(uint256 indexed bountyId, uint256 indexed claimId, address indexed voter, bool yes, uint256 weight)`

---

#### tallyVotes

Calculates voting result (anyone can call after deadline).

```solidity
function tallyVotes(uint256 bountyId, uint256 claimId) 
    external 
    nonReentrant 
    returns (bool accepted)
```

**Parameters:**
- `bountyId`: Target bounty
- `claimId`: Claim to tally

**Requirements:**
- Voting deadline passed
- Not yet tallied

**Returns:**
- `accepted`: True if claim accepted

**Effects:**
- If accepted: Credits claimant + contributors
- If rejected: Returns claim NFT to claimant

---

#### cancelOpenBounty

Cancels an open bounty (issuer only, before external contributors).

```solidity
function cancelOpenBounty(uint256 bountyId) external nonReentrant
```

**Parameters:**
- `bountyId`: Target bounty

**Requirements:**
- Caller must be issuer
- No external contributors yet

---

#### claimRefundFromCancelledOpenBounty

Claims refund from cancelled open bounty.

```solidity
function claimRefundFromCancelledOpenBounty(uint256 bountyId) 
    external 
    nonReentrant
```

**Parameters:**
- `bountyId`: Target bounty

**Requirements:**
- Bounty must be cancelled
- Must have contribution

**Effects:**
- Credits withdrawal with contribution

---

### Withdrawal Functions

#### withdraw

Withdraws pending ETH.

```solidity
function withdraw() external nonReentrant
```

**Effects:**
- Sends all pending ETH to caller
- Zeroes pending withdrawal balance

**Events:**
- `Withdrawal(address indexed user, uint256 amount)`

---

#### withdrawTo

Withdraws pending ETH to another address.

```solidity
function withdrawTo(address recipient) external nonReentrant
```

**Parameters:**
- `recipient`: Address to send funds to

**Requirements:**
- Recipient must not be zero address

---

#### returnClaimNFTToIssuer

Returns claim NFT to bounty issuer (after acceptance).

```solidity
function returnClaimNFTToIssuer(uint256 claimId) external nonReentrant
```

**Parameters:**
- `claimId`: Claim NFT to return

**Requirements:**
- Claim must be accepted
- Caller must be bounty issuer

---

### View Functions

#### getBounty

```solidity
function getBounty(uint256 bountyId) 
    external 
    view 
    returns (Bounty memory)
```

#### getClaim

```solidity
function getClaim(uint256 claimId) 
    external 
    view 
    returns (Claim memory)
```

#### getVotes

```solidity
function getVotes(uint256 bountyId, uint256 claimId) 
    external 
    view 
    returns (Votes memory)
```

#### getUserBounties

```solidity
function getUserBounties(address user) 
    external 
    view 
    returns (uint256[] memory)
```

#### getUserClaims

```solidity
function getUserClaims(address user) 
    external 
    view 
    returns (uint256[] memory)
```

#### getPendingWithdrawal

```solidity
function getPendingWithdrawal(address user) 
    external 
    view 
    returns (uint256)
```

---

### Admin Functions

#### setVotingPeriod

```solidity
function setVotingPeriod(uint256 newVotingPeriod) external
```

**Requirements:**
- Caller must be deployer (timelocked)
- Must be within reasonable bounds

#### resetVotingPeriod

```solidity
function resetVotingPeriod(uint256 bountyId, uint256 claimId) 
    external 
    nonReentrant
```

**Requirements:**
- Caller must be bounty issuer
- Voting must be active

**Effects:**
- Resets voting deadline to `block.timestamp + votingPeriod`

---

## Contract: PoidhClaimNFT

ERC721 token representing bounty claims.

### Functions

#### mint

```solidity
function mint(address to, uint256 tokenId) external
```

**Requirements:**
- Caller must be PoidhV3 contract

#### tokenURI

```solidity
function tokenURI(uint256 tokenId) 
    external 
    view 
    override 
    returns (string memory)
```

Returns base64 encoded metadata.

---

## Events Reference

```solidity
event BountyCreated(
    uint256 indexed bountyId,
    address indexed issuer,
    string name,
    uint256 amount
);

event ClaimSubmitted(
    uint256 indexed claimId,
    uint256 indexed bountyId,
    address indexed issuer
);

event ClaimAccepted(
    uint256 indexed claimId,
    uint256 indexed bountyId
);

event BountyCancelled(uint256 indexed bountyId);

event ContributionAdded(
    uint256 indexed bountyId,
    address indexed contributor,
    uint256 amount
);

event Voted(
    uint256 indexed bountyId,
    uint256 indexed claimId,
    address indexed voter,
    bool yes,
    uint256 weight
);

event Withdrawal(
    address indexed user,
    uint256 amount
);
```

---

## Error Reference

```solidity
error NotIssuer();
error InvalidClaim();
error AlreadyClaimed();
error NotActive();
error VotingNotActive();
error NotParticipant();
error AlreadyVoted();
error InvalidAmount();
error InsufficientFunds();
error ReentrancyGuard();
```

---

## Gas Costs (Estimated)

| Function | Gas Cost (avg) |
|----------|---------------|
| createSoloBounty | ~150,000 |
| claimSoloBounty | ~200,000 |
| acceptSoloClaim | ~100,000 |
| createOpenBounty | ~160,000 |
| joinOpenBounty | ~80,000 |
| claimOpenBounty | ~220,000 |
| vote | ~50,000 |
| tallyVotes | ~80,000 |
| withdraw | ~40,000 |

*Note: Gas costs vary based on input sizes and network conditions.*
