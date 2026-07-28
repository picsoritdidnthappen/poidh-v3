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

* **poidh v3 Core Contracts:** `[Insert link to v3 contracts repo or address deployment list here]` — Review the core implementation logic for creating bounties, depositing funds, submitting claims, and handling resolution payouts.
* **poidh NFT Contracts:** `[Insert link to NFT contracts repo or address deployment list here]` — View the ERC-721 implementation handling the metadata and proof-of-completion mints.

---

## querying the poidh database (indexer)

To make building user experiences easier and faster, we host a dedicated indexing service. This allows developers to pull relational data about bounties and claims via simple HTTP requests instead of spinning up heavy RPC node operations.

### api reference
You can view the full REST API documentation, test endpoints, and inspect request/response schemas directly using the [poidh Swagger Interface](https://poidh.xyz).

### data accuracy & trust assumptions
* **Source Material:** The database is populated by an offchain indexer listening to onchain events emitted by the immutable poidh contracts.
* **Accuracy:** This data is roughly **99.9% historically accurate**. 
* **Developer Note:** Because this data is derived from an offchain indexer parsing the blockchain, it is not as "perfect" or instantaneous as pulling directly from an onchain RPC query. For highly critical, real-time value transfers or consensus checks, consider validating states directly against the contract.
