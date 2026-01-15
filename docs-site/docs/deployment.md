# Deployment Guide

## Pre-Deployment Checklist

- [ ] All tests passing (`forge test -vvv`)
- [ ] Coverage >95% (`forge coverage`)
- [ ] Fuzz tests passed (`FOUNDRY_FUZZ_RUNS=10000 forge test`)
- [ ] Invariant tests passed (`FOUNDRY_INVARIANT_RUNS=2000 forge test`)
- [ ] Security review completed
- [ ] Treasury address configured
- [ ] Parameters validated

## Environment Variables

```bash
# Required
export POIDH_TREASURY=0x...           # Fee recipient address
export POIDH_START_CLAIM_INDEX=1      # Starting claim ID (must be >= 1)

# Optional (with defaults)
export POIDH_MIN_BOUNTY_AMOUNT=1000000000000000      # 0.001 ETH
export POIDH_MIN_CONTRIBUTION=10000000000000        # 0.00001 ETH
export POIDH_NFT_NAME="poidh claims v3"
export POIDH_NFT_SYMBOL="POIDH3"

# Deployment
export DEPLOYER_PK="0x..."            # Deployer private key
export RPC_URL="https://..."           # Chain RPC URL
```

## Deployment Scripts

### Generic Deployment

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PK \
  --broadcast \
  --verify \
  -vvv
```

### Chain-Specific Deployments

#### Base

```bash
forge script script/deploy/Base.s.sol:DeployBase \
  --rpc-url https://mainnet.base.org \
  --private-key $DEPLOYER_PK \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

#### Arbitrum

```bash
forge script script/deploy/Arbitrum.s.sol:DeployArbitrum \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --private-key $DEPLOYER_PK \
  --broadcast \
  --verify
```

#### Base Sepolia (Testnet)

```bash
forge script script/deploy/BaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url https://sepolia.base.org \
  --private-key $DEPLOYER_PK \
  --broadcast \
  --verify
```

## Post-Deployment Steps

### 1. Verify Contracts

```bash
# Check verification status
cast code <CONTRACT_ADDRESS> --rpc-url $RPC_URL

# Verify on Etherscan/BaseScan
forge verify-contract <CONTRACT_ADDRESS> \
  "PoidhV3" \
  --constructor-args $(cast abi-encode "constructor(address,uint256,uint256)" "$TREASURY" "$MIN_BOUNTY" "$MIN_CONTRIB") \
  --chain-id $CHAIN_ID
```

### 2. Verify Parameters

```bash
# Check treasury
cast call <CONTRACT_ADDRESS> "treasury()(address)" --rpc-url $RPC_URL

# Check MIN_BOUNTY_AMOUNT
cast call <CONTRACT_ADDRESS> "MIN_BOUNTY_AMOUNT()(uint256)" --rpc-url $RPC_URL

# Check MIN_CONTRIBUTION
cast call <CONTRACT_ADDRESS> "MIN_CONTRIBUTION()(uint256)" --rpc-url $RPC_URL

# Check voting period
cast call <CONTRACT_ADDRESS> "votingPeriod()(uint256)" --rpc-url $RPC_URL
```

### 3. Test Transactions

```bash
# Test solo bounty creation
cast send <CONTRACT_ADDRESS> \
  "createSoloBounty(string,string)(uint256)" \
  "Test Bounty" "Test Description" \
  --value 0.1ether \
  --private-key $TEST_KEY \
  --rpc-url $RPC_URL

# Test withdrawal
cast send <CONTRACT_ADDRESS> \
  "withdraw()" \
  --private-key $TEST_KEY \
  --rpc-url $RPC_URL
```

### 4. Monitor Contract

```bash
# Watch events
cast logs --from-block <DEPLOYMENT_BLOCK> \
  --address <CONTRACT_ADDRESS> \
  --rpc-url $RPC_URL

# Check contract balance
cast balance <CONTRACT_ADDRESS> --rpc-url $RPC_URL
```

## Configuration

### Minimum Amounts

| Chain | MIN_BOUNTY_AMOUNT | MIN_CONTRIBUTION |
|-------|-------------------|------------------|
| Base | 0.001 ETH | 0.00001 ETH |
| Arbitrum | 0.001 ETH | 0.00001 ETH |
| Degenchain | 1000 DEGEN | 10 DEGEN |

### Voting Period

- Default: 2 days
- Adjustable by: `resetVotingPeriod()`
- Recommended: 1-7 days depending on use case

### Fee Structure

- Protocol fee: 2.5% (250 BPS)
- Sent to treasury on claim acceptance
- Deducted from bounty amount before payout

## Deployment Addresses

### Mainnet

| Chain | Contract Address | Deployment Date |
|-------|------------------|-----------------|
| Arbitrum | [0xF3872201171A0fF0a6e789627583E8036C41Baec](https://arbiscan.io/address/0xF3872201171A0fF0a6e789627583E8036C41Baec) | Jan-11-2026 |
| Base | [0xF3872201171A0fF0a6e789627583E8036C41Baec](https://basescan.org/address/0xF3872201171A0fF0a6e789627583E8036C41Baec) | Jan-11-2026 |
| Degen Chain | [0x0285626130C127741C18C7730625ca624B727DC3](https://explorer.degen.tips/address/0x0285626130C127741C18C7730625ca624B727DC3) | Jan-11-2026 |

### Testnet

| Chain | Contract Address | Deployment Date |
|-------|------------------|-----------------|
| Base Sepolia | *TBD* | - |

## Security Considerations

### Treasury Configuration

- Use multi-sig wallet
- Consider timelock for fee changes
- Document fee distribution strategy

### Deployer Key

- Use hardware wallet or secure KMS
- Destroy after deployment if possible
- Document key custody procedures

### Immutable Parameters

Once deployed, these cannot be changed:
- Treasury address
- MIN_BOUNTY_AMOUNT
- MIN_CONTRIBUTION
- PoidhClaimNFT contract

## Monitoring

### Key Metrics to Track

- Total bounties created
- Total claims submitted
- Acceptance rate
- Average bounty size
- Total protocol fees collected
- Gas usage trends

### Alert Configuration

Set up alerts for:
- Unusually large bounties
- High rejection rates
- Failed transactions
- Large withdrawals
- Contract balance anomalies

## Upgrade Path

Currently immutable. Future considerations:

1. Proxy pattern for upgradeability
2. Migration strategy for active bounties
3. Governance mechanism for parameter changes
4. Community signaling for upgrades

## Troubleshooting

### Common Issues

**Deployment fails with "insufficient funds"**
```bash
# Check deployer balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# Estimate gas cost
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL
```

**Verification fails**
```bash
# Check chain ID
cast chain-id --rpc-url $RPC_URL

# Verify constructor args match
cast abi-encode "constructor(address,uint256,uint256)" "$TREASURY" "$MIN_BOUNTY" "$MIN_CONTRIB"
```

**Transaction reverts with "Not issuer"**
```bash
# Verify caller address
cast call <CONTRACT_ADDRESS> "getBounty(uint256)((uint256,address,string,string,uint256,address,uint256,uint256))" <BOUNTY_ID> --rpc-url $RPC_URL
```

## Support

For deployment issues:
1. Check docs: `docs/README.md`
2. Review security report: `docs/POIDH_V3_SECURITY_REPORT.md`
3. Test on testnet first
4. Consult team before mainnet deployment

## Additional Resources

- [Foundry Deployment Docs](https://book.getfoundry.sh/forge/deploying)
- [Base Deployment Guide](https://docs.base.org/using-base/deploying)
- [Arbitrum Deployment Guide](https://developer.offchainlabs.com/docs/deploy_a_contract/)
