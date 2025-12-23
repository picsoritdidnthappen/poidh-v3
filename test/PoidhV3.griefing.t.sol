// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoidhV3} from "../src/PoidhV3.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

/// @title PoidhV3 Economic Griefing & Edge Case Tests
/// @notice Tests for non-exploit attack vectors: griefing, MEV, admin abuse, config footguns
/// @dev These tests document KNOWN LIMITATIONS and potential improvements

// ============================================================================
// HELPER CONTRACTS
// ============================================================================

/// @notice Contract that reverts on ETH receive - causes withdraw to fail
contract RevertingReceiver {
    PoidhV3 public poidh;

    constructor(address _poidh) {
        poidh = PoidhV3(payable(_poidh));
    }

    function createBounty() external payable {
        poidh.createSoloBounty{value: msg.value}("Test", "Desc");
    }

    function cancelBounty(uint256 bountyId) external {
        poidh.cancelSoloBounty(bountyId);
    }

    function withdraw() external {
        poidh.withdraw();
    }

    // Revert on any ETH received
    receive() external payable {
        revert("I don't accept ETH");
    }
}

/// @notice Contract that accepts ETH but can't transfer NFTs
contract NFTSinkContract {
    // No onERC721Received, but can still receive via transferFrom
    receive() external payable {}
}

/// @notice Contract that creates bounties (issuer is a contract)
contract ContractIssuer {
    PoidhV3 public poidh;

    constructor(address _poidh) {
        poidh = PoidhV3(payable(_poidh));
    }

    function createSoloBounty() external payable returns (uint256) {
        poidh.createSoloBounty{value: msg.value}("Contract Bounty", "Desc");
        return poidh.bountyCounter() - 1;
    }

    function acceptClaim(uint256 bountyId, uint256 claimId) external {
        poidh.acceptClaim(bountyId, claimId);
    }

    function withdraw() external {
        poidh.withdraw();
    }

    receive() external payable {}
}

// ============================================================================
// MAIN TEST CONTRACT
// ============================================================================
contract PoidhV3GriefingTest is Test {
    PoidhV3 public poidh;
    PoidhClaimNFT public nft;

    address public treasury;
    address public issuer;
    address public claimant;

    function setUp() public {
        treasury = makeAddr("treasury");
        issuer = makeAddr("issuer");
        claimant = makeAddr("claimant");

        vm.deal(issuer, 100 ether);
        vm.deal(claimant, 100 ether);

        nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
        poidh = new PoidhV3(address(nft), treasury, 1);
        nft.setPoidh(address(poidh));
    }

    // ========================================================================
    // 1. ECONOMIC GRIEFING - 1-wei Force Voting Attack
    // ========================================================================
    function test_GRIEFING_1wei_forces_voting() public {
        // Issuer creates open bounty
        vm.prank(issuer);
        poidh.createOpenBounty{value: 10 ether}("Big Bounty", "Description");
        uint256 bountyId = 0;

        // Griefer joins with just 1 wei - this is the MINIMUM possible
        address griefer = makeAddr("griefer");
        vm.deal(griefer, 1 wei);
        vm.prank(griefer);
        poidh.joinOpenBounty{value: 1 wei}(bountyId);

        // Now everHadExternalContributor is TRUE
        assertTrue(poidh.everHadExternalContributor(bountyId), "Flag should be set");

        // Even if griefer withdraws...
        vm.prank(griefer);
        poidh.withdrawFromOpenBounty(bountyId);

        // Flag is STILL true - issuer is permanently forced into voting
        assertTrue(poidh.everHadExternalContributor(bountyId), "Flag persists after withdrawal");

        // Issuer creates a claim
        vm.prank(claimant);
        poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

        // Direct accept should fail
        vm.prank(issuer);
        vm.expectRevert(PoidhV3.NotSoloBounty.selector);
        poidh.acceptClaim(bountyId, 1);

        console.log("[CONFIRMED GRIEFING] 1-wei join permanently forces voting");
        console.log("[COST TO GRIEFER] 1 wei + gas (~50k gas)");
        console.log("[IMPACT] Issuer must go through 48h voting even if griefer withdrew");
        console.log("");
        console.log("[MITIGATION] Add MIN_CONTRIBUTION_AMOUNT for joinOpenBounty");
    }

    // ========================================================================
    // 2. ECONOMIC GRIEFING - Vote Buying / Whale Attack
    // ========================================================================
    function test_GRIEFING_whale_vote_swing() public {
        // Setup: Issuer creates bounty, small contributors join
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");
        uint256 bountyId = 0;

        // Small contributors join
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        vm.prank(alice);
        poidh.joinOpenBounty{value: 0.5 ether}(bountyId);
        vm.prank(bob);
        poidh.joinOpenBounty{value: 0.5 ether}(bountyId);

        // Total: issuer 1 ETH, alice 0.5 ETH, bob 0.5 ETH = 2 ETH total

        // Claim and start voting
        vm.prank(claimant);
        poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

        vm.prank(issuer);
        poidh.submitClaimForVote(bountyId, 1);
        // Issuer auto-votes YES with 1 ETH weight

        // Alice and Bob vote NO
        vm.prank(alice);
        poidh.voteClaim(bountyId, false);
        vm.prank(bob);
        poidh.voteClaim(bountyId, false);

        // Current: YES=1 ETH, NO=1 ETH - vote would fail

        // WHALE enters at last second with massive contribution
        // Note: This would require whale to join BEFORE voting starts
        // because joinOpenBounty reverts during voting

        // Let's show what happens if whale was already in
        console.log("[INFO] Whale attack requires joining BEFORE vote starts");
        console.log("[INFO] joinOpenBounty blocked during voting (VotingOngoing)");
        console.log("[PARTIAL MITIGATION] Voting freeze prevents last-second joins");
        console.log("");
        console.log("[REMAINING RISK] Whale can join before vote, then vote-swing");
        console.log("[MITIGATION] Snapshot weights at vote start, or quadratic voting");
    }

    // ========================================================================
    // 3. ECONOMIC GRIEFING - Last-Second Join Before Vote
    // ========================================================================
    function test_GRIEFING_join_before_vote_frontrun() public {
        // Setup
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");
        uint256 bountyId = 0;

        vm.prank(claimant);
        poidh.createClaim(bountyId, "Claim", "Desc", "ipfs://x");

        // Attacker sees submitClaimForVote in mempool and frontruns with join
        address attacker = makeAddr("attacker");
        vm.deal(attacker, 10 ether);

        // Attacker joins BEFORE vote starts (in same block, earlier tx)
        vm.prank(attacker);
        poidh.joinOpenBounty{value: 5 ether}(bountyId);

        // Now issuer submits vote - attacker already in with 5 ETH
        vm.prank(issuer);
        poidh.submitClaimForVote(bountyId, 1);

        // Attacker has more weight than issuer (5 ETH vs 1 ETH)
        // Attacker votes NO
        vm.prank(attacker);
        poidh.voteClaim(bountyId, false);

        // Check vote state
        (uint256 yes, uint256 no,) = poidh.bountyVotingTracker(bountyId);
        assertEq(yes, 1 ether, "Issuer YES weight");
        assertEq(no, 5 ether, "Attacker NO weight");

        // Vote will fail because NO > YES
        vm.warp(block.timestamp + 2 days + 1);
        poidh.resolveVote(bountyId);

        // Bounty not accepted
        (,,,,,address claimer,,) = poidh.bounties(bountyId);
        assertEq(claimer, address(0), "Bounty should not be claimed");

        console.log("[CONFIRMED GRIEFING] Frontrun join can swing vote");
        console.log("[COST] Attacker must lock ETH for voting period");
        console.log("[MITIGATION] Snapshot weights at vote start");
    }

    // ========================================================================
    // 4. ADMIN ABUSE - Pause Blocks Withdraw
    // ========================================================================
    function test_GRIEFING_pause_blocks_withdraw() public {
        // User creates and cancels bounty - has pending withdrawal
        vm.prank(issuer);
        poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

        vm.prank(issuer);
        poidh.cancelSoloBounty(0);

        assertEq(poidh.pendingWithdrawals(issuer), 1 ether);

        // Malicious/compromised owner pauses
        poidh.pause();

        // User cannot withdraw
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        poidh.withdraw();

        console.log("[CONFIRMED RISK] Paused contract blocks all withdrawals");
        console.log("[IMPACT] Users' funds locked until unpause");
        console.log("[MITIGATION] Use multisig owner, timelock, or exempt withdraw from pause");
    }

    // ========================================================================
    // 5. CONFIG FOOTGUN - Wrong Treasury Address
    // ========================================================================
    function test_FOOTGUN_wrong_treasury_permanent_loss() public {
        // Deploy with wrong treasury (e.g., zero address blocked, but typo address isn't)
        address wrongTreasury = address(0xdead);

        PoidhClaimNFT newNft = new PoidhClaimNFT("test", "TEST");
        PoidhV3 badPoidh = new PoidhV3(address(newNft), wrongTreasury, 1);
        newNft.setPoidh(address(badPoidh));

        // Fees will go to wrong address forever (immutable)
        assertEq(badPoidh.treasury(), wrongTreasury);

        console.log("[CONFIG RISK] Treasury is immutable");
        console.log("[IMPACT] Wrong address = permanent fee loss");
        console.log("[MITIGATION] Deploy checklist, CI validation, consider upgradeable treasury");
    }

    // ========================================================================
    // 6. NFT SINK - Contract Issuer Can't Move NFT
    // ========================================================================
    function test_EDGE_CASE_nft_sink_contract_issuer() public {
        // Deploy a contract that creates bounties
        ContractIssuer contractIssuer = new ContractIssuer(address(poidh));
        vm.deal(address(contractIssuer), 10 ether);

        // Contract creates bounty
        vm.prank(address(contractIssuer));
        contractIssuer.createSoloBounty{value: 1 ether}();

        // Someone claims
        vm.prank(claimant);
        poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

        // Contract accepts claim - NFT transferred to contract
        vm.prank(address(contractIssuer));
        contractIssuer.acceptClaim(0, 1);

        // NFT is now owned by contract
        assertEq(nft.ownerOf(1), address(contractIssuer));

        // ContractIssuer has no way to transfer the NFT!
        // (It doesn't implement transferFrom logic)

        console.log("[EDGE CASE] Contract issuers receive NFTs via transferFrom");
        console.log("[IMPACT] NFT may be stuck if contract lacks transfer capability");
        console.log("[NOTE] This is expected behavior - contracts should implement NFT handling");
    }

    // ========================================================================
    // 7. DOS - Claim Spam / Storage Bloat
    // ========================================================================
    function test_DOS_claim_spam() public {
        vm.prank(issuer);
        poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

        // Spammer creates many claims - only costs gas
        address spammer = makeAddr("spammer");
        uint256 spamCount = 100;

        uint256 gasStart = gasleft();
        for (uint256 i = 0; i < spamCount; i++) {
            vm.prank(spammer);
            poidh.createClaim(0, "SPAM SPAM SPAM SPAM SPAM", "SPAM SPAM SPAM", "ipfs://spam");
        }
        uint256 gasUsed = gasStart - gasleft();

        console.log("[DOS VECTOR] Claim spam possible");
        console.log("Claims created:", spamCount);
        console.log("Total gas used:", gasUsed);
        console.log("Gas per claim:", gasUsed / spamCount);
        console.log("");
        console.log("[IMPACT] Storage bloat, indexer load, UI clutter");
        console.log("[MITIGATION] Claim deposit/bond, per-bounty cap, issuer can close claims");
    }

    // ========================================================================
    // 8. DOS - Participant Slot Exhaustion
    // ========================================================================
    function test_DOS_participant_slot_exhaustion() public {
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

        // Attacker fills all participant slots with dust
        for (uint256 i = 1; i < 100; i++) {
            address attacker = address(uint160(i + 5000));
            vm.deal(attacker, 0.01 ether);
            vm.prank(attacker);
            poidh.joinOpenBounty{value: 0.001 ether}(0);
        }

        // Legitimate user cannot join
        address legitUser = makeAddr("legit");
        vm.deal(legitUser, 10 ether);
        vm.prank(legitUser);
        vm.expectRevert(PoidhV3.MaxParticipantsReached.selector);
        poidh.joinOpenBounty{value: 5 ether}(0);

        console.log("[DOS VECTOR] Participant slots can be exhausted");
        console.log("[COST TO ATTACKER] 99 * 0.001 ETH = 0.099 ETH + gas");
        console.log("[IMPACT] Blocks legitimate high-value contributors");
        console.log("[MITIGATION] Minimum contribution, issuer can close funding");
    }

    // ========================================================================
    // 9. SELF-DOS - Receiver Revert on Withdraw
    // ========================================================================
    function test_SELF_DOS_receiver_revert() public {
        // Deploy reverting receiver
        RevertingReceiver badReceiver = new RevertingReceiver(address(poidh));
        vm.deal(address(badReceiver), 10 ether);

        // Create and cancel bounty
        vm.prank(address(badReceiver));
        badReceiver.createBounty{value: 1 ether}();

        vm.prank(address(badReceiver));
        badReceiver.cancelBounty(0);

        // Funds are pending
        assertEq(poidh.pendingWithdrawals(address(badReceiver)), 1 ether);

        // But withdraw fails because receiver reverts
        vm.prank(address(badReceiver));
        vm.expectRevert(PoidhV3.TransferFailed.selector);
        badReceiver.withdraw();

        // Funds stuck forever
        assertEq(poidh.pendingWithdrawals(address(badReceiver)), 1 ether);

        console.log("[SELF-DOS] Contracts that revert on receive can't withdraw");
        console.log("[IMPACT] Funds permanently locked for that address");
        console.log("[MITIGATION] Add withdrawTo(address payable to) function");
    }

    // ========================================================================
    // 10. MEV - Vote Resolution Timing
    // ========================================================================
    function test_MEV_vote_resolution_timing() public {
        // Setup voting
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

        address contributor = makeAddr("contributor");
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 0.5 ether}(0);

        vm.prank(claimant);
        poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        // Contributor votes NO
        vm.prank(contributor);
        poidh.voteClaim(0, false);

        // Fast forward to exactly deadline
        vm.warp(block.timestamp + 2 days);

        // Anyone can resolve immediately - MEV bot opportunity
        address mevBot = makeAddr("mevBot");
        vm.prank(mevBot);
        poidh.resolveVote(0);

        console.log("[MEV OPPORTUNITY] Anyone can call resolveVote after deadline");
        console.log("[IMPACT] Bots can frontrun resolution for timing advantages");
        console.log("[NOTE] This is generally acceptable - permissionless finalization");
        console.log("[MITIGATION IF NEEDED] Commit-reveal voting, extended window");
    }

    // ========================================================================
    // 11. EDGE CASE - Issuer withdraws ALL, bounty has 0 amount
    // ========================================================================
    function test_EDGE_CASE_issuer_contribution_matters() public {
        // Create open bounty
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

        // Add contributor
        address contributor = makeAddr("contributor");
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 0.5 ether}(0);

        // Issuer cannot withdraw (by design)
        vm.prank(issuer);
        vm.expectRevert(PoidhV3.IssuerCannotWithdraw.selector);
        poidh.withdrawFromOpenBounty(0);

        console.log("[VERIFIED] Issuer cannot withdraw from open bounty");
        console.log("[DESIGN] Prevents bounty from becoming 0-amount while active");
    }

    // ========================================================================
    // 12. EDGE CASE - Vote with withdrawn weight still tracked
    // ========================================================================
    function test_EDGE_CASE_vote_weight_after_withdraw() public {
        // Setup
        vm.prank(issuer);
        poidh.createOpenBounty{value: 1 ether}("Bounty", "Description");

        address contributor = makeAddr("contributor");
        vm.deal(contributor, 1 ether);
        vm.prank(contributor);
        poidh.joinOpenBounty{value: 0.5 ether}(0);

        // Contributor withdraws BEFORE voting starts
        vm.prank(contributor);
        poidh.withdrawFromOpenBounty(0);

        // Start voting
        vm.prank(claimant);
        poidh.createClaim(0, "Claim", "Desc", "ipfs://x");

        vm.prank(issuer);
        poidh.submitClaimForVote(0, 1);

        // Contributor tries to vote - should fail (no weight)
        vm.prank(contributor);
        vm.expectRevert(PoidhV3.NotActiveParticipant.selector);
        poidh.voteClaim(0, true);

        console.log("[VERIFIED] Withdrawn contributors cannot vote");
    }

    // ========================================================================
    // 13. EDGE CASE - Multiple claims, accept specific one
    // ========================================================================
    function test_EDGE_CASE_multiple_claims_accept_any() public {
        vm.prank(issuer);
        poidh.createSoloBounty{value: 1 ether}("Bounty", "Description");

        // Multiple claimants
        address claimant1 = makeAddr("claimant1");
        address claimant2 = makeAddr("claimant2");
        address claimant3 = makeAddr("claimant3");

        vm.prank(claimant1);
        poidh.createClaim(0, "Claim1", "Desc", "ipfs://1");

        vm.prank(claimant2);
        poidh.createClaim(0, "Claim2", "Desc", "ipfs://2");

        vm.prank(claimant3);
        poidh.createClaim(0, "Claim3", "Desc", "ipfs://3");

        // Issuer can accept any claim (e.g., claim 2)
        vm.prank(issuer);
        poidh.acceptClaim(0, 2);

        // Claimant2 gets payout
        uint256 expectedPayout = 1 ether - (1 ether * 250) / 10000;
        assertEq(poidh.pendingWithdrawals(claimant2), expectedPayout);

        // Other claimants get nothing
        assertEq(poidh.pendingWithdrawals(claimant1), 0);
        assertEq(poidh.pendingWithdrawals(claimant3), 0);

        console.log("[VERIFIED] Issuer can accept any valid claim");
    }

    // ========================================================================
    // SUMMARY
    // ========================================================================
    function test_GRIEFING_SUMMARY() public pure {
        console.log("");
        console.log("====================================================");
        console.log("    POIDH V3 GRIEFING & EDGE CASE TEST SUMMARY      ");
        console.log("====================================================");
        console.log("");
        console.log("CONFIRMED GRIEFING VECTORS:");
        console.log("  [1] 1-wei join forces voting permanently");
        console.log("  [2] Frontrun join before vote can swing outcome");
        console.log("  [3] Claim spam bloats storage (no cost to attacker)");
        console.log("  [4] Participant slot exhaustion with dust");
        console.log("");
        console.log("ADMIN/CONFIG RISKS:");
        console.log("  [5] Pause blocks withdraw (soft rug potential)");
        console.log("  [6] Wrong treasury = permanent fee loss");
        console.log("");
        console.log("SELF-DOS RISKS:");
        console.log("  [7] Contracts that revert on receive can't withdraw");
        console.log("");
        console.log("MEV OPPORTUNITIES:");
        console.log("  [8] Anyone can call resolveVote (acceptable)");
        console.log("");
        console.log("RECOMMENDED MITIGATIONS:");
        console.log("  - MIN_CONTRIBUTION_AMOUNT for joinOpenBounty");
        console.log("  - Claim deposit/bond or per-bounty cap");
        console.log("  - withdrawTo(address) for stuck contracts");
        console.log("  - Multisig/timelock for owner");
        console.log("  - Snapshot weights at vote start");
        console.log("====================================================");
    }
}
