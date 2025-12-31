// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoidhClaimNFT} from "../src/PoidhClaimNFT.sol";

contract DummyPoidh {}

contract PoidhClaimNFTTest is Test {
  PoidhClaimNFT nft;

  address notOwner = address(0xB0B);
  address poidh;

  function setUp() public {
    nft = new PoidhClaimNFT("poidh claims v3", "POIDH3");
    poidh = address(new DummyPoidh());
  }

  function test_setPoidh_onlyOwner() public {
    vm.prank(notOwner);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
    nft.setPoidh(poidh);
  }

  function test_setPoidh_reverts_zero_address() public {
    vm.expectRevert(PoidhClaimNFT.InvalidPoidhAddress.selector);
    nft.setPoidh(address(0));
  }

  function test_mintToEscrow_onlyPoidh() public {
    vm.expectRevert(PoidhClaimNFT.NotPoidh.selector);
    nft.mintToEscrow(1, "ipfs://x");
  }

  function test_mintToEscrow_mints_to_poidh() public {
    nft.setPoidh(poidh);

    vm.prank(poidh);
    nft.mintToEscrow(1, "ipfs://x");

    assertEq(nft.ownerOf(1), poidh);
    assertEq(nft.tokenURI(1), "ipfs://x");
  }
}
