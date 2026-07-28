# building on poidh 💻

Welcome to the developer documentation for [poidh](https://poidh.xyz). Whether you want to improve our open-source application, build custom frontends on top of our immutable contracts, extract data via our indexer, or query active bounties, this guide covers the core technical touchpoints.

---

## contributing to the app

We welcome community contributions to the core poidh application! You can help us squash bugs, improve the UI, or build new feature sets.

### getting started locally
Full setup instructions, environment variables, and repository architecture can be found in the official poidh GitHub repo: https://github.com/picsoritdidnthappen/poidh-app

### need help?
If you have questions about the codebase, architectural choices, or want to discuss a major feature before submitting a Pull Request, please reach out to Kenny directly via X or Farcaster.

- https://x.com/kennyistyping
- https://farcaster.xyz/kenny

---

## building on top of poidh contracts

poidh is built on foundational core principles of censorship resistance and decentralization. **All poidh smart contracts are completely immutable.** Once deployed, they cannot be altered, ensuring your integrations will never break due to contract upgrades.

### supported networks
The poidh protocol is actively deployed across multiple EVM chains:
* **Ethereum Mainnet**
* **Arbitrum**
* **Base**
* **Degen Chain**

### contract repositories & addresses
Developers can interact directly with the underlying bounty mechanics or query the proof-of-completion NFTs minted upon successful bounty execution. 

**poidh v3 Core Contracts:**
- Ethereum Mainnet - https://etherscan.io/address/0xe731dfadbff20542e10d09d26fc71445c70d4232
- Arbitrum - https://arbiscan.io/address/0x5555fa783936c260f77385b4e153b9725fef1719
- Base - https://basescan.org/address/0x5555fa783936c260f77385b4e153b9725fef1719
- Degen Chain - https://explorer.degen.tips/address/0x18E5585ca7cE31b90Bc8BB7aAf84152857cE243f

**poidh v3 NFT Contracts:**

- Ethereum Mainnet - https://etherscan.io/address/0x9c5f45d5e1382e4058d334d93c6c01442012a4d9
- Arbitrum - https://arbiscan.io/address/0x27e117cc9a8da363442e7bd0618939e3eeeacf6a
- Base - https://basescan.org/address/0x27e117cc9a8da363442e7bd0618939e3eeeacf6a
- Degen Chain - https://explorer.degen.tips/token/0x39F04b7897DCAf9Dc454E433F43Fb1C3bB528E11

**[Read the full contract docs](/contracts/overview)**

Note, poidh v3 is a security-focused rebuild of the protocol following [an exploit in December 2025 of the poidh v2 contracts](https://words.poidh.xyz/poidh-is-back). The main poidh website displays the history of bounties, claims, and payments completed via poidh v2, but the contracts are no longer utilized within the app. 

THESE CONTRACTS ARE LISTED FOR INFORMATIONAL PURPOSES ONLY AND SHOULD NOT BE USED UNDER ANY CIRCUMSTANCES

**poidh v2 Core Contracts:**
- Arbitrum - https://arbiscan.io/address/0x0aa50ce0d724cc28f8f7af4630c32377b4d5c27d
- Base - https://basescan.org/address/0xb502c5856f7244dccdd0264a541cc25675353d39
- Degen Chain - https://explorer.degen.tips/address/0x2445BfFc6aB9EEc6C562f8D7EE325CddF1780814

**poidh v2 NFT Contracts:**
- Arbitrum - https://arbiscan.io/address/0xddfb1a53e7b73dba09f79fca24765c593d447a80
- Base - https://basescan.org/address/0xddfb1a53e7b73dba09f79fca24765c593d447a80
- Degen Chain - https://explorer.degen.tips/token/0xDdfb1A53E7b73Dba09f79FCA24765C593D447a80

---

## querying the poidh database (indexer)

To make building user experiences easier and faster, we host a dedicated indexing service. This allows developers to pull relational data about bounties and claims via simple HTTP requests instead of spinning up heavy RPC node operations.

### api reference
You can view the full REST API documentation, test endpoints, and inspect request/response schemas directly using https://indexer.poidh.xyz/swagger. 

### data accuracy & trust assumptions
* **Source Material:** The database is populated by an offchain indexer listening to onchain events emitted by the immutable poidh contracts.
* **Accuracy:** This data is roughly **99.9% historically accurate**. 
* **Developer Note:** Because this data is derived from an offchain indexer parsing the blockchain, it is not as "perfect" or instantaneous as pulling directly from an onchain RPC query. For highly critical, real-time value transfers or consensus checks, consider validating states directly against the contract.
