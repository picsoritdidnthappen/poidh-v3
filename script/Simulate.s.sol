// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract Simulate is Script {
  struct VotingParams {
    uint256 seed;
    uint256 runs;
    uint256 participants;
    uint256 yesBps; // 0..10_000
    uint256 issuerAmount;
    uint256 minJoin;
    uint256 maxJoin;
  }

  struct VotingSetup {
    PoidhV3 poidh;
    PoidhClaimNFT nft;
    address issuer;
    address treasury;
    address claimant;
    address[] participants;
    string runsPath;
    string summaryPath;
  }

  struct RunResult {
    uint256 yes;
    uint256 no;
    uint256 total;
    uint256 fee;
    uint256 payout;
    bool passed;
  }

  struct VotingAgg {
    uint256 passedCount;
    uint256 yesSum;
    uint256 noSum;
    uint256 totalSum;
  }

  function runVoting(uint256 seed, uint256 runs, uint256 participants, uint256 yesBps) external {
    VotingParams memory p = VotingParams({
      seed: seed,
      runs: runs,
      participants: participants,
      yesBps: yesBps,
      issuerAmount: 1 ether,
      minJoin: 0.000_01 ether,
      maxJoin: 1 ether
    });
    _runVoting(p);
  }

  function runVotingWithParams(
    uint256 seed,
    uint256 runs,
    uint256 participants,
    uint256 yesBps,
    uint256 issuerAmount,
    uint256 minJoin,
    uint256 maxJoin
  ) external {
    VotingParams memory p = VotingParams({
      seed: seed,
      runs: runs,
      participants: participants,
      yesBps: yesBps,
      issuerAmount: issuerAmount,
      minJoin: minJoin,
      maxJoin: maxJoin
    });
    _runVoting(p);
  }

  function runSlotExhaustion() external {
    (PoidhV3 poidh,, address issuer) = _deploy();

    vm.deal(issuer, 100 ether);

    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: 1 ether}("open", "desc");
    uint256 bountyId = poidh.bountyCounter() - 1;

    uint256 sybils = poidh.MAX_PARTICIPANTS() - 1; // issuer occupies index 0
    for (uint256 i = 0; i < sybils; i++) {
      address sybil = vm.addr(10_000 + i);
      vm.deal(sybil, 1 ether);

      vm.prank(sybil);
      poidh.joinOpenBounty{value: poidh.MIN_CONTRIBUTION()}(bountyId);
    }

    // Drain back the dust; array length remains MAX_PARTICIPANTS.
    for (uint256 i = 0; i < sybils; i++) {
      address sybil = vm.addr(10_000 + i);
      vm.prank(sybil);
      poidh.withdrawFromOpenBounty(bountyId);
    }

    address newcomer = vm.addr(4242);
    vm.deal(newcomer, 1 ether);

    bool blocked;
    vm.prank(newcomer);
    try poidh.joinOpenBounty{value: poidh.MIN_CONTRIBUTION()}(bountyId) {
      blocked = false;
    } catch (bytes memory reason) {
      // forge-lint: disable-next-line(unsafe-typecast)
      blocked = (reason.length >= 4 && bytes4(reason) == PoidhV3.MaxParticipantsReached.selector);
    }

    console2.log("slotExhaustion_blockedNewJoin", blocked);
    (address[] memory addrs,) = poidh.getParticipantsPaged(bountyId, 0, type(uint256).max);
    console2.log("participantsArrayLength", addrs.length);
  }

  function _runVoting(VotingParams memory p) internal {
    if (p.runs == 0) return;
    if (p.yesBps > 10_000) revert("yesBps>10000");
    if (p.issuerAmount == 0) revert("issuerAmount=0");
    if (p.minJoin == 0) revert("minJoin=0");
    if (p.maxJoin < p.minJoin) revert("maxJoin<minJoin");
    if (p.participants > 99) p.participants = 99;

    VotingSetup memory s = _setupVoting(p);

    VotingAgg memory agg;
    for (uint256 r = 0; r < p.runs; r++) {
      RunResult memory res = _runVotingOnce(s, p, r);

      agg.yesSum += res.yes;
      agg.noSum += res.no;
      agg.totalSum += res.total;
      if (res.passed) agg.passedCount++;

      _writeRunLine(s.runsPath, r, p.participants, res);
    }

    _writeVotingSummary(s, p, agg);

    console2.log("wrote", s.runsPath);
    console2.log("wrote", s.summaryPath);
    console2.log("passBps", (agg.passedCount * 10_000) / p.runs);
  }

  function _setupVoting(VotingParams memory p) internal returns (VotingSetup memory s) {
    (s.poidh, s.nft, s.issuer) = _deploy();
    s.treasury = s.poidh.treasury();
    s.claimant = vm.addr(3);

    vm.deal(s.issuer, 10_000 ether);
    vm.deal(s.claimant, 10_000 ether);

    s.participants = new address[](p.participants);
    for (uint256 i = 0; i < p.participants; i++) {
      s.participants[i] = vm.addr(1000 + i);
      vm.deal(s.participants[i], 10_000 ether);
    }

    vm.createDir("cache/simulations", true);
    string memory ts = vm.toString(vm.unixTime());
    s.runsPath = string.concat("cache/simulations/voting-", ts, ".jsonl");
    s.summaryPath = string.concat("cache/simulations/voting-summary-", ts, ".json");
    vm.writeFile(s.runsPath, "");
  }

  function _runVotingOnce(VotingSetup memory s, VotingParams memory p, uint256 r)
    internal
    returns (RunResult memory res)
  {
    uint256 snap = vm.snapshot();

    uint256 bountyId = _createOpenBounty(s.poidh, s.issuer, p.issuerAmount);
    uint256 joinSum = _joinParticipants(s, p, r, bountyId);
    uint256 total = p.issuerAmount + joinSum;

    uint256 claimId = _createClaimAndStartVote(s, bountyId);

    (uint256 yes, uint256 no) = _castVotes(s, p, r, bountyId);

    res = _resolveAndCheck(s, bountyId, claimId, yes, no, total);
    vm.revertTo(snap);
  }

  function _createOpenBounty(PoidhV3 poidh, address issuer, uint256 issuerAmount)
    internal
    returns (uint256 bountyId)
  {
    vm.prank(issuer, issuer);
    poidh.createOpenBounty{value: issuerAmount}("open", "desc");
    bountyId = poidh.bountyCounter() - 1;
  }

  function _joinParticipants(
    VotingSetup memory s,
    VotingParams memory p,
    uint256 r,
    uint256 bountyId
  ) internal returns (uint256 joinSum) {
    uint256 participantCount = p.participants;
    for (uint256 i = 0; i < participantCount; i++) {
      uint256 joinAmt = bound(_rand(p.seed, r, i, 0), p.minJoin, p.maxJoin);
      vm.prank(s.participants[i]);
      s.poidh.joinOpenBounty{value: joinAmt}(bountyId);
      joinSum += joinAmt;
    }
  }

  function _createClaimAndStartVote(VotingSetup memory s, uint256 bountyId)
    internal
    returns (uint256 claimId)
  {
    vm.prank(s.claimant);
    s.poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
    claimId = s.poidh.claimCounter() - 1;

    vm.prank(s.issuer);
    s.poidh.submitClaimForVote(bountyId, claimId);
  }

  function _castVotes(VotingSetup memory s, VotingParams memory p, uint256 r, uint256 bountyId)
    internal
    returns (uint256 yes, uint256 no)
  {
    yes = p.issuerAmount;

    uint256 participantCount = p.participants;
    for (uint256 i = 0; i < participantCount; i++) {
      uint256 joinAmt = bound(_rand(p.seed, r, i, 0), p.minJoin, p.maxJoin);
      bool voteYes = (_rand(p.seed, r, i, 1) % 10_000) < p.yesBps;
      if (voteYes) yes += joinAmt;
      else no += joinAmt;

      vm.prank(s.participants[i]);
      s.poidh.voteClaim(bountyId, voteYes);
    }
  }

  function _resolveAndCheck(
    VotingSetup memory s,
    uint256 bountyId,
    uint256 claimId,
    uint256 yes,
    uint256 no,
    uint256 total
  ) internal returns (RunResult memory res) {
    bool expectedPass = yes > ((yes + no) / 2);

    vm.warp(block.timestamp + s.poidh.votingPeriod() + 1);
    s.poidh.resolveVote(bountyId);

    (,,,, uint256 remaining, address claimer,,) = s.poidh.bounties(bountyId);
    bool passed = claimer == s.claimant;
    if (passed != expectedPass) revert("voteMismatch");

    uint256 fee;
    uint256 payout;
    if (passed) {
      fee = (total * s.poidh.FEE_BPS()) / s.poidh.BPS_DENOM();
      payout = total - fee;

      if (remaining != 0) revert("remainingNotZero");
      if (s.poidh.pendingWithdrawals(s.claimant) != payout) revert("badPayout");
      if (s.poidh.pendingWithdrawals(s.treasury) != fee) revert("badFee");
      if (s.nft.ownerOf(claimId) != s.issuer) revert("nftNotDelivered");
    } else {
      if (remaining != total) revert("remainingMismatch");
      if (s.poidh.pendingWithdrawals(s.claimant) != 0) revert("unexpectedPayout");
      if (s.poidh.pendingWithdrawals(s.treasury) != 0) revert("unexpectedFee");
      if (s.nft.ownerOf(claimId) != address(s.poidh)) revert("nftNotEscrowed");
    }

    res = RunResult({yes: yes, no: no, total: total, fee: fee, payout: payout, passed: passed});
  }

  function _writeRunLine(
    string memory runsPath,
    uint256 r,
    uint256 participantCount,
    RunResult memory res
  ) internal {
    string memory obj = string.concat("run-", vm.toString(r));
    vm.serializeUint(obj, "run", r);
    vm.serializeUint(obj, "participants", participantCount);
    vm.serializeUint(obj, "yes", res.yes);
    vm.serializeUint(obj, "no", res.no);
    vm.serializeUint(obj, "total", res.total);
    vm.serializeUint(obj, "fee", res.fee);
    vm.serializeUint(obj, "payout", res.payout);
    string memory json = vm.serializeBool(obj, "passed", res.passed);
    vm.writeLine(runsPath, json);
  }

  function _writeVotingSummary(VotingSetup memory s, VotingParams memory p, VotingAgg memory agg)
    internal
  {
    uint256 passBps = (agg.passedCount * 10_000) / p.runs;

    string memory summary = "summary";
    vm.serializeUint(summary, "seed", p.seed);
    vm.serializeUint(summary, "runs", p.runs);
    vm.serializeUint(summary, "participants", p.participants);
    vm.serializeUint(summary, "yesBps", p.yesBps);
    vm.serializeUint(summary, "issuerAmount", p.issuerAmount);
    vm.serializeUint(summary, "minJoin", p.minJoin);
    vm.serializeUint(summary, "maxJoin", p.maxJoin);
    vm.serializeUint(summary, "passedCount", agg.passedCount);
    vm.serializeUint(summary, "passBps", passBps);
    vm.serializeUint(summary, "yesSum", agg.yesSum);
    vm.serializeUint(summary, "noSum", agg.noSum);
    vm.serializeUint(summary, "totalSum", agg.totalSum);
    vm.serializeString(summary, "runsPath", s.runsPath);
    string memory summaryJson = vm.serializeString(summary, "network", "local");
    vm.writeFile(s.summaryPath, summaryJson);
  }

  function _deploy() internal returns (PoidhV3 poidh, PoidhClaimNFT nft, address issuer) {
    issuer = vm.addr(1);
    address treasury = vm.addr(2);

    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = new PoidhV3(address(nft), treasury, 1);
    nft.setPoidh(address(poidh));
  }

  function _rand(uint256 seed, uint256 runIndex, uint256 actorIndex, uint256 salt)
    internal
    pure
    returns (uint256)
  {
    return uint256(keccak256(abi.encode(seed, runIndex, actorIndex, salt)));
  }
}
