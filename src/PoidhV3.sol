// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";

/// @title PoidhV3
/// @notice Secure rebuild of POIDH v2 bounty contracts.
/// @dev Design goals:
///  - Preserve the core v2 mechanics: solo bounties, open bounties, 48h voting, >50% of participating weight, 2.5% fee.
///  - Fix the v2 exploit class: ERC721 callback reentrancy + missing state finalization.
///  - Eliminate push-payments; unify all value exits behind a pull-payment `withdraw()`.
contract PoidhV3 is ReentrancyGuard, Ownable2Step, Pausable {
    /** =========================
        === Constants / Config ===
        ========================= */
    uint256 public constant FEE_BPS = 250; // 2.5%
    uint256 public constant BPS_DENOM = 10_000;
    uint256 public constant MIN_BOUNTY_AMOUNT = 0.001 ether;
    uint256 public constant MAX_PARTICIPANTS = 100; // includes issuer slot at index 0

    uint256 public votingPeriod = 2 days;

    address public immutable treasury;
    IPoidhClaimNFT public immutable poidhNft;

    /** =================
        === Data Types ===
        ================= */
    struct Bounty {
        uint256 id;
        address issuer;
        string name;
        string description;
        uint256 amount;      // escrow amount remaining (native token)
        address claimer;     // address(0) = active, issuer = cancelled/closed, other = claimed
        uint256 createdAt;
        uint256 claimId;     // accepted claim id (0 if none)
    }

    struct Claim {
        uint256 id;
        address issuer;
        uint256 bountyId;
        address bountyIssuer;
        string name;
        string description;
        uint256 createdAt;
        bool accepted;
    }

    struct Votes {
        uint256 yes;
        uint256 no;
        uint256 deadline;
    }

    /** =====================
        === Storage Layout ===
        ===================== */
    Bounty[] public bounties;
    Claim[] public claims;

    uint256 public bountyCounter;
    uint256 public claimCounter;

    // User indexes
    mapping(address => uint256[]) public userBounties;
    mapping(address => uint256[]) public userClaims;
    mapping(uint256 => uint256[]) public bountyClaims;

    // Open bounty contributors (issuer is always at index 0 on creation)
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => uint256[]) public participantAmounts;

    // Voting
    mapping(uint256 => uint256) public bountyCurrentVotingClaim;
    mapping(uint256 => Votes) public bountyVotingTracker;

    // Vote-round mechanism: no need to loop/reset hasVoted across contributors
    mapping(uint256 => uint256) public voteRound; // increments each time a vote starts
    mapping(uint256 => mapping(address => uint256)) private lastVotedRound; // last round id a user voted in

    // Constant-time contributor index lookup (index+1; 0 means "never seen")
    mapping(uint256 => mapping(address => uint256)) private contributorIndexPlus1;

    // Tracks if an open bounty ever had an external contributor (non-issuer) with nonzero contribution.
    // If true, the bounty can only be resolved via voting (even if external contributors later withdraw).
    mapping(uint256 => bool) public everHadExternalContributor;

    // Pull payments (native token)
    mapping(address => uint256) public pendingWithdrawals;

    /** ============
        === Events ===
        ============ */
    event BountyCreated(
        uint256 indexed id,
        address indexed issuer,
        string name,
        string description,
        uint256 amount,
        uint256 createdAt
    );

    event ClaimCreated(
        uint256 indexed id,
        address indexed issuer,
        uint256 indexed bountyId,
        address bountyIssuer,
        string name,
        string description,
        uint256 createdAt
    );

    event ClaimAccepted(
        uint256 indexed bountyId,
        uint256 indexed claimId,
        address indexed claimIssuer,
        address bountyIssuer,
        uint256 bountyAmount,
        uint256 payout,
        uint256 fee
    );

    event BountyJoined(uint256 indexed bountyId, address indexed participant, uint256 amount);

    event ClaimSubmittedForVote(uint256 indexed bountyId, uint256 indexed claimId);

    event BountyCancelled(uint256 indexed bountyId, address indexed issuer, uint256 issuerRefund);

    event ResetVotingPeriod(uint256 indexed bountyId);

    event VoteClaim(address indexed voter, uint256 indexed bountyId, uint256 indexed claimId);

    event WithdrawFromOpenBounty(uint256 indexed bountyId, address indexed participant, uint256 amount);

    // New, indexer-friendly events
    event Withdrawal(address indexed user, uint256 amount);
    event VotingStarted(uint256 indexed bountyId, uint256 indexed claimId, uint256 deadline, uint256 issuerYesWeight);
    event VoteCast(address indexed voter, uint256 indexed bountyId, uint256 indexed claimId, bool support, uint256 weight);
    event VotingResolved(uint256 indexed bountyId, uint256 indexed claimId, bool passed, uint256 yes, uint256 no);
    event RefundClaimed(uint256 indexed bountyId, address indexed participant, uint256 amount);

    /** ============
        === Errors ===
        ============ */
    error NoEther();
    error MinimumBountyNotMet();
    error BountyNotFound();
    error ClaimNotFound();
    error VotingOngoing();
    error VotingEnded();
    error NoVotingPeriodSet();
    error BountyClaimed();
    error BountyClosed();
    error NotOpenBounty();
    error NotSoloBounty();
    error WrongCaller();
    error IssuerCannotClaim();
    error IssuerCannotWithdraw();
    error NotActiveParticipant();
    error AlreadyVoted();
    error ClaimAlreadyAccepted();
    error NothingToWithdraw();
    error TransferFailed();
    error InsufficientBalance();
    error MaxParticipantsReached();
    error NotCancelledOpenBounty();
    error VoteWouldPass();
    error InvalidStartClaimIndex();

    /** ==================
        === Modifiers  ===
        ================== */
    function _requireBountyExists(uint256 bountyId) internal view {
        if (bountyId >= bountyCounter) revert BountyNotFound();
    }

    function _requireBountyNotFinalized(uint256 bountyId) internal view {
        Bounty storage bounty = bounties[bountyId];
        if (bounty.claimer == bounty.issuer) revert BountyClosed();
        if (bounty.claimer != address(0)) revert BountyClaimed();
    }

    function _requireActiveBounty(uint256 bountyId) internal view {
        if (bountyId >= bountyCounter) revert BountyNotFound();
        Bounty storage bounty = bounties[bountyId];

        // Do not allow bypassing an active voting period
        if (bountyCurrentVotingClaim[bountyId] != 0) revert VotingOngoing();
        if (bounty.claimer == bounty.issuer) revert BountyClosed();
        if (bounty.claimer != address(0)) revert BountyClaimed();
    }

    function _requireOpenBounty(uint256 bountyId) internal view {
        if (participants[bountyId].length == 0) revert NotOpenBounty();
    }

    modifier bountyExists(uint256 bountyId) {
        _requireBountyExists(bountyId);
        _;
    }

    modifier bountyNotFinalized(uint256 bountyId) {
        _requireBountyNotFinalized(bountyId);
        _;
    }

    modifier bountyChecks(uint256 bountyId) {
        _requireActiveBounty(bountyId);
        _;
    }

    modifier openBountyChecks(uint256 bountyId) {
        _requireOpenBounty(bountyId);
        _;
    }

    modifier votingChecks(uint256 bountyId) {
        uint256 currentClaim = bountyCurrentVotingClaim[bountyId];
        if (currentClaim == 0) revert NoVotingPeriodSet();
        Votes memory v = bountyVotingTracker[bountyId];
        if (block.timestamp >= v.deadline) revert VotingEnded();
        _;
    }

    /** =====================
        === Initialization ===
        ===================== */
    /// @param _poidhNft claim NFT contract (mint-to-escrow)
    /// @param _treasury fee recipient (withdraws via withdraw())
    /// @param _startClaimIndex reserve claimId 0 as "unset" sentinel
    constructor(address _poidhNft, address _treasury, uint256 _startClaimIndex) Ownable(msg.sender) {
        if (_treasury == address(0)) revert WrongCaller(); // reuse error (keeps ABI small)
        if (_startClaimIndex == 0) revert InvalidStartClaimIndex();
        poidhNft = IPoidhClaimNFT(_poidhNft);
        treasury = _treasury;

        // Reserve claimId 0 (sentinel) by pre-filling claims up to start index.
        claimCounter = _startClaimIndex;
        for (uint256 i = 0; i < _startClaimIndex; i++) {
            claims.push(
                Claim({
                    id: i,
                    issuer: address(0),
                    bountyId: 0,
                    bountyIssuer: address(0),
                    name: "",
                    description: "",
                    createdAt: 0,
                    accepted: false
                })
            );
        }
    }

    /** =========================
        === Admin / Emergency  ===
        ========================= */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /** =====================
        === Pull withdrawals ===
        ===================== */
    function withdraw() external nonReentrant whenNotPaused {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        pendingWithdrawals[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawal(msg.sender, amount);
    }

    /** =====================
        === Bounty Creation ===
        ===================== */
    function createSoloBounty(string calldata name, string calldata description)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        if (msg.value == 0) revert NoEther();
        if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();
        _createBounty(name, description);
    }

    function createOpenBounty(string calldata name, string calldata description)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        if (msg.value == 0) revert NoEther();
        if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();

        uint256 bountyId = _createBounty(name, description);

        // Set up issuer as participant[0]
        participants[bountyId].push(msg.sender);
        participantAmounts[bountyId].push(msg.value);
        contributorIndexPlus1[bountyId][msg.sender] = 1; // index 0 => store 1
    }

    function _createBounty(string calldata name, string calldata description) internal returns (uint256 bountyId) {
        bountyId = bountyCounter;
        bounties.push(
            Bounty({
                id: bountyId,
                issuer: msg.sender,
                name: name,
                description: description,
                amount: msg.value,
                claimer: address(0),
                createdAt: block.timestamp,
                claimId: 0
            })
        );
        userBounties[msg.sender].push(bountyId);
        bountyCounter++;

        emit BountyCreated(bountyId, msg.sender, name, description, msg.value, block.timestamp);
    }

    /** ============================
        === Open Bounty Funding   ===
        ============================ */
    function joinOpenBounty(uint256 bountyId)
        external
        payable
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
        openBountyChecks(bountyId)
    {
        if (msg.value == 0) revert NoEther();

        Bounty storage bounty = bounties[bountyId];
        if (msg.sender == bounty.issuer) revert WrongCaller();

        address[] storage p = participants[bountyId];
        if (p.length >= MAX_PARTICIPANTS) revert MaxParticipantsReached();

        uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];
        if (idxPlus1 == 0) {
            // New contributor
            p.push(msg.sender);
            participantAmounts[bountyId].push(msg.value);
            contributorIndexPlus1[bountyId][msg.sender] = p.length; // index+1
        } else {
            // Existing contributor slot (possibly previously withdrawn)
            uint256 idx = idxPlus1 - 1;
            // If slot was cleared to address(0), reclaim it.
            if (participants[bountyId][idx] == address(0)) {
                participants[bountyId][idx] = msg.sender;
            }
            // Otherwise must match.
            if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
            participantAmounts[bountyId][idx] += msg.value;
        }

        // Track that this bounty has had an external contributor at least once
        everHadExternalContributor[bountyId] = true;

        bounty.amount += msg.value;
        emit BountyJoined(bountyId, msg.sender, msg.value);
    }

    /// @notice Withdraw your contribution from an open bounty (only when not voting).
    /// @dev Implements pull-payment: credits `pendingWithdrawals` and requires `withdraw()`.
    function withdrawFromOpenBounty(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
        openBountyChecks(bountyId)
    {
        Bounty storage bounty = bounties[bountyId];
        if (msg.sender == bounty.issuer) revert IssuerCannotWithdraw();

        uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];
        if (idxPlus1 == 0) revert NotActiveParticipant();
        uint256 idx = idxPlus1 - 1;

        if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
        uint256 amount = participantAmounts[bountyId][idx];
        if (amount == 0) revert NotActiveParticipant();

        // Effects
        participantAmounts[bountyId][idx] = 0;
        participants[bountyId][idx] = address(0);
        bounty.amount -= amount;

        pendingWithdrawals[msg.sender] += amount;

        emit WithdrawFromOpenBounty(bountyId, msg.sender, amount);
    }

    /** =====================
        === Cancellation   ===
        ===================== */
    function cancelSoloBounty(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
    {
        if (participants[bountyId].length != 0) revert NotSoloBounty();

        Bounty storage bounty = bounties[bountyId];
        if (msg.sender != bounty.issuer) revert WrongCaller();

        uint256 amount = bounty.amount;

        // Effects
        bounty.claimer = bounty.issuer; // close
        bounty.amount = 0;

        pendingWithdrawals[msg.sender] += amount;

        emit BountyCancelled(bountyId, msg.sender, amount);
    }

    /// @notice Cancel an open bounty. Constant-time. Contributors claim refunds themselves.
    function cancelOpenBounty(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
        openBountyChecks(bountyId)
    {
        Bounty storage bounty = bounties[bountyId];
        if (msg.sender != bounty.issuer) revert WrongCaller();

        // Effects: close first
        bounty.claimer = bounty.issuer;

        // Refund issuer immediately (index 0)
        uint256 issuerAmount = participantAmounts[bountyId][0];
        if (issuerAmount > 0) {
            participantAmounts[bountyId][0] = 0;
            participants[bountyId][0] = address(0);
            bounty.amount -= issuerAmount;
            pendingWithdrawals[bounty.issuer] += issuerAmount;
        }

        emit BountyCancelled(bountyId, msg.sender, issuerAmount);
    }

    /// @notice Contributors claim their refunds after an open bounty is cancelled.
    function claimRefundFromCancelledOpenBounty(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
    {
        if (bountyId >= bountyCounter) revert BountyNotFound();
        Bounty storage bounty = bounties[bountyId];
        if (participants[bountyId].length == 0) revert NotOpenBounty();
        if (bounty.claimer != bounty.issuer) revert NotCancelledOpenBounty();

        uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];
        if (idxPlus1 == 0) revert NotActiveParticipant();
        uint256 idx = idxPlus1 - 1;

        if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
        uint256 amount = participantAmounts[bountyId][idx];
        if (amount == 0) revert NotActiveParticipant();

        participantAmounts[bountyId][idx] = 0;
        participants[bountyId][idx] = address(0);
        bounty.amount -= amount;

        pendingWithdrawals[msg.sender] += amount;
        emit RefundClaimed(bountyId, msg.sender, amount);
    }

    /** =====================
        === Claim Creation ===
        ===================== */
    function createClaim(
        uint256 bountyId,
        string calldata name,
        string calldata description,
        string calldata uri
    )
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
    {
        Bounty memory bounty = bounties[bountyId];

        if (msg.sender == bounty.issuer) revert IssuerCannotClaim();

        uint256 claimId = claimCounter;

        claims.push(
            Claim({
                id: claimId,
                issuer: msg.sender,
                bountyId: bountyId,
                bountyIssuer: bounty.issuer,
                name: name,
                description: description,
                createdAt: block.timestamp,
                accepted: false
            })
        );

        // Mint claim NFT to escrow (this contract) via the PoidhClaimNFT contract.
        poidhNft.mintToEscrow(claimId, uri);

        userClaims[msg.sender].push(claimId);
        bountyClaims[bountyId].push(claimId);

        claimCounter++;

        emit ClaimCreated(claimId, msg.sender, bountyId, bounty.issuer, name, description, block.timestamp);
    }

    /** =====================
        === Voting (Open)  ===
        ===================== */
    function submitClaimForVote(uint256 bountyId, uint256 claimId)
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
        openBountyChecks(bountyId)
    {
        if (claimId >= claimCounter) revert ClaimNotFound();

        Bounty memory bounty = bounties[bountyId];

        if (msg.sender != bounty.issuer) revert WrongCaller();

        Claim memory claim = claims[claimId];
        if (claim.issuer == address(0)) revert ClaimNotFound();
        if (claim.bountyId != bountyId) revert ClaimNotFound();
        if (claim.accepted) revert ClaimAlreadyAccepted();

        // Start a new vote round
        voteRound[bountyId] += 1;
        uint256 roundId = voteRound[bountyId];

        // Issuer auto-votes YES with their weight (participant[0]).
        uint256 issuerWeight = participantAmounts[bountyId][0];
        if (issuerWeight == 0) revert NotActiveParticipant();

        bountyCurrentVotingClaim[bountyId] = claimId;
        bountyVotingTracker[bountyId] = Votes({
            yes: issuerWeight,
            no: 0,
            deadline: block.timestamp + votingPeriod
        });

        lastVotedRound[bountyId][msg.sender] = roundId;

        emit ClaimSubmittedForVote(bountyId, claimId);
        emit VotingStarted(bountyId, claimId, block.timestamp + votingPeriod, issuerWeight);
        emit VoteCast(msg.sender, bountyId, claimId, true, issuerWeight);
    }

    function voteClaim(uint256 bountyId, bool vote)
        external
        nonReentrant
        whenNotPaused
        bountyExists(bountyId)
        votingChecks(bountyId)
    {
        if (participants[bountyId].length == 0) revert NotOpenBounty();

        uint256 currentClaim = bountyCurrentVotingClaim[bountyId];

        uint256 roundId = voteRound[bountyId];
        if (lastVotedRound[bountyId][msg.sender] == roundId) revert AlreadyVoted();

        uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];
        if (idxPlus1 == 0) revert NotActiveParticipant();
        uint256 idx = idxPlus1 - 1;

        if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
        uint256 weight = participantAmounts[bountyId][idx];
        if (weight == 0) revert NotActiveParticipant();

        // Effects
        lastVotedRound[bountyId][msg.sender] = roundId;

        Votes storage v = bountyVotingTracker[bountyId];
        if (vote) {
            v.yes += weight;
        } else {
            v.no += weight;
        }

        // Legacy + new events
        emit VoteClaim(msg.sender, bountyId, currentClaim);
        emit VoteCast(msg.sender, bountyId, currentClaim, vote, weight);
    }

    function resolveVote(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
    {
        if (participants[bountyId].length == 0) revert NotOpenBounty();

        uint256 currentClaim = bountyCurrentVotingClaim[bountyId];
        if (currentClaim == 0) revert NoVotingPeriodSet();

        Votes memory v = bountyVotingTracker[bountyId];
        if (block.timestamp < v.deadline) revert VotingOngoing();

        bool passed = v.yes > ((v.no + v.yes) / 2);

        if (passed) {
            _acceptClaim(bountyId, currentClaim);
        } else {
            // reset
            bountyCurrentVotingClaim[bountyId] = 0;
            delete bountyVotingTracker[bountyId];

            emit ResetVotingPeriod(bountyId);
            emit VotingResolved(bountyId, currentClaim, false, v.yes, v.no);
        }
    }

    /// @notice Keep for ABI compatibility, but cannot discard a winning vote.
    function resetVotingPeriod(uint256 bountyId)
        external
        nonReentrant
        whenNotPaused
        bountyExists(bountyId)
        bountyNotFinalized(bountyId)
    {
        if (participants[bountyId].length == 0) revert NotOpenBounty();
        uint256 currentClaim = bountyCurrentVotingClaim[bountyId];
        if (currentClaim == 0) revert NoVotingPeriodSet();

        Votes memory v = bountyVotingTracker[bountyId];
        if (block.timestamp < v.deadline) revert VotingOngoing();

        bool wouldPass = v.yes > ((v.no + v.yes) / 2);
        if (wouldPass) revert VoteWouldPass();

        bountyCurrentVotingClaim[bountyId] = 0;
        delete bountyVotingTracker[bountyId];

        emit ResetVotingPeriod(bountyId);
        emit VotingResolved(bountyId, currentClaim, false, v.yes, v.no);
    }

    /** =====================
        === Acceptance     ===
        ===================== */
    function acceptClaim(uint256 bountyId, uint256 claimId)
        external
        nonReentrant
        whenNotPaused
        bountyChecks(bountyId)
    {
        if (claimId >= claimCounter) revert ClaimNotFound();

        Bounty memory bounty = bounties[bountyId];

        // Solo bounty: always direct accept by issuer
        if (participants[bountyId].length == 0) {
            if (msg.sender != bounty.issuer) revert WrongCaller();
            _acceptClaim(bountyId, claimId);
            return;
        }

        // Open bounty: only direct accept if it NEVER had external contributors.
        // Otherwise must go through voting.
        if (everHadExternalContributor[bountyId]) revert NotSoloBounty();
        if (msg.sender != bounty.issuer) revert WrongCaller();

        _acceptClaim(bountyId, claimId);
    }

    function _acceptClaim(uint256 bountyId, uint256 claimId) internal {
        Bounty storage bounty = bounties[bountyId];
        Claim storage claim = claims[claimId];

        if (claim.issuer == address(0)) revert ClaimNotFound();
        if (claim.bountyId != bountyId) revert ClaimNotFound();
        if (claim.accepted) revert ClaimAlreadyAccepted();
        if (bounty.amount > address(this).balance) revert InsufficientBalance();

        address claimIssuer = claim.issuer;
        uint256 bountyAmount = bounty.amount;

        uint256 fee = (bountyAmount * FEE_BPS) / BPS_DENOM;
        uint256 payout = bountyAmount - fee;

        // Effects: finalize state BEFORE any external interaction
        bounty.claimer = claimIssuer;
        bounty.claimId = claimId;
        bounty.amount = 0;

        claim.accepted = true;

        // Snapshot voting state (if this came from resolveVote)
        uint256 currentVotingClaim = bountyCurrentVotingClaim[bountyId];
        Votes memory voteSnap = bountyVotingTracker[bountyId];

        // Clear voting state
        bountyCurrentVotingClaim[bountyId] = 0;
        delete bountyVotingTracker[bountyId];

        // Pull payments
        pendingWithdrawals[claimIssuer] += payout;
        pendingWithdrawals[treasury] += fee;

        emit ClaimAccepted(bountyId, claimId, claimIssuer, bounty.issuer, bountyAmount, payout, fee);

        // Interaction: transfer claim NFT from escrow (this contract) to bounty issuer.
        // Using `transferFrom` avoids ERC721Receiver callback vectors.
        poidhNft.transferFrom(address(this), bounty.issuer, claimId);

        if (currentVotingClaim != 0) {
            emit VotingResolved(bountyId, claimId, true, voteSnap.yes, voteSnap.no);
        }
    }

    /** =====================
        === View Helpers   ===
        ===================== */
    function getBountiesLength() external view returns (uint256) {
        return bounties.length;
    }

    function getBounties(uint256 offset) external view returns (Bounty[] memory) {
        Bounty[] memory result = new Bounty[](10);
        uint256 counter;
        for (uint256 i = bounties.length; i > offset && counter < 10; i--) {
            result[counter] = bounties[i - 1];
            counter++;
        }
        return result;
    }

    function getClaimsByBountyId(uint256 bountyId, uint256 offset) external view returns (Claim[] memory) {
        uint256[] memory ids = bountyClaims[bountyId];
        Claim[] memory result = new Claim[](10);
        uint256 counter;
        for (uint256 i = ids.length; i > offset && counter < 10; i--) {
            result[counter] = claims[ids[i - 1]];
            counter++;
        }
        return result;
    }

    function getBountiesByUser(address user, uint256 offset) external view returns (Bounty[] memory) {
        uint256[] memory ids = userBounties[user];
        Bounty[] memory result = new Bounty[](10);
        uint256 counter;
        for (uint256 i = ids.length; i > offset && counter < 10; i--) {
            result[counter] = bounties[ids[i - 1]];
            counter++;
        }
        return result;
    }

    function getClaimsByUser(address user, uint256 offset) external view returns (Claim[] memory) {
        uint256[] memory ids = userClaims[user];
        Claim[] memory result = new Claim[](10);
        uint256 counter;
        for (uint256 i = ids.length; i > offset && counter < 10; i--) {
            result[counter] = claims[ids[i - 1]];
            counter++;
        }
        return result;
    }

    function getParticipants(uint256 bountyId)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        return (participants[bountyId], participantAmounts[bountyId]);
    }

    /// @notice Pagination helper for big bounties (indexer-friendly).
    function getParticipantsPaged(uint256 bountyId, uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory addrs, uint256[] memory amts)
    {
        address[] memory p = participants[bountyId];
        uint256[] memory a = participantAmounts[bountyId];

        if (offset >= p.length) {
            return (new address[](0), new uint256[](0));
        }

        uint256 end = offset + limit;
        if (end > p.length) end = p.length;

        uint256 n = end - offset;
        addrs = new address[](n);
        amts = new uint256[](n);

        for (uint256 i = 0; i < n; i++) {
            addrs[i] = p[offset + i];
            amts[i] = a[offset + i];
        }
    }

    receive() external payable {}
}
