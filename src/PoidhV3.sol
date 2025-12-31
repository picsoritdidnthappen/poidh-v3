// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";

/// @title PoidhV3
/// @notice POIDH bounty protocol (solo + open bounties) with weighted voting and pull-payments.
/// @dev Security design goals:
/// - All ETH exits are pull-based via `pendingWithdrawals` + `withdraw()` / `withdrawTo()`.
/// - Claim NFTs are escrowed in this contract and transferred with `transferFrom` (no callbacks).
/// - All external, state-changing entrypoints are `nonReentrant`.
contract PoidhV3 is ReentrancyGuard {
  /// =========================
  /// === Constants / Config ===
  /// =========================
  uint256 public constant FEE_BPS = 250; // 2.5%
  uint256 public constant BPS_DENOM = 10_000;

  uint256 public constant MIN_BOUNTY_AMOUNT = 0.001 ether;
  uint256 public constant MIN_CONTRIBUTION = 0.000_01 ether;

  /// @notice Max participant slots for an open bounty (issuer included at slot 0).
  uint256 public constant MAX_PARTICIPANTS = 150;

  /// @notice Voting duration for open bounty votes.
  uint256 public votingPeriod = 2 days;

  /// @notice Fee recipient (credited via pull withdrawals).
  address public immutable treasury;

  /// @notice Claim NFT contract used for claim escrow and transfers.
  IPoidhClaimNFT public immutable poidhNft;

  /// ==================
  /// === Data Types ===
  /// ==================
  struct Bounty {
    uint256 id;
    address issuer;
    string name;
    string description;
    uint256 amount;
    address claimer; // 0 = active, issuer = cancelled/closed, other = accepted
    uint256 createdAt;
    uint256 claimId; // accepted claim id (0 if none)
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

  /// ======================
  /// === Storage / State ===
  /// ======================
  Bounty[] public bounties;
  Claim[] public claims;

  uint256 public bountyCounter;
  uint256 public claimCounter; // claimId 0 reserved sentinel

  mapping(address user => uint256[] bountyIds) public userBounties;
  mapping(address user => uint256[] claimIds) public userClaims;
  mapping(uint256 bountyId => uint256[] claimIds) public bountyClaims;

  /// @notice Open bounty participants (issuer always at index 0).
  mapping(uint256 bountyId => address[] participantAddresses) public participants;

  /// @notice Contribution amounts aligned with `participants[bountyId]`.
  mapping(uint256 bountyId => uint256[] participantContributionAmounts) public participantAmounts;

  /// @notice Stack of reusable participant slot indices (vacated slots) for each bounty.
  /// @dev Prevents permanent MAX_PARTICIPANTS exhaustion when people withdraw.
  mapping(uint256 bountyId => uint256[] freeSlotIndices) private freeParticipantSlots;

  /// @notice contributor => (index + 1) in participants for O(1) lookup.
  /// @dev Zero means "no active slot currently assigned".
  mapping(uint256 bountyId => mapping(address contributor => uint256 indexPlus1)) private
    contributorIndexPlus1;

  /// @notice Whether an open bounty has EVER had an external contributor (non-issuer).
  mapping(uint256 bountyId => bool hadExternalContributor) public everHadExternalContributor;

  /// @notice Current claim being voted on (0 if none).
  mapping(uint256 bountyId => uint256 claimId) public bountyCurrentVotingClaim;

  /// @notice Vote totals + deadline for the active round.
  mapping(uint256 bountyId => Votes votes) public bountyVotingTracker;

  /// @notice Vote round id increments each time voting starts on a bounty.
  mapping(uint256 bountyId => uint256 roundId) public voteRound;

  /// @notice Voter => last round id they voted in for a bounty.
  mapping(uint256 bountyId => mapping(address voter => uint256 roundId)) private lastVotedRound;

  /// @notice Snapshotted weights at vote start (address => weight).
  mapping(uint256 bountyId => mapping(address participant => uint256 weight)) public
    voteWeightSnapshot;

  /// @notice The round id that a snapshot entry belongs to.
  /// @dev This fixes the “stale snapshot” issue: old weights cannot be reused in later rounds.
  mapping(uint256 bountyId => mapping(address participant => uint256 roundId)) private
    voteWeightSnapshotRound;

  /// @notice Pull payment balances.
  mapping(address account => uint256 amount) public pendingWithdrawals;

  /// =================
  /// === Events     ===
  /// =================
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

  /// @notice Legacy vote event for ABI/indexer compatibility.
  event VoteClaim(address indexed voter, uint256 indexed bountyId, uint256 indexed claimId);

  event WithdrawFromOpenBounty(
    uint256 indexed bountyId, address indexed participant, uint256 amount
  );

  event Withdrawal(address indexed user, uint256 amount);
  event WithdrawalTo(address indexed user, address indexed to, uint256 amount);

  event VotingStarted(
    uint256 indexed bountyId, uint256 indexed claimId, uint256 deadline, uint256 issuerYesWeight
  );

  event VoteCast(
    address indexed voter,
    uint256 indexed bountyId,
    uint256 indexed claimId,
    bool support,
    uint256 weight
  );

  event VotingResolved(
    uint256 indexed bountyId, uint256 indexed claimId, bool passed, uint256 yes, uint256 no
  );

  event RefundClaimed(uint256 indexed bountyId, address indexed participant, uint256 amount);

  /// =================
  /// === Errors     ===
  /// =================
  error NoEther();
  error MinimumBountyNotMet();
  error MinimumContributionNotMet();
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
  error ContractsCannotCreateBounties();
  error InvalidTreasury(address treasury);
  error InvalidPoidhNft(address poidhNft);
  error InvalidWithdrawTo(address to);
  error DirectEtherNotAccepted();

  /// =========================
  /// === Internal Requires ===
  /// =========================
  function _requireBountyExists(uint256 bountyId) internal view {
    if (bountyId >= bountyCounter) revert BountyNotFound();
  }

  function _requireBountyNotFinalized(uint256 bountyId) internal view {
    Bounty storage bounty = bounties[bountyId];
    if (bounty.claimer == bounty.issuer) revert BountyClosed();
    if (bounty.claimer != address(0)) revert BountyClaimed();
  }

  /// @dev Active = exists, not finalized, and no active vote.
  function _requireActiveBounty(uint256 bountyId) internal view {
    if (bountyId >= bountyCounter) revert BountyNotFound();
    if (bountyCurrentVotingClaim[bountyId] != 0) revert VotingOngoing();

    Bounty storage bounty = bounties[bountyId];
    if (bounty.claimer == bounty.issuer) revert BountyClosed();
    if (bounty.claimer != address(0)) revert BountyClaimed();
  }

  function _requireOpenBounty(uint256 bountyId) internal view {
    if (participants[bountyId].length == 0) revert NotOpenBounty();
  }

  /// @return currentClaim the claim id currently in voting
  function _requireVoteActive(uint256 bountyId) internal view returns (uint256 currentClaim) {
    currentClaim = bountyCurrentVotingClaim[bountyId];
    if (currentClaim == 0) revert NoVotingPeriodSet();
    Votes memory v = bountyVotingTracker[bountyId];
    if (block.timestamp >= v.deadline) revert VotingEnded();
  }

  /// =====================
  /// === Initialization ===
  /// =====================
  /// @param _poidhNft The claim NFT contract (must be deployed).
  /// @param _treasury Fee recipient (credited via pull withdrawals).
  /// @param _startClaimIndex The first real claim id; must be `>= 1` (claim id `0` is reserved).
  constructor(address _poidhNft, address _treasury, uint256 _startClaimIndex) {
    if (_treasury == address(0)) revert InvalidTreasury(_treasury);
    if (_poidhNft == address(0) || _poidhNft.code.length == 0) revert InvalidPoidhNft(_poidhNft);
    if (_startClaimIndex == 0) revert InvalidStartClaimIndex();

    poidhNft = IPoidhClaimNFT(_poidhNft);
    treasury = _treasury;

    // Reserve claimId 0..(_startClaimIndex-1) as sentinels by pre-filling.
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

  /// =========================
  /// === Pull withdrawals   ===
  /// =========================
  /// @notice Withdraw the caller's pending balance to `msg.sender`.
  /// @dev Uses CEI and `nonReentrant` to harden against reentrancy during ETH receive hooks.
  function withdraw() external nonReentrant {
    uint256 amount = pendingWithdrawals[msg.sender];
    if (amount == 0) revert NothingToWithdraw();

    pendingWithdrawals[msg.sender] = 0;
    (bool ok,) = msg.sender.call{value: amount}("");
    if (!ok) revert TransferFailed();

    emit Withdrawal(msg.sender, amount);
  }

  /// @notice Withdraw the caller's pending balance to `to`.
  /// @dev Useful when `msg.sender` is a contract that cannot receive ETH directly.
  /// Emits both `Withdrawal` (legacy/indexer compatibility) and `WithdrawalTo` (destination).
  function withdrawTo(address payable to) external nonReentrant {
    if (to == address(0)) revert InvalidWithdrawTo(to);

    uint256 amount = pendingWithdrawals[msg.sender];
    if (amount == 0) revert NothingToWithdraw();

    pendingWithdrawals[msg.sender] = 0;
    (bool ok,) = to.call{value: amount}("");
    if (!ok) revert TransferFailed();

    emit Withdrawal(msg.sender, amount);
    emit WithdrawalTo(msg.sender, to, amount);
  }

  /// =======================
  /// === Bounty Creation  ===
  /// =======================
  /// @notice Create a solo bounty (issuer-only funding; issuer accepts a claim directly).
  /// @dev EOAs only (`msg.sender == tx.origin`) to prevent contract issuers becoming NFT sinks.
  function createSoloBounty(string calldata name, string calldata description)
    external
    payable
    nonReentrant
  {
    if (msg.sender != tx.origin) revert ContractsCannotCreateBounties();
    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();
    _createBounty(name, description);
  }

  /// @notice Create an open bounty (multiple contributors; claim acceptance uses voting).
  /// @dev EOAs only (`msg.sender == tx.origin`) to prevent contract issuers becoming NFT sinks.
  function createOpenBounty(string calldata name, string calldata description)
    external
    payable
    nonReentrant
  {
    if (msg.sender != tx.origin) revert ContractsCannotCreateBounties();
    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();

    uint256 bountyId = _createBounty(name, description);

    // issuer is always participant slot 0
    participants[bountyId].push(msg.sender);
    participantAmounts[bountyId].push(msg.value);
    contributorIndexPlus1[bountyId][msg.sender] = 1; // index 0 => store 1
  }

  /// @dev Internal bounty creation shared by solo + open bounties.
  function _createBounty(string calldata name, string calldata description)
    internal
    returns (uint256 bountyId)
  {
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

  /// =============================
  /// === Open Bounty Funding   ===
  /// =============================
  /// @notice Contribute ETH to an open bounty.
  /// @dev Reverts while voting is active. Enforces `MIN_CONTRIBUTION` and `MAX_PARTICIPANTS`.
  function joinOpenBounty(uint256 bountyId) external payable nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);

    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_CONTRIBUTION) revert MinimumContributionNotMet();

    Bounty storage bounty = bounties[bountyId];
    if (msg.sender == bounty.issuer) revert WrongCaller();

    uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];

    if (idxPlus1 == 0) {
      // New contributor: reuse a free slot if possible, otherwise append.
      uint256 idx;

      uint256[] storage freeSlots = freeParticipantSlots[bountyId];
      if (freeSlots.length > 0) {
        idx = freeSlots[freeSlots.length - 1];
        freeSlots.pop();

        // slot must be vacant
        participants[bountyId][idx] = msg.sender;
        participantAmounts[bountyId][idx] = msg.value;
      } else {
        address[] storage p = participants[bountyId];
        if (p.length >= MAX_PARTICIPANTS) revert MaxParticipantsReached();

        p.push(msg.sender);
        participantAmounts[bountyId].push(msg.value);
        idx = p.length - 1;
      }

      contributorIndexPlus1[bountyId][msg.sender] = idx + 1;
    } else {
      // Existing active contributor: add to their existing slot.
      uint256 idx = idxPlus1 - 1;
      if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
      participantAmounts[bountyId][idx] += msg.value;
    }

    everHadExternalContributor[bountyId] = true;
    bounty.amount += msg.value;

    emit BountyJoined(bountyId, msg.sender, msg.value);
  }

  /// @notice Withdraw the caller's entire contribution from an open bounty (credited to pending).
  /// @dev Reverts while voting is active.
  function withdrawFromOpenBounty(uint256 bountyId) external nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);

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

    // Free slot can be reused by someone else later.
    if (idx != 0) freeParticipantSlots[bountyId].push(idx);

    // Clear index mapping so this address is treated as "new" if it rejoins later.
    contributorIndexPlus1[bountyId][msg.sender] = 0;

    // Optional hygiene (not required for safety due to round-scoped snapshot):
    // voteWeightSnapshot[bountyId][msg.sender] = 0;
    // voteWeightSnapshotRound[bountyId][msg.sender] = 0;

    pendingWithdrawals[msg.sender] += amount;

    emit WithdrawFromOpenBounty(bountyId, msg.sender, amount);
  }

  /// =================
  /// === Cancellation ===
  /// =================
  /// @notice Cancel a solo bounty and credit the issuer refund to pending withdrawals.
  function cancelSoloBounty(uint256 bountyId) external nonReentrant {
    _requireActiveBounty(bountyId);
    if (participants[bountyId].length != 0) revert NotSoloBounty();

    Bounty storage bounty = bounties[bountyId];
    if (msg.sender != bounty.issuer) revert WrongCaller();

    uint256 amount = bounty.amount;

    // Effects
    bounty.claimer = bounty.issuer;
    bounty.amount = 0;

    pendingWithdrawals[msg.sender] += amount;

    emit BountyCancelled(bountyId, msg.sender, amount);
  }

  /// @notice Cancel an open bounty in constant time; contributors must claim refunds themselves.
  function cancelOpenBounty(uint256 bountyId) external nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);

    Bounty storage bounty = bounties[bountyId];
    if (msg.sender != bounty.issuer) revert WrongCaller();

    // Effects: close first
    bounty.claimer = bounty.issuer;

    // Refund issuer immediately (slot 0)
    uint256 issuerAmount = participantAmounts[bountyId][0];
    if (issuerAmount > 0) {
      participantAmounts[bountyId][0] = 0;
      participants[bountyId][0] = address(0);
      bounty.amount -= issuerAmount;
      pendingWithdrawals[bounty.issuer] += issuerAmount;
    }

    emit BountyCancelled(bountyId, msg.sender, issuerAmount);
  }

  /// @notice Claim the caller's refund from a cancelled open bounty (credited to pending).
  function claimRefundFromCancelledOpenBounty(uint256 bountyId) external nonReentrant {
    _requireBountyExists(bountyId);

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

    // slot hygiene
    if (idx != 0) freeParticipantSlots[bountyId].push(idx);
    contributorIndexPlus1[bountyId][msg.sender] = 0;

    pendingWithdrawals[msg.sender] += amount;

    emit RefundClaimed(bountyId, msg.sender, amount);
  }

  /// =====================
  /// === Claim Creation ===
  /// =====================
  /// @notice Create a claim for a bounty and mint the claim NFT into escrow.
  /// @dev Claims are minted to this contract via `PoidhClaimNFT.mintToEscrow` (no `_safeMint`).
  function createClaim(
    uint256 bountyId,
    string calldata name,
    string calldata description,
    string calldata uri
  ) external nonReentrant {
    _requireActiveBounty(bountyId);

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

    emit ClaimCreated(
      claimId, msg.sender, bountyId, bounty.issuer, name, description, block.timestamp
    );
  }

  /// =====================
  /// === Voting (Open)  ===
  /// =====================
  /// @notice Start a new vote round on an open bounty claim (issuer-only).
  /// @dev Snapshots contribution weights at the moment voting starts; joins/withdrawals are
  /// blocked.
  function submitClaimForVote(uint256 bountyId, uint256 claimId) external nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);

    if (claimId >= claimCounter) revert ClaimNotFound();

    Bounty memory bounty = bounties[bountyId];
    if (msg.sender != bounty.issuer) revert WrongCaller();

    Claim memory claim = claims[claimId];
    if (claim.issuer == address(0)) revert ClaimNotFound();
    if (claim.bountyId != bountyId) revert ClaimNotFound();
    if (claim.accepted) revert ClaimAlreadyAccepted();

    // Start new round
    voteRound[bountyId] += 1;
    uint256 roundId = voteRound[bountyId];

    // Snapshot participant weights (round-scoped to prevent stale reuse)
    address[] memory p = participants[bountyId];
    uint256[] memory amounts = participantAmounts[bountyId];

    for (uint256 i = 0; i < p.length; i++) {
      address a = p[i];
      uint256 w = amounts[i];
      if (a != address(0) && w > 0) {
        voteWeightSnapshot[bountyId][a] = w;
        voteWeightSnapshotRound[bountyId][a] = roundId;
      }
    }

    uint256 issuerWeight = amounts[0];
    if (issuerWeight == 0) revert NotActiveParticipant();

    bountyCurrentVotingClaim[bountyId] = claimId;
    uint256 deadline = block.timestamp + votingPeriod;
    bountyVotingTracker[bountyId] = Votes({yes: issuerWeight, no: 0, deadline: deadline});

    // issuer auto-votes YES
    lastVotedRound[bountyId][msg.sender] = roundId;

    emit ClaimSubmittedForVote(bountyId, claimId);
    emit VotingStarted(bountyId, claimId, deadline, issuerWeight);
    emit VoteCast(msg.sender, bountyId, claimId, true, issuerWeight);
  }

  /// @notice Vote for/against the currently submitted claim on an open bounty.
  /// @dev Uses a round-scoped weight snapshot taken at `submitClaimForVote`.
  function voteClaim(uint256 bountyId, bool vote) external nonReentrant {
    _requireBountyExists(bountyId);
    uint256 currentClaim = _requireVoteActive(bountyId);

    if (participants[bountyId].length == 0) revert NotOpenBounty();

    uint256 roundId = voteRound[bountyId];
    if (lastVotedRound[bountyId][msg.sender] == roundId) revert AlreadyVoted();

    // IMPORTANT: round-scoped snapshot check prevents stale weight reuse across rounds.
    if (voteWeightSnapshotRound[bountyId][msg.sender] != roundId) revert NotActiveParticipant();

    uint256 weight = voteWeightSnapshot[bountyId][msg.sender];
    if (weight == 0) revert NotActiveParticipant();

    // Effects
    lastVotedRound[bountyId][msg.sender] = roundId;

    Votes storage v = bountyVotingTracker[bountyId];
    if (vote) v.yes += weight;
    else v.no += weight;

    emit VoteClaim(msg.sender, bountyId, currentClaim); // legacy
    emit VoteCast(msg.sender, bountyId, currentClaim, vote, weight);
  }

  /// @notice Resolve a vote after its deadline (permissionless).
  /// @dev If the vote passes, accepts the claim (finalizes state, credits withdrawals, transfers
  /// NFT).
  function resolveVote(uint256 bountyId) external nonReentrant {
    if (participants[bountyId].length == 0) revert NotOpenBounty();

    uint256 currentClaim = bountyCurrentVotingClaim[bountyId];
    if (currentClaim == 0) revert NoVotingPeriodSet();

    Votes memory v = bountyVotingTracker[bountyId];
    if (block.timestamp < v.deadline) revert VotingOngoing();

    bool passed = v.yes > ((v.no + v.yes) / 2);

    if (passed) {
      _acceptClaim(bountyId, currentClaim);
    } else {
      bountyCurrentVotingClaim[bountyId] = 0;
      delete bountyVotingTracker[bountyId];

      emit ResetVotingPeriod(bountyId);
      emit VotingResolved(bountyId, currentClaim, false, v.yes, v.no);
    }
  }

  /// @notice ABI-compat reset, but cannot discard a winning vote.
  function resetVotingPeriod(uint256 bountyId) external nonReentrant {
    _requireBountyExists(bountyId);
    _requireBountyNotFinalized(bountyId);

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

  /// =====================
  /// === Acceptance     ===
  /// =====================
  /// @notice Accept a claim on a solo bounty, or on an open bounty that never had an external
  /// contributor.
  /// @dev Open bounties with any external contributor must use the vote flow.
  function acceptClaim(uint256 bountyId, uint256 claimId) external nonReentrant {
    _requireActiveBounty(bountyId);

    if (claimId >= claimCounter) revert ClaimNotFound();

    Bounty memory bounty = bounties[bountyId];

    // Solo bounty: issuer can accept
    if (participants[bountyId].length == 0) {
      if (msg.sender != bounty.issuer) revert WrongCaller();
      _acceptClaim(bountyId, claimId);
      return;
    }

    // Open bounty: direct accept ONLY if it never had external contributors.
    if (everHadExternalContributor[bountyId]) revert NotSoloBounty();
    if (msg.sender != bounty.issuer) revert WrongCaller();

    _acceptClaim(bountyId, claimId);
  }

  /// @dev Finalizes the bounty and claim, credits pending withdrawals, then transfers the claim
  /// NFT.
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

    // Effects: finalize BEFORE external calls
    bounty.claimer = claimIssuer;
    bounty.claimId = claimId;
    bounty.amount = 0;

    claim.accepted = true;

    // snapshot vote state (if called via resolveVote)
    uint256 currentVotingClaim = bountyCurrentVotingClaim[bountyId];
    Votes memory voteSnap = bountyVotingTracker[bountyId];

    // Clear voting state
    bountyCurrentVotingClaim[bountyId] = 0;
    delete bountyVotingTracker[bountyId];

    // Pull payments
    pendingWithdrawals[claimIssuer] += payout;
    pendingWithdrawals[treasury] += fee;

    emit ClaimAccepted(bountyId, claimId, claimIssuer, bounty.issuer, bountyAmount, payout, fee);

    // Interaction: transfer NFT out of escrow WITHOUT ERC721Receiver callbacks
    poidhNft.transferFrom(address(this), bounty.issuer, claimId);

    if (currentVotingClaim != 0) {
      emit VotingResolved(bountyId, claimId, true, voteSnap.yes, voteSnap.no);
    }
  }

  /// =====================
  /// === View Helpers   ===
  /// =====================
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

  function getClaimsByBountyId(uint256 bountyId, uint256 offset)
    external
    view
    returns (Claim[] memory)
  {
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

  function getParticipantsPaged(uint256 bountyId, uint256 offset, uint256 limit)
    external
    view
    returns (address[] memory addrs, uint256[] memory amts)
  {
    address[] memory p = participants[bountyId];
    uint256[] memory a = participantAmounts[bountyId];

    if (offset >= p.length) return (new address[](0), new uint256[](0));

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

  /// @dev Prevent accidental ETH transfers that are not attributed to a bounty/refund.
  receive() external payable {
    revert DirectEtherNotAccepted();
  }
}
