// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract PoidhV3CoverageTest is Test {
    PoidhV3 poidh;
    PoidhClaimNFT nft;

    address treasury;
    address issuer;
    address claimant;
    address contributor;
    address other;

    function setUp() public {
        vm.txGasPrice(0);

        treasury = makeAddr("treasury");
        issuer = makeAddr("issuer");
        claimant = makeAddr("claimant");
        contributor = makeAddr("contributor");
        other = makeAddr("other");

        nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
        poidh = new PoidhV3(address(nft), treasury, 1);
        nft.setPoidh(address(poidh));

        vm.deal(issuer, 10_000 ether);
        vm.deal(claimant, 10_000 ether);
        vm.deal(contributor, 10_000 ether);
        vm.deal(other, 10_000 ether);
        vm.deal(treasury, 0);
    }

    function _createSolo(uint256 amount) internal returns (uint256 bountyId) {
        bountyId = poidh.bountyCounter();
        vm.prank(issuer);
        poidh.createSoloBounty{value: amount}("solo", "desc");
    }

    function _createOpen(uint256 amount) internal returns (uint256 bountyId) {
        bountyId = poidh.bountyCounter();
        vm.prank(issuer);
        poidh.createOpenBounty{value: amount}("open", "desc");
    }

    function _createClaim(uint256 bountyId, address who) internal returns (uint256 claimId) {
        claimId = poidh.claimCounter();
        vm.prank(who);
        poidh.createClaim(bountyId, "claim", "desc", "ipfs://x");
    }

    function _mapSlot(uint256 mappingSlot, uint256 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, mappingSlot));
    }

    function _mapArrayElemSlot(uint256 mappingSlot, uint256 key, uint256 index) internal pure returns (bytes32) {
        bytes32 lenSlot = keccak256(abi.encode(key, mappingSlot));
        bytes32 dataSlot = keccak256(abi.encode(lenSlot));
        return bytes32(uint256(dataSlot) + index);
    }

    function _arrayStructBaseSlot(uint256 arraySlot, uint256 index, uint256 structSlots) internal pure returns (bytes32) {
        bytes32 dataSlot = keccak256(abi.encode(arraySlot));
        return bytes32(uint256(dataSlot) + (index * structSlots));
    }

    function test_unpause_allows_state_changes_again() public {
        poidh.pause();

        vm.prank(issuer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        poidh.createSoloBounty{value: 1 ether}("solo", "desc");

        poidh.unpause();

        vm.prank(issuer);
        poidh.createSoloBounty{value: 1 ether}("solo", "desc");
        assertEq(poidh.bountyCounter(), 1);
    }

    function test_withdraw_reverts_nothingToWithdraw() public {
        vm.expectRevert(PoidhV3.NothingToWithdraw.selector);
        poidh.withdraw();
    }

    function test_createOpenBounty_reverts_noEther_and_below_min() public {
        uint256 min = poidh.MIN_BOUNTY_AMOUNT();

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.NoEther.selector);
        poidh.createOpenBounty("open", "desc");

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.MinimumBountyNotMet.selector);
        poidh.createOpenBounty{value: min - 1}("open", "desc");
    }

    function test_bountyNotFound_reverts_in_multiple_entrypoints() public {
        vm.prank(claimant);
        vm.expectRevert(PoidhV3.BountyNotFound.selector);
        poidh.createClaim(0, "claim", "desc", "ipfs://x");

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.BountyNotFound.selector);
        poidh.joinOpenBounty{value: 1 wei}(0);

        vm.expectRevert(PoidhV3.BountyNotFound.selector);
        poidh.cancelSoloBounty(0);

        vm.expectRevert(PoidhV3.BountyNotFound.selector);
        poidh.claimRefundFromCancelledOpenBounty(0);

        vm.expectRevert(PoidhV3.BountyNotFound.selector);
        poidh.voteClaim(0, true);
    }

    function test_joinOpenBounty_reverts_notOpenBounty_on_solo() public {
        _createSolo(1 ether);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotOpenBounty.selector);
        poidh.joinOpenBounty{value: 1 wei}(0);
    }

    function test_cancelSoloBounty_reverts_notSoloBounty_and_wrongCaller() public {
        _createOpen(1 ether);

        vm.expectRevert(PoidhV3.NotSoloBounty.selector);
        poidh.cancelSoloBounty(0);

        _createSolo(1 ether);
        vm.prank(contributor);
        vm.expectRevert(PoidhV3.WrongCaller.selector);
        poidh.cancelSoloBounty(1);
    }

    function test_cancelOpenBounty_reverts_wrongCaller() public {
        _createOpen(1 ether);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.WrongCaller.selector);
        poidh.cancelOpenBounty(0);
    }

    function test_claimRefundFromCancelledOpenBounty_reverts_notOpenBounty_on_solo() public {
        _createSolo(1 ether);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotOpenBounty.selector);
        poidh.claimRefundFromCancelledOpenBounty(0);
    }

    function test_claimRefundFromCancelledOpenBounty_reverts_notActiveParticipant_and_withdrawn_before_cancel() public {
        _createOpen(1 ether);

        vm.prank(contributor);
        poidh.joinOpenBounty{value: 2 ether}(0);

        vm.prank(issuer);
        poidh.cancelOpenBounty(0);

        vm.prank(other);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.claimRefundFromCancelledOpenBounty(0);

        // New bounty: withdraw before cancellation => slot cleared, cannot claim refund.
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 2 ether}(1);
        vm.prank(contributor);
        poidh.withdrawFromOpenBounty(1);
        vm.prank(issuer);
        poidh.cancelOpenBounty(1);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.claimRefundFromCancelledOpenBounty(1);
    }

    function test_claimRefundFromCancelledOpenBounty_reverts_amount_zero_via_state_corruption() public {
        _createOpen(1 ether);

        vm.prank(contributor);
        poidh.joinOpenBounty{value: 2 ether}(0);

        vm.prank(issuer);
        poidh.cancelOpenBounty(0);

        // Force participantAmounts[0][1] = 0 while participants[0][1] is still `contributor`.
        bytes32 slot = _mapArrayElemSlot(11, 0, 1); // participantAmounts slot=11, bountyId=0, idx=1
        vm.store(address(poidh), slot, bytes32(uint256(0)));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.claimRefundFromCancelledOpenBounty(0);
    }

    function test_createClaim_reverts_bountyClaimed() public {
        _createSolo(1 ether);
        _createClaim(0, claimant);

        vm.prank(issuer);
        poidh.acceptClaim(0, 1);

        vm.prank(other);
        vm.expectRevert(PoidhV3.BountyClaimed.selector);
        poidh.createClaim(0, "claim2", "desc", "ipfs://y");
    }

    function test_acceptClaim_reverts_wrongCaller_solo_and_open() public {
        _createSolo(1 ether);
        _createClaim(0, claimant);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.WrongCaller.selector);
        poidh.acceptClaim(0, 1);

        _createOpen(1 ether);
        _createClaim(1, claimant);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.WrongCaller.selector);
        poidh.acceptClaim(1, 2);
    }

    function test_acceptClaim_reverts_claimNotFound_variants() public {
        _createSolo(1 ether);

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimNotFound.selector);
        poidh.acceptClaim(0, 999);

        // claimId 0 is reserved sentinel with issuer == address(0)
        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimNotFound.selector);
        poidh.acceptClaim(0, 0);

        // Wrong bounty: claim belongs to bounty 0, try accept on bounty 1.
        _createSolo(1 ether);
        _createClaim(0, claimant);
        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimNotFound.selector);
        poidh.acceptClaim(1, 1);
    }

    function test_acceptClaim_reverts_insufficientBalance_via_vm_deal() public {
        _createSolo(1 ether);
        _createClaim(0, claimant);

        vm.deal(address(poidh), 0);

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.InsufficientBalance.selector);
        poidh.acceptClaim(0, 1);
    }

    function test_acceptClaim_reverts_claimAlreadyAccepted_via_state_corruption() public {
        _createSolo(1 ether);
        uint256 claimId = _createClaim(0, claimant);

        // Force claims[claimId].accepted = true while bounty is still active.
        bytes32 claimBase = _arrayStructBaseSlot(4, claimId, 8);
        vm.store(address(poidh), bytes32(uint256(claimBase) + 7), bytes32(uint256(1)));

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimAlreadyAccepted.selector);
        poidh.acceptClaim(0, claimId);
    }

    function test_submitClaimForVote_reverts_claimId_ge_counter_wrongCaller_wrongBounty() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);
        _createClaim(0, claimant);

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimNotFound.selector);
        poidh.submitClaimForVote(0, 999);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.WrongCaller.selector);
        poidh.submitClaimForVote(0, 1);

        // Wrong bounty: create a second open bounty, try submit claim from bounty 0.
        _createOpen(1 ether);
        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimNotFound.selector);
        poidh.submitClaimForVote(1, 1);
    }

    function test_submitClaimForVote_reverts_claimAlreadyAccepted_and_issuerWeight_zero_via_state_corruption() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);
        _createClaim(0, claimant);

        // Force claims[1].accepted = true (Claim struct slot 4, 8 slots per element, accepted at offset 7).
        bytes32 claimBase = _arrayStructBaseSlot(4, 1, 8);
        vm.store(address(poidh), bytes32(uint256(claimBase) + 7), bytes32(uint256(1)));

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.ClaimAlreadyAccepted.selector);
        poidh.submitClaimForVote(0, 1);

        // Reset accepted to false and force issuerWeight = 0 for participantAmounts[0][0].
        vm.store(address(poidh), bytes32(uint256(claimBase) + 7), bytes32(uint256(0)));

        bytes32 issuerAmountSlot = _mapArrayElemSlot(11, 0, 0); // participantAmounts[0][0]
        vm.store(address(poidh), issuerAmountSlot, bytes32(uint256(0)));

        vm.prank(issuer);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.submitClaimForVote(0, 1);
    }

    function test_resetVotingPeriod_reverts_votingOngoing_before_deadline() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        uint256 claimId = _createClaim(0, claimant);

        vm.prank(issuer);
        poidh.submitClaimForVote(0, claimId);

        vm.expectRevert(PoidhV3.VotingOngoing.selector);
        poidh.resetVotingPeriod(0);
    }

    function test_voteClaim_reverts_noVotingPeriodSet_and_notOpenBounty_defensive() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NoVotingPeriodSet.selector);
        poidh.voteClaim(0, true);

        // Defensive: force a solo bounty into a voting state, then ensure voteClaim rejects it.
        _createSolo(1 ether);

        // bountyCurrentVotingClaim[1] = 1
        vm.store(address(poidh), _mapSlot(12, 1), bytes32(uint256(1)));
        // voteRound[1] = 1 (so it doesn't trip AlreadyVoted on default 0)
        vm.store(address(poidh), _mapSlot(14, 1), bytes32(uint256(1)));
        // bountyVotingTracker[1].deadline = block.timestamp + 1 days (Votes.deadline is offset 2)
        bytes32 voteBase = _mapSlot(13, 1);
        vm.store(address(poidh), bytes32(uint256(voteBase) + 2), bytes32(uint256(block.timestamp + 1 days)));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotOpenBounty.selector);
        poidh.voteClaim(1, true);
    }

    function test_voteClaim_reverts_notActiveParticipant_when_participants_slot_corrupted() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);
        uint256 claimId = _createClaim(0, claimant);

        vm.prank(issuer);
        poidh.submitClaimForVote(0, claimId);

        // Corrupt participants[0][1] to a different address.
        bytes32 slot = _mapArrayElemSlot(10, 0, 1); // participants slot=10, bountyId=0, idx=1
        vm.store(address(poidh), slot, bytes32(uint256(uint160(other))));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.voteClaim(0, true);
    }

    function test_voteClaim_reverts_notActiveParticipant_weight_zero_via_state_corruption() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);
        _createClaim(0, claimant);

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        // Force contributor weight to 0 while their participant slot is still active.
        bytes32 contribAmtSlot = _mapArrayElemSlot(11, 0, 1);
        vm.store(address(poidh), contribAmtSlot, bytes32(uint256(0)));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.voteClaim(0, true);
    }

    function test_voteClaim_reverts_notActiveParticipant_when_not_in_participants() public {
        _createOpen(1 ether);
        _createClaim(0, claimant);

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        vm.prank(other);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.voteClaim(0, true);
    }

    function test_resolveVote_reverts_notOpenBounty_and_noVotingPeriodSet() public {
        _createSolo(1 ether);
        vm.expectRevert(PoidhV3.NotOpenBounty.selector);
        poidh.resolveVote(0);

        _createOpen(1 ether);
        vm.expectRevert(PoidhV3.NoVotingPeriodSet.selector);
        poidh.resolveVote(1);
    }

    function test_resetVotingPeriod_reverts_notOpenBounty_noVoting_and_finalized() public {
        _createSolo(1 ether);
        vm.expectRevert(PoidhV3.NotOpenBounty.selector);
        poidh.resetVotingPeriod(0);

        _createOpen(1 ether);
        vm.expectRevert(PoidhV3.NoVotingPeriodSet.selector);
        poidh.resetVotingPeriod(1);

        // BountyClosed via bountyNotFinalized
        vm.prank(issuer);
        poidh.cancelSoloBounty(0);
        vm.expectRevert(PoidhV3.BountyClosed.selector);
        poidh.resetVotingPeriod(0);

        // BountyClaimed via bountyNotFinalized
        _createSolo(1 ether);
        uint256 claimId = _createClaim(2, claimant);
        vm.prank(issuer);
        poidh.acceptClaim(2, claimId);
        vm.expectRevert(PoidhV3.BountyClaimed.selector);
        poidh.resetVotingPeriod(2);
    }

    function test_joinOpenBounty_reverts_notActiveParticipant_when_slot_corrupted() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        // Corrupt participants[0][1] to a different address.
        bytes32 slot = _mapArrayElemSlot(10, 0, 1); // participants slot=10, bountyId=0, idx=1
        vm.store(address(poidh), slot, bytes32(uint256(uint160(other))));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.joinOpenBounty{value: 1 wei}(0);
    }

    function test_withdrawFromOpenBounty_reverts_notActiveParticipant_when_amount_zero_but_slot_active() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        // Force participantAmounts[0][1] = 0 while participants[0][1] is still `contributor`.
        bytes32 amtSlot = _mapArrayElemSlot(11, 0, 1);
        vm.store(address(poidh), amtSlot, bytes32(uint256(0)));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.withdrawFromOpenBounty(0);
    }

    function test_withdrawFromOpenBounty_reverts_notActiveParticipant_when_participants_slot_corrupted() public {
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(0);

        // Corrupt participants[0][1] to a different address.
        bytes32 slot = _mapArrayElemSlot(10, 0, 1); // participants slot=10, bountyId=0, idx=1
        vm.store(address(poidh), slot, bytes32(uint256(uint160(other))));

        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.withdrawFromOpenBounty(0);
    }

    function test_view_helpers_and_receive() public {
        // create >10 bounties to exercise pagination
        for (uint256 i = 0; i < 12; i++) {
            _createSolo(1 ether);
        }
        assertEq(poidh.getBountiesLength(), 12);

        PoidhV3.Bounty[] memory recent = poidh.getBounties(0);
        assertEq(recent.length, 10);
        assertEq(recent[0].id, 11);
        assertEq(recent[9].id, 2);

        // offset beyond length => no loop iterations (still returns length 10 default array)
        PoidhV3.Bounty[] memory emptyLike = poidh.getBounties(999);
        assertEq(emptyLike.length, 10);

        // user bounties pagination
        PoidhV3.Bounty[] memory byUser = poidh.getBountiesByUser(issuer, 0);
        assertEq(byUser.length, 10);
        assertEq(byUser[0].id, 11);

        // claims pagination
        _createSolo(1 ether);
        for (uint256 i = 0; i < 12; i++) {
            _createClaim(12, claimant);
        }
        PoidhV3.Claim[] memory byBounty = poidh.getClaimsByBountyId(12, 0);
        assertEq(byBounty.length, 10);
        assertEq(byBounty[0].id, 12);

        PoidhV3.Claim[] memory byUserClaims = poidh.getClaimsByUser(claimant, 0);
        assertEq(byUserClaims.length, 10);

        // participants paging
        _createOpen(1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 1 ether}(13);
        vm.prank(other);
        poidh.joinOpenBounty{value: 1 ether}(13);

        (address[] memory pAll, uint256[] memory aAll) = poidh.getParticipants(13);
        assertEq(pAll.length, 3);
        assertEq(aAll.length, 3);

        (address[] memory p0, uint256[] memory a0) = poidh.getParticipantsPaged(13, 0, 100);
        assertEq(p0.length, 3);
        assertEq(a0.length, 3);

        (address[] memory pEmpty, uint256[] memory aEmpty) = poidh.getParticipantsPaged(13, 999, 1);
        assertEq(pEmpty.length, 0);
        assertEq(aEmpty.length, 0);

        // receive() coverage
        (bool ok,) = address(poidh).call{value: 1 wei}("");
        assertTrue(ok);
    }
}
