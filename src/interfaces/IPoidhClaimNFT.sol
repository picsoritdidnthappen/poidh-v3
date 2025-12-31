// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title IPoidhClaimNFT
/// @notice Minimal interface for the POIDH claim NFT contract used by `PoidhV3`.
interface IPoidhClaimNFT is IERC721 {
  /// @notice Mint a claim NFT to the POIDH contract (escrow) and set its tokenURI.
  /// @dev Implementations should avoid ERC721Receiver callback reentrancy by using `_mint`
  /// rather than `_safeMint`.
  /// @param tokenId The token id to mint (typically the PoidhV3 claim id).
  /// @param uri The tokenURI to store for the minted token.
  function mintToEscrow(uint256 tokenId, string calldata uri) external;
}
