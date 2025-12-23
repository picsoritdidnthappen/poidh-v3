// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PoidhClaimNFT
/// @notice Minimal ERC721 for POIDH claim NFTs. Designed to avoid callback-based reentrancy:
///         - Uses `_mint` (not `_safeMint`).
///         - POIDH contract mints to itself as escrow, then transfers with `transferFrom`.
contract PoidhClaimNFT is ERC721URIStorage, Ownable2Step {
    error NotPoidh();
    error InvalidPoidhAddress();

    event PoidhSet(address indexed oldPoidh, address indexed newPoidh);

    address public poidh;

    modifier onlyPoidh() {
        if (msg.sender != poidh) revert NotPoidh();
        _;
    }

    constructor(string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {}

    /// @notice Sets the authorized POIDH contract that can mint claim NFTs.
    /// @dev Use a multisig as owner. Call this once after deploying PoidhV3.
    function setPoidh(address newPoidh) external onlyOwner {
        if (newPoidh == address(0)) revert InvalidPoidhAddress();
        address old = poidh;
        poidh = newPoidh;
        emit PoidhSet(old, newPoidh);
    }

    /// @notice Mint a claim NFT to the POIDH contract (escrow) with a tokenURI.
    function mintToEscrow(uint256 tokenId, string calldata uri) external onlyPoidh {
        _mint(poidh, tokenId); // no ERC721Receiver callback
        _setTokenURI(tokenId, uri);
    }
}
