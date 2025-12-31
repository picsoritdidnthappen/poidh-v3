// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract PoidhV3Handler is Test {
  PoidhV3 public immutable poidh;
  PoidhClaimNFT public immutable nft;

  address public immutable treasury;
  address public immutable issuer;
  address[] public actors;

  uint256 public constant MAX_BOUNTIES = 25;

  // track last-voted per bounty+actor to reduce reverts
  mapping(uint256 => mapping(address => uint256)) public lastVotedRound;

  constructor(
    PoidhV3 poidh_,
    PoidhClaimNFT nft_,
    address treasury_,
    address issuer_,
    address[] memory actors_
  ) {
    poidh = poidh_;
    nft = nft_;
    treasury = treasury_;
    issuer = issuer_;
    actors = actors_;
  }

  function _actor(uint256 seed) internal view returns (address) {
    return actors[seed % actors.length];
  }

  function createSolo(uint96 amountRaw) external {
    if (poidh.bountyCounter() >= MAX_BOUNTIES) return;

    uint256 min = poidh.MIN_BOUNTY_AMOUNT();
    uint256 amount = bound(uint256(amountRaw), min, 10 ether);

    vm.prank(issuer, issuer);
    poidh.createSoloBounty{value: amount}("solo", "desc");
  }

  function createOpen(uint96 amountRaw) external {
    if (poidh.bountyCounter() >= MAX_BOUNTIES) return;

    uint256 min = poidh.MIN_BOUNTY_AMOUNT();
    uint256 amount = bound(uint256(amountRaw), min, 10 ether);

    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: amount}("open", "desc");
  }

  function joinOpen(uint256 bountyIdRaw, uint96 amountRaw, uint256 actorSeed) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    (address[] memory p,) = poidh.getParticipants(bountyId);
    if (p.length == 0) return;

    address participant = _actor(actorSeed);
    if (participant == issuer) return;

    uint256 min = poidh.MIN_CONTRIBUTION();
    uint256 amount = bound(uint256(amountRaw), min, 1 ether);

    vm.prank(participant);
    poidh.joinOpenBounty{value: amount}(bountyId);
  }

  function withdrawFromOpen(uint256 bountyIdRaw, uint256 actorSeed) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    (address[] memory p, uint256[] memory a) = poidh.getParticipants(bountyId);
    if (p.length == 0) return;

    address participant = _actor(actorSeed);
    if (participant == issuer) return;

    // Find slot and skip if not active
    bool active;
    for (uint256 i = 0; i < p.length; i++) {
      if (p[i] == participant && a[i] > 0) {
        active = true;
        break;
      }
    }
    if (!active) return;

    vm.prank(participant);
    poidh.withdrawFromOpenBounty(bountyId);
  }

  function cancelSolo(uint256 bountyIdRaw) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    (address[] memory p,) = poidh.getParticipants(bountyId);
    if (p.length != 0) return;

    vm.prank(issuer);
    poidh.cancelSoloBounty(bountyId);
  }

  function cancelOpen(uint256 bountyIdRaw) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    (address[] memory p,) = poidh.getParticipants(bountyId);
    if (p.length == 0) return;

    vm.prank(issuer);
    poidh.cancelOpenBounty(bountyId);
  }

  function claimRefund(uint256 bountyIdRaw, uint256 actorSeed) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    (address[] memory p, uint256[] memory a) = poidh.getParticipants(bountyId);
    if (p.length == 0) return;

    // only for cancelled open bounties
    (, address bountyIssuer,,, uint256 amount, address claimer,,) = poidh.bounties(bountyId);
    if (claimer != bountyIssuer) return;
    if (amount == 0) return;

    address participant = _actor(actorSeed);
    if (participant == issuer) return;

    bool active;
    for (uint256 i = 0; i < p.length; i++) {
      if (p[i] == participant && a[i] > 0) {
        active = true;
        break;
      }
    }
    if (!active) return;

    vm.prank(participant);
    poidh.claimRefundFromCancelledOpenBounty(bountyId);
  }

  function createClaim(uint256 bountyIdRaw, uint256 actorSeed) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    address claimant = _actor(actorSeed);

    // Skip finalized bounties
    (, address bountyIssuer,,, uint256 amount, address claimer,,) = poidh.bounties(bountyId);
    if (claimant == bountyIssuer) return;
    if (claimer != address(0)) return;
    if (amount == 0) return;

    vm.prank(claimant);
    poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
  }

  function submitForVote(uint256 bountyIdRaw, uint256 claimIdRaw) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    if (poidh.bountyCurrentVotingClaim(bountyId) != 0) return;

    (address[] memory p,) = poidh.getParticipants(bountyId);
    if (p.length == 0) return;

    // only bother with claimIds that exist
    uint256 claimCounter = poidh.claimCounter();
    if (claimCounter == 0) return;
    uint256 claimId = claimIdRaw % claimCounter;
    if (claimId == 0) return; // reserved sentinel

    // ensure claim exists for this bounty and is unaccepted
    (, address claimIssuer, uint256 claimBountyId,,,,, bool accepted) = poidh.claims(claimId);
    if (claimIssuer == address(0)) return;
    if (accepted) return;
    if (claimBountyId != bountyId) return;

    vm.prank(issuer);
    poidh.submitClaimForVote(bountyId, claimId);
  }

  function vote(uint256 bountyIdRaw, bool support, uint256 actorSeed) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    uint256 currentClaim = poidh.bountyCurrentVotingClaim(bountyId);
    if (currentClaim == 0) return;

    (,, uint256 deadline) = poidh.bountyVotingTracker(bountyId);
    if (deadline == 0) return;
    if (block.timestamp >= deadline) return;

    address voter = _actor(actorSeed);
    if (voter == issuer) return; // issuer auto-votes YES

    uint256 roundId = poidh.voteRound(bountyId);
    if (lastVotedRound[bountyId][voter] == roundId) return;

    (address[] memory p, uint256[] memory a) = poidh.getParticipants(bountyId);
    bool active;
    for (uint256 i = 0; i < p.length; i++) {
      if (p[i] == voter && a[i] > 0) {
        active = true;
        break;
      }
    }
    if (!active) return;

    vm.prank(voter);
    poidh.voteClaim(bountyId, support);
    lastVotedRound[bountyId][voter] = roundId;
  }

  function resolve(uint256 bountyIdRaw) external {
    uint256 bountyId = bountyIdRaw % (poidh.bountyCounter() + 1);
    if (bountyId >= poidh.bountyCounter()) return;

    uint256 currentClaim = poidh.bountyCurrentVotingClaim(bountyId);
    if (currentClaim == 0) return;

    (,, uint256 deadline) = poidh.bountyVotingTracker(bountyId);
    if (deadline == 0) return;
    if (block.timestamp < deadline) return;

    poidh.resolveVote(bountyId);
  }

  function withdrawPending(uint256 actorSeed) external {
    address who = _actor(actorSeed);
    uint256 pending = poidh.pendingWithdrawals(who);
    if (pending == 0) return;

    vm.prank(who);
    poidh.withdraw();
  }
}

contract PoidhV3InvariantTest is StdInvariant, Test {
  PoidhV3 poidh;
  PoidhClaimNFT nft;
  PoidhV3Handler handler;

  address treasury;
  address issuer;

  function setUp() public {
    vm.txGasPrice(0);

    treasury = makeAddr("treasury");
    issuer = makeAddr("issuer");

    address[] memory actors = new address[](5);
    actors[0] = makeAddr("alice");
    actors[1] = makeAddr("bob");
    actors[2] = makeAddr("carol");
    actors[3] = makeAddr("dave");
    actors[4] = makeAddr("erin");

    for (uint256 i = 0; i < actors.length; i++) {
      vm.deal(actors[i], 1000 ether);
    }
    vm.deal(issuer, 1000 ether);

    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));

    handler = new PoidhV3Handler(poidh, nft, treasury, issuer, actors);
    targetContract(address(handler));
  }

  function invariant_noPendingWithdrawalsToZeroAddress() public view {
    assertEq(poidh.pendingWithdrawals(address(0)), 0);
  }

  function invariant_claimedBountiesFinalized_and_nftDelivered() public view {
    uint256 bountyCount = poidh.bountyCounter();
    for (uint256 i = 0; i < bountyCount; i++) {
      (, address bountyIssuer,,, uint256 amount, address claimer,, uint256 claimId) =
        poidh.bounties(i);

      // Claimed bounties must be fully finalized.
      if (claimer != address(0) && claimer != bountyIssuer) {
        assertEq(amount, 0);
        assertTrue(claimId != 0);

        (, address claimIssuer, uint256 claimBountyId,,,,, bool accepted) = poidh.claims(claimId);
        assertEq(claimBountyId, i);
        assertEq(claimIssuer, claimer);
        assertTrue(accepted);
        assertEq(nft.ownerOf(claimId), bountyIssuer);
      }
    }
  }

  function invariant_openBountyAmountMatchesParticipantSums_unless_claimed() public view {
    uint256 bountyCount = poidh.bountyCounter();
    for (uint256 i = 0; i < bountyCount; i++) {
      (, address bountyIssuer,,, uint256 amount, address claimer,,) = poidh.bounties(i);
      (address[] memory p, uint256[] memory a) = poidh.getParticipants(i);

      if (p.length == 0) continue;
      if (claimer != address(0) && claimer != bountyIssuer) continue; // claimed: participantAmounts
      // are historical

      uint256 sum;
      for (uint256 j = 0; j < a.length; j++) {
        sum += a[j];
      }
      assertEq(sum, amount);
    }
  }

  function invariant_votingState_is_consistent() public view {
    uint256 bountyCount = poidh.bountyCounter();
    for (uint256 i = 0; i < bountyCount; i++) {
      uint256 currentClaim = poidh.bountyCurrentVotingClaim(i);
      (uint256 yes, uint256 no, uint256 deadline) = poidh.bountyVotingTracker(i);

      if (currentClaim == 0) {
        assertEq(yes, 0);
        assertEq(no, 0);
        assertEq(deadline, 0);
        continue;
      }

      assertTrue(deadline != 0);
      assertTrue(currentClaim < poidh.claimCounter());

      (, address claimIssuer, uint256 claimBountyId,,,,, bool accepted) = poidh.claims(currentClaim);
      assertTrue(claimIssuer != address(0));
      assertEq(claimBountyId, i);
      assertFalse(accepted);
    }
  }
}
