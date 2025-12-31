# Base Sepolia Deployment (PoidhV3 + PoidhClaimNFT)

This repo includes `foundry.toml` aliases for Base Sepolia RPC + BaseScan verification.

## Prereqs

- Funded deployer EOA on Base Sepolia
- `POIDH_TREASURY` address confirmed (immutable in `PoidhV3`)
- (Recommended) Safe multisig address ready to own `PoidhClaimNFT`
- BaseScan API key (for `--verify`)

## Deploy

```bash
export BASE_SEPOLIA_RPC_URL="https://…"
export BASESCAN_API_KEY="…"

export DEPLOYER_PK="0x…"
export POIDH_TREASURY="0x…"
export POIDH_START_CLAIM_INDEX=1

# optional
export POIDH_MULTISIG="0x…"
export POIDH_NFT_NAME="poidh claims v3"
export POIDH_NFT_SYMBOL="POIDH3"

forge script script/Deploy.s.sol:Deploy \
  --rpc-url base_sepolia \
  --private-key "$DEPLOYER_PK" \
  --broadcast \
  --verify
```

## Post-deploy checks

Fill these from the script output:
- `POIDH_V3=0x…`
- `POIDH_NFT=0x…`

```bash
cast call "$POIDH_V3" "treasury()(address)" --rpc-url base_sepolia
cast call "$POIDH_V3" "poidhNft()(address)" --rpc-url base_sepolia
cast call "$POIDH_NFT" "poidh()(address)" --rpc-url base_sepolia

# If you set POIDH_MULTISIG, ownership is 2-step:
cast call "$POIDH_NFT" "owner()(address)" --rpc-url base_sepolia
cast call "$POIDH_NFT" "pendingOwner()(address)" --rpc-url base_sepolia
```

Expected:
- `PoidhV3.poidhNft()` == `POIDH_NFT`
- `PoidhClaimNFT.poidh()` == `POIDH_V3`
- `PoidhV3.treasury()` == `POIDH_TREASURY`
- If `POIDH_MULTISIG` set: `pendingOwner()` == `POIDH_MULTISIG` until the Safe calls `acceptOwnership()`
