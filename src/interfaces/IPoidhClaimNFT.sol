// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IPoidhClaimNFT is IERC721 {
    function mintToEscrow(uint256 tokenId, string calldata uri) external;
}
