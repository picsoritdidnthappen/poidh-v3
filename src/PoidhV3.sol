// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";

contract PoidhV3 is ReentrancyGuard {
  uint256 public constant FEE_BPS = 250;
  uint256 public constant BPS_DENOM = 10_000;
  uint256 public immutable MIN_BOUNTY_AMOUNT;
  uint256 public immutable MIN_CONTRIBUTION;
  uint256 public constant MAX_PARTICIPANTS = 150;
  uint256 public votingPeriod = 2 days;
  address public immutable treasury;
  IPoidhClaimNFT public immutable poidhNft;

  struct Bounty {
    uint256 id; address issuer; string name; string description;
    uint256 amount; address claimer; uint256 createdAt; uint256 claimId;
  }
  struct Claim {
    uint256 id; address issuer; uint256 bountyId; address bountyIssuer;
    string name; string description; uint256 createdAt; bool accepted;
  }
  struct Votes { uint256 yes; uint256 no; uint256 deadline; }

  Bounty[] public bounties;
  Claim[] public claims;
  uint256 public bountyCounter;
  uint256 public claimCounter;

  mapping(address => uint256[]) public userBounties;
  mapping(address => uint256[]) public userClaims;
  mapping(uint256 => uint256[]) public bountyClaims;
  mapping(uint256 => address[]) public participants;
  mapping(uint256 => uint256[]) public participantAmounts;
  mapping(uint256 => uint256[]) private freeParticipantSlots;
  mapping(uint256 => mapping(address => uint256)) private contributorIndexPlus1;
  mapping(uint256 => bool) public everHadExternalContributor;
  mapping(uint256 => uint256) public bountyCurrentVotingClaim;
  mapping(uint256 => Votes) public bountyVotingTracker;
  mapping(uint256 => uint256) public voteRound;
  mapping(uint256 => mapping(address => uint256)) private lastVotedRound;
  mapping(uint256 => mapping(address => uint256)) public voteWeightSnapshot;
  mapping(uint256 => mapping(address => uint256)) private voteWeightSnapshotRound;
  mapping(address => uint256) public pendingWithdrawals;

  event BountyCreated(uint256 indexed id, address indexed issuer, string title, string description, uint256 amount, uint256 createdAt, bool isOpenBounty, uint256 round);
  event ClaimCreated(uint256 indexed id, address indexed issuer, uint256 indexed bountyId, address bountyIssuer, string title, string description, uint256 createdAt, string imageUri, uint256 round);
  event ClaimAccepted(uint256 indexed bountyId, uint256 indexed claimId, address indexed claimIssuer, address bountyIssuer, uint256 bountyAmount, uint256 payout, uint256 fee, uint256 round);
  event BountyJoined(uint256 indexed bountyId, address indexed participant, uint256 amount, uint256 latestBountyBalance, uint256 round);
  event BountyCancelled(uint256 indexed bountyId, address indexed issuer, uint256 issuerRefund, uint256 round);
  event WithdrawFromOpenBounty(uint256 indexed bountyId, address indexed participant, uint256 amount, uint256 latestBountyAmount, uint256 round);
  event Withdrawal(address indexed user, uint256 amount);
  event WithdrawalTo(address indexed user, address indexed to, uint256 amount);
  event VotingStarted(uint256 indexed bountyId, uint256 indexed claimId, uint256 deadline, uint256 issuerYesWeight, uint256 round);
  event VoteCast(address indexed voter, uint256 indexed bountyId, uint256 indexed claimId, bool support, uint256 weight, uint256 round);
  event VotingResolved(uint256 indexed bountyId, uint256 indexed claimId, bool passed, uint256 yes, uint256 no, uint256 round);
  event RefundClaimed(uint256 indexed bountyId, address indexed participant, uint256 amount, uint256 round);

  error NoEther(); error MinimumBountyNotMet(); error MinimumContributionNotMet();
  error BountyNotFound(); error ClaimNotFound(); error VotingOngoing(); error VotingEnded();
  error NoVotingPeriodSet(); error BountyClaimed(); error BountyClosed(); error NotOpenBounty();
  error NotSoloBounty(); error WrongCaller(); error IssuerCannotClaim(); error IssuerCannotWithdraw();
  error NotActiveParticipant(); error AlreadyVoted(); error ClaimAlreadyAccepted();
  error NothingToWithdraw(); error TransferFailed(); error InsufficientBalance();
  error MaxParticipantsReached(); error NotCancelledOpenBounty(); error VoteWouldPass();
  error InvalidStartClaimIndex(); error ContractsCannotCreateBounties();
  error InvalidTreasury(address treasury); error InvalidPoidhNft(address poidhNft);
  error InvalidWithdrawTo(address to); error DirectEtherNotAccepted();
  error InvalidMinBountyAmount(uint256 amount); error InvalidMinContribution(uint256 amount);

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
    if (bountyCurrentVotingClaim[bountyId] != 0) revert VotingOngoing();
    Bounty storage bounty = bounties[bountyId];
    if (bounty.claimer == bounty.issuer) revert BountyClosed();
    if (bounty.claimer != address(0)) revert BountyClaimed();
  }
  function _requireOpenBounty(uint256 bountyId) internal view {
    if (participants[bountyId].length == 0) revert NotOpenBounty();
  }
  function _requireVoteActive(uint256 bountyId) internal view returns (uint256 currentClaim) {
    currentClaim = bountyCurrentVotingClaim[bountyId];
    if (currentClaim == 0) revert NoVotingPeriodSet();
    Votes memory v = bountyVotingTracker[bountyId];
    if (block.timestamp >= v.deadline) revert VotingEnded();
  }

  constructor(address _poidhNft, address _treasury, uint256 _startClaimIndex, uint256 _minBountyAmount, uint256 _minContribution) {
    if (_treasury == address(0)) revert InvalidTreasury(_treasury);
    if (_poidhNft == address(0) || _poidhNft.code.length == 0) revert InvalidPoidhNft(_poidhNft);
    if (_startClaimIndex == 0) revert InvalidStartClaimIndex();
    if (_minBountyAmount == 0) revert InvalidMinBountyAmount(_minBountyAmount);
    if (_minContribution == 0) revert InvalidMinContribution(_minContribution);
    poidhNft = IPoidhClaimNFT(_poidhNft);
    treasury = _treasury;
    MIN_BOUNTY_AMOUNT = _minBountyAmount;
    MIN_CONTRIBUTION = _minContribution;
    claimCounter = _startClaimIndex;
    for (uint256 i = 0; i < _startClaimIndex; i++) {
      claims.push(Claim({id: i, issuer: address(0), bountyId: 0, bountyIssuer: address(0), name: "", description: "", createdAt: 0, accepted: false}));
    }
  }

  function withdraw() external nonReentrant {
    uint256 amount = pendingWithdrawals[msg.sender];
    if (amount == 0) revert NothingToWithdraw();
    pendingWithdrawals[msg.sender] = 0;
    (bool ok,) = msg.sender.call{value: amount}("");
    if (!ok) revert TransferFailed();
    emit Withdrawal(msg.sender, amount);
  }

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

  function createSoloBounty(string calldata name, string calldata description) external payable nonReentrant {
    if (msg.sender != tx.origin) revert ContractsCannotCreateBounties();
    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();
    _createBounty(name, description, false);
  }

  function createOpenBounty(string calldata name, string calldata description) external payable nonReentrant {
    if (msg.sender != tx.origin) revert ContractsCannotCreateBounties();
    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_BOUNTY_AMOUNT) revert MinimumBountyNotMet();
    uint256 bountyId = _createBounty(name, description, true);
    participants[bountyId].push(msg.sender);
    participantAmounts[bountyId].push(msg.value);
    contributorIndexPlus1[bountyId][msg.sender] = 1;
  }

  function _createBounty(string calldata name, string calldata description, bool isOpenBounty) internal returns (uint256 bountyId) {
    bountyId = bountyCounter;
    bounties.push(Bounty({id: bountyId, issuer: msg.sender, name: name, description: description, amount: msg.value, claimer: address(0), createdAt: block.timestamp, claimId: 0}));
    userBounties[msg.sender].push(bountyId);
    bountyCounter++;
    emit BountyCreated(bountyId, msg.sender, name, description, msg.value, block.timestamp, isOpenBounty, voteRound[bountyId]);
  }

  function joinOpenBounty(uint256 bountyId) external payable nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);
    if (msg.value == 0) revert NoEther();
    if (msg.value < MIN_CONTRIBUTION) revert MinimumContributionNotMet();
    Bounty storage bounty = bounties[bountyId];
    if (msg.sender == bounty.issuer) revert WrongCaller();
    uint256 idxPlus1 = contributorIndexPlus1[bountyId][msg.sender];
    if (idxPlus1 == 0) {
      uint256 idx;
      uint256[] storage freeSlots = freeParticipantSlots[bountyId];
      if (freeSlots.length > 0) {
        idx = freeSlots[freeSlots.length - 1];
        freeSlots.pop();
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
      uint256 idx = idxPlus1 - 1;
      if (participants[bountyId][idx] != msg.sender) revert NotActiveParticipant();
      participantAmounts[bountyId][idx] += msg.value;
    }
    everHadExternalContributor[bountyId] = true;
    bounty.amount += msg.value;
    emit BountyJoined(bountyId, msg.sender, msg.value, bounty.amount, voteRound[bountyId]);
  }

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
    participantAmounts[bountyId][idx] = 0;
    participants[bountyId][idx] = address(0);
    bounty.amount -= amount;
    if (idx != 0) freeParticipantSlots[bountyId].push(idx);
    contributorIndexPlus1[bountyId][msg.sender] = 0;
    pendingWithdrawals[msg.sender] += amount;
    emit WithdrawFromOpenBounty(bountyId, msg.sender, amount, bounty.amount, voteRound[bountyId]);
  }

  function cancelSoloBounty(uint256 bountyId) external nonReentrant {
    _requireActiveBounty(bountyId);
    if (participants[bountyId].length != 0) revert NotSoloBounty();
    Bounty storage bounty = bounties[bountyId];
    if (msg.sender != bounty.issuer) revert WrongCaller();
    uint256 amount = bounty.amount;
    bounty.claimer = bounty.issuer;
    bounty.amount = 0;
    pendingWithdrawals[msg.sender] += amount;
    emit BountyCancelled(bountyId, msg.sender, amount, voteRound[bountyId]);
  }

  function cancelOpenBounty(uint256 bountyId) external nonReentrant {
    _requireActiveBounty(bountyId);
    _requireOpenBounty(bountyId);
    Bounty storage bounty = bounties[bountyId];
    if (msg.sender != bounty.issuer) revert WrongCaller();
    bounty.claimer = bounty.issuer;
    uint256 issuerAmount = participantAmounts[bountyId][0];
    if (issuerAmount > 0) {
      participantAmounts[bountyId][0] = 0;
      participants[bountyId][0] = address(0);
      bounty.amount -= issuerAmount;
      pendingWithdrawals[bounty.issuer] += issuerAmount;
    }
    emit BountyCancelled(bountyId, msg.sender, issuerAmount, voteRound[bountyId]);
  }

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
    if (idx != 0) freeParticipantSlots[bountyId].push(idx);
    contributorIndexPlus1[bountyId][msg.sender] = 0;
    pendingWithdrawals[msg.sender] += amount;
    emit RefundClaimed(bountyId, msg.sender, amount, voteRound[bountyId]);
  }

  function createClaim(uint256 bountyId, string calldata name, string calldata description, string calldata uri) external nonReentrant {
    _requireActiveBounty(bountyId);
    address bountyIssuer = bounties[bountyId].issuer;
    if (msg.sender == bountyIssuer) revert IssuerCannotClaim();
    uint256 claimId = claimCounter;
    uint256 round = voteRound[bountyId];
    claims.push(Claim({id: claimId, issuer: msg.sender, bountyId: bountyId, bountyIssuer: bountyIssuer, name: name, description: description, createdAt: block.timestamp, accepted: false}));
    poidhNft.mintToEscrow(claimId, uri);
    userClaims[msg.sender].push(claimId);
    bountyClaims[bountyId].push(claimId);
    claimCounter++;
    emit ClaimCreated(claimId, msg.sender, bountyId, bountyIssuer, name, description, block.timestamp, uri, round);
  }

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
    voteRound[bountyId] += 1;
    uint256 roundId = voteRound[bountyId];
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
    lastVotedRound[bountyId][msg.sender] = roundId;
    emit VotingStarted(bountyId, claimId, deadline, issuerWeight, roundId);
  }

  function voteClaim(uint256 bountyId, bool vote) external nonReentrant {
    _requireBountyExists(bountyId);
    uint256 currentClaim = _requireVoteActive(bountyId);
    if (participants[bountyId].length == 0) revert NotOpenBounty();
    uint256 roundId = voteRound[bountyId];
    if (lastVotedRound[bountyId][msg.sender] == roundId) revert AlreadyVoted();
    if (voteWeightSnapshotRound[bountyId][msg.sender] != roundId) revert NotActiveParticipant();
    uint256 weight = voteWeightSnapshot[bountyId][msg.sender];
    if (weight == 0) revert NotActiveParticipant();
    lastVotedRound[bountyId][msg.sender] = roundId;
    Votes storage v = bountyVotingTracker[bountyId];
    if (vote) v.yes += weight;
    else v.no += weight;
    emit VoteCast(msg.sender, bountyId, currentClaim, vote, weight, roundId);
  }

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
      emit VotingResolved(bountyId, currentClaim, false, v.yes, v.no, voteRound[bountyId]);
    }
  }

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
    emit VotingResolved(bountyId, currentClaim, false, v.yes, v.no, voteRound[bountyId]);
  }

  function acceptClaim(uint256 bountyId, uint256 claimId) external nonReentrant {
    _requireActiveBounty(bountyId);
    if (claimId >= claimCounter) revert ClaimNotFound();
    Bounty memory bounty = bounties[bountyId];
    if (participants[bountyId].length == 0) {
      if (msg.sender != bounty.issuer) revert WrongCaller();
      _acceptClaim(bountyId, claimId);
      return;
    }
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
    address bountyIssuer = bounty.issuer;
    uint256 bountyAmount = bounty.amount;
    uint256 round = voteRound[bountyId];
    uint256 fee = (bountyAmount * FEE_BPS) / BPS_DENOM;
    uint256 payout = bountyAmount - fee;
    bounty.claimer = claimIssuer;
    bounty.claimId = claimId;
    bounty.amount = 0;
    claim.accepted = true;
    uint256 currentVotingClaim = bountyCurrentVotingClaim[bountyId];
    Votes memory voteSnap = bountyVotingTracker[bountyId];
    bountyCurrentVotingClaim[bountyId] = 0;
    delete bountyVotingTracker[bountyId];
    pendingWithdrawals[claimIssuer] += payout;
    pendingWithdrawals[treasury] += fee;
    emit ClaimAccepted(bountyId, claimId, claimIssuer, bountyIssuer, bountyAmount, payout, fee, round);
    poidhNft.transferFrom(address(this), bountyIssuer, claimId);
    if (currentVotingClaim != 0) {
      emit VotingResolved(bountyId, claimId, true, voteSnap.yes, voteSnap.no, round);
    }
  }

  function getBountiesLength() external view returns (uint256) { return bounties.length; }

  function getBounties(uint256 offset) external view returns (Bounty[] memory) {
    Bounty[] memory result = new Bounty[](10);
    uint256 counter;
    for (uint256 i = bounties.length; i > offset && counter < 10; i--) { result[counter] = bounties[i - 1]; counter++; }
    return result;
  }

  function getClaimsByBountyId(uint256 bountyId, uint256 offset) external view returns (Claim[] memory) {
    uint256[] memory ids = bountyClaims[bountyId];
    Claim[] memory result = new Claim[](10);
    uint256 counter;
    for (uint256 i = ids.length; i > offset && counter < 10; i--) { result[counter] = claims[ids[i - 1]]; counter++; }
    return result;
  }

  function getBountiesByUser(address user, uint256 offset) external view returns (Bounty[] memory) {
    uint256[] memory ids = userBounties[user];
    Bounty[] memory result = new Bounty[](10);
    uint256 counter;
    for (uint256 i = ids.length; i > offset && counter < 10; i--) { result[counter] = bounties[ids[i - 1]]; counter++; }
    return result;
  }

  function getClaimsByUser(address user, uint256 offset) external view returns (Claim[] memory) {
    uint256[] memory ids = userClaims[user];
    Claim[] memory result = new Claim[](10);
    uint256 counter;
    for (uint256 i = ids.length; i > offset && counter < 10; i--) { result[counter] = claims[ids[i - 1]]; counter++; }
    return result;
  }

  function getParticipants(uint256 bountyId) external view returns (address[] memory, uint256[] memory) {
    return (participants[bountyId], participantAmounts[bountyId]);
  }

  function getParticipantsPaged(uint256 bountyId, uint256 offset, uint256 limit) external view returns (address[] memory addrs, uint256[] memory amts) {
    address[] memory p = participants[bountyId];
    uint256[] memory a = participantAmounts[bountyId];
    if (offset >= p.length) return (new address[](0), new uint256[](0));
    uint256 end = offset + limit;
    if (end > p.length) end = p.length;
    uint256 n = end - offset;
    addrs = new address[](n);
    amts = new uint256[](n);
    for (uint256 i = 0; i < n; i++) { addrs[i] = p[offset + i]; amts[i] = a[offset + i]; }
  }

  receive() external payable { revert DirectEtherNotAccepted(); }
}
