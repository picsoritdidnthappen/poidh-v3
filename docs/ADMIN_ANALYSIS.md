# POIDH Admin Powers Analysis: v2 vs v3

This document provides a complete audit of all administrative/owner functionality in both v2 and v3 contracts.

---

## Executive Summary

| Version | Contract | Admin Functions | Admin Power Level |
|---------|----------|-----------------|-------------------|
| **v2** | PoidhV2.sol | **0** | None |
| **v2** | PoidhV2Nft.sol | **1** (`setPoidhContract`) | Minimal |
| **v3** | PoidhV3.sol | **0** | None |
| **v3** | PoidhClaimNFT.sol | **1** (`setPoidh`) | Minimal |

**Both versions are essentially trustless** - the only admin power is wiring the NFT contract to accept mints from the bounty contract.

---

## V2 Contracts (Source: github.com/picsoritdidnthappen/poidh-contracts)

### PoidhV2.sol - Main Bounty Contract

**Imports:**
```solidity
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
```

**Admin Analysis:**
| Feature | Present | Notes |
|---------|---------|-------|
| `Ownable` import | ❌ No | Not imported |
| `Pausable` import | ❌ No | Not imported |
| `onlyOwner` modifier | ❌ No | Does not exist |
| `pause()` / `unpause()` | ❌ No | Does not exist |
| Emergency withdraw | ❌ No | Does not exist |
| Mutable treasury | ❌ No | `address public immutable treasury` |
| Mutable fee | ❌ No | Hardcoded `(bountyAmount * 25) / 1000` (2.5%) |
| Owner state variable | ❌ No | Does not exist |

**Conclusion: PoidhV2.sol has ZERO admin powers.**

---

### PoidhV2Nft.sol - NFT Contract

**Imports:**
```solidity
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol';
```

**Note:** Does NOT import `Ownable` - uses a custom authority pattern instead.

**Admin Analysis:**
| Feature | Present | Notes |
|---------|---------|-------|
| `Ownable` import | ❌ No | Uses custom `poidhV2Authority` instead |
| `poidhV2Authority` | ✅ Yes | `address public immutable poidhV2Authority` |
| Admin function | ✅ Yes | `setPoidhContract(address, bool)` |

**The ONLY admin function:**
```solidity
function setPoidhContract(address _poidhContract, bool _hasPermission) external {
    require(msg.sender == poidhV2Authority, 'only poidhV2Authority can set poidh contracts');
    poidhContracts[_poidhContract] = _hasPermission;
    setApprovalForAll(_poidhContract, _hasPermission);
}
```

**What it does:**
- Allows/disallows contracts from minting claim NFTs
- Sets approval for the contract to transfer NFTs

**What it CANNOT do:**
- Cannot steal user funds
- Cannot pause the protocol
- Cannot change fees
- Cannot change treasury
- Cannot modify existing bounties/claims

**Risk:** If `poidhV2Authority` is compromised, attacker could:
1. Disable minting (griefing) by setting `poidhContracts[poidhV2] = false`
2. Enable a malicious contract to mint fake claim NFTs

---

## V3 Contracts (This Repository)

### PoidhV3.sol - Main Bounty Contract

**Imports:**
```solidity
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";
```

**Admin Analysis:**
| Feature | Present | Notes |
|---------|---------|-------|
| `Ownable*` inheritance | ❌ No | No owner/admin in `PoidhV3` |
| `pause()` / `unpause()` | ❌ No | Removed |
| Emergency withdraw | ❌ No | Does not exist |
| Mutable treasury | ❌ No | `address public immutable treasury` |
| Mutable fee | ❌ No | `uint256 public constant FEE_BPS = 250` |
| Mutable votingPeriod | ❌ No | No setter; voting period is fixed in this implementation |

**Conclusion: PoidhV3.sol has ZERO admin powers and no owner.**

---

### PoidhClaimNFT.sol - NFT Contract

**Imports:**
```solidity
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IPoidhClaimNFT} from "./interfaces/IPoidhClaimNFT.sol";
```

**Admin Analysis:**
| Feature | Present | Notes |
|---------|---------|-------|
| `Ownable2Step` inheritance | ✅ Yes | Contract inherits it |
| Owner-only functions | ✅ Yes | **1 function** |

**The ONLY admin function:**
```solidity
function setPoidh(address newPoidh) external {
    _checkOwner();
    if (newPoidh == address(0)) revert InvalidPoidhAddress();
    emit PoidhSet(poidh, newPoidh);
    poidh = newPoidh;
}
```

**What it does:**
- Sets which contract can mint claim NFTs

**What it CANNOT do:**
- Cannot steal user funds (funds are in PoidhV3, not NFT contract)
- Cannot pause the protocol
- Cannot change fees
- Cannot change treasury
- Cannot modify existing bounties/claims
- Cannot burn or transfer user NFTs

**Risk:** If owner is compromised, attacker could:
1. Disable minting by setting `poidh = address(0)` (but rejected by check)
2. Set `poidh` to a malicious contract that mints fake claim NFTs
3. **Cannot steal funds** - funds are in PoidhV3 which has no admin functions

---

## Comparison Matrix

| Capability | v2 PoidhV2 | v2 PoidhV2Nft | v3 PoidhV3 | v3 PoidhClaimNFT |
|------------|------------|---------------|------------|------------------|
| Steal user funds | ❌ | ❌ | ❌ | ❌ |
| Pause protocol | ❌ | ❌ | ❌ | ❌ |
| Change fee % | ❌ | ❌ | ❌ | ❌ |
| Change treasury | ❌ | ❌ | ❌ | ❌ |
| Block new mints | ❌ | ✅ | ❌ | ✅ |
| Enable rogue minter | ❌ | ✅ | ❌ | ✅ |
| Upgrade contract | ❌ | ❌ | ❌ | ❌ |

---

## Recommendations for V3

### Option 1: Keep Current Design (Recommended)

**Pros:**
- `setPoidh()` needed for initial deployment wiring
- Allows recovery if PoidhV3 needs to be redeployed
- Matches v2's minimal admin model

**Cons:**
- NFT owner could theoretically enable a malicious minter

**Mitigations:**
1. Use a multisig for NFT ownership
2. Add a timelock before `setPoidh` takes effect
3. Consider renouncing ownership after deployment is stable

### Operational Footgun: Lost Owner Key (Migration Blocker)

The single biggest real-world risk with the current minimal-admin design is not “malicious admin”,
it’s **operational key loss**:

- If the `PoidhClaimNFT` owner key is lost, `setPoidh()` can never be called again.
- This prevents:
  - migrating to a new POIDH contract (v3 → v4),
  - emergency “halt claim minting” actions that rely on re-wiring,
  - repairing a misconfigured initial deployment.

**Implication:** in the “lost key” scenario, the only practical path is to **deploy a new claim NFT
contract** and point the new POIDH contract at it (a new collection address).

Migration notes and comms guidance:
- `docs/migrations/NFT_REDEPLOYMENT.md`

### Option 2: Renounce NFT Ownership After Deployment

```solidity
// After deployment and testing:
nft.renounceOwnership();
```

**Pros:**
- Fully trustless - no one can change the minter
- Maximum decentralization

**Cons:**
- Cannot recover if PoidhV3 has a critical bug requiring redeployment
- Cannot upgrade to PoidhV4 without deploying a new NFT contract

### Status: PoidhV3 Has No Owner (Implemented)

This repo’s `PoidhV3` does not inherit `Ownable`/`Ownable2Step` and has no admin key surface.

---

## Summary

**V2 was more trustless than the security report suggested.** It had:
- No pause functionality
- No admin withdraw
- Only a single `setPoidhContract()` function on the NFT

**V3 matches V2's minimal admin model:**
- No pause functionality (removed)
- No admin withdraw
- Only a single `setPoidh()` function on the NFT
- `PoidhV3.sol` has no owner/admin surface

**The only admin power in either version is controlling which contract can mint claim NFTs.** This is needed for deployment but could be renounced afterward for full trustlessness.
