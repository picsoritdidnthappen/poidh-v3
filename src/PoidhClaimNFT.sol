// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
  ERC721URIStorage
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";

/// @title PoidhClaimNFT
/// @notice Minimal ERC721 for POIDH claim NFTs.
/// @dev Designed to avoid callback-based reentrancy:
/// - Uses `_mint` (not `_safeMint`).
/// - PoidhV3 mints to itself as escrow, then transfers with `transferFrom` (not
/// `safeTransferFrom`).
contract PoidhClaimNFT is ERC721URIStorage, Ownable2Step, IPoidhClaimNFT {
  /// @dev Reverts for unauthorized mint attempts.
  error NotPoidh();
  /// @dev Reverts when wiring to address(0).
  error InvalidPoidhAddress();
  /// @dev Reverts when wiring to a non-contract address.
  error PoidhMustBeContract();

  /// @notice Emitted when the authorized POIDH contract is changed.
  event PoidhSet(address indexed oldPoidh, address indexed newPoidh);

  /// @notice The PoidhV3 contract authorized to mint claim NFTs.
  address public poidh;

  /// @param name_ ERC721 name.
  /// @param symbol_ ERC721 symbol.
  constructor(string memory name_, string memory symbol_)
    ERC721(name_, symbol_)
    Ownable(msg.sender)
  {}

  /// @notice Sets the authorized POIDH contract that can mint claim NFTs.
  /// @dev Use a multisig as owner. Call this once after deploying PoidhV3.
  function setPoidh(address newPoidh) external onlyOwner {
    _setPoidh(newPoidh);
  }

  /// @inheritdoc IPoidhClaimNFT
  function mintToEscrow(uint256 tokenId, string calldata uri) external {
    _revertIfNotPoidh();
    _mint(poidh, tokenId);
    _setTokenURI(tokenId, uri);
  }

  /// @dev Owner-only wiring function used after deployment.
  function _setPoidh(address newPoidh) internal {
    if (newPoidh == address(0)) revert InvalidPoidhAddress();

    // Optional safety check: ensure this is a deployed contract
    if (newPoidh.code.length == 0) revert PoidhMustBeContract();

    emit PoidhSet(poidh, newPoidh);
    poidh = newPoidh;
  }

  function _revertIfNotPoidh() internal view {
    if (msg.sender != poidh) revert NotPoidh();
  }
}
