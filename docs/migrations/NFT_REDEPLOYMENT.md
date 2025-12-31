# NFT Redeployment Plan (Lost Owner EOA)

## Problem Statement

The claim NFT contract (`PoidhClaimNFT` in v3, and the analogous NFT in v2) includes an
owner-controlled “wiring” function:

- v3: `PoidhClaimNFT.setPoidh(address)`

If the owner EOA key is lost, **the authorized POIDH contract cannot be updated**, which blocks:

- upgrading/migrating to a new POIDH bounty contract, and/or
- emergency response actions that rely on changing the authorized minter.

## Recommended Path: Redeploy a New Claim NFT for v3

Given the owner key is likely unrecoverable, the practical option is:

1) deploy a new `PoidhClaimNFT` contract (new collection address)
2) deploy `PoidhV3` pointing at the new NFT
3) call `setPoidh(PoidhV3)` on the new NFT
4) transfer NFT ownership to a Safe multisig (or keep in multisig from the start)

This repository’s deploy script already follows this pattern:
- `script/Deploy.s.sol`

## Product / UX Implications

- **v2 claim NFTs become “limited”**: the old collection can’t be wired to a new POIDH contract.
- v3 claim NFTs will live in a *new collection address*, even if name/symbol are similar.
- The frontend/indexer should treat v2 and v3 claim NFTs as distinct collections.

## Communications Guidance (Suggested)

- Announce that v2 claim NFTs are final/limited and that v3 uses a new claim NFT contract.
- Provide both collection addresses and clearly label them by version/network.

## Key Management Requirement (Non-Negotiable)

Before mainnet:
- Put the new claim NFT owner behind a Safe multisig.
- Document signer set + threshold.
- Test the 2-step ownership transfer flow (Ownable2Step).

