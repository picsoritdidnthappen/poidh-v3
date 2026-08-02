# claim NFTs 💎

Every claim submitted on poidh is minted as an NFT.

These NFTs are more than just receipts.

They are permanent, onchain records of real-world actions, creative work, and contributions made through the protocol.

The supporting photos/GIFs/media associated with each claim are stored on the InterPlanetary File System (IPFS) and all text information is embedded permanently onchain. This creates a durable record of the evidence behind every completed bounty.

Whenever a bounty is successfully completed, the creator receives the NFT submitted by the claimant alongside the completed work itself.

This creates a lasting collectible tied to the history of what happened.

<img width="1790" height="849" alt="poidh original nft" src="https://github.com/user-attachments/assets/99ac5704-1a07-444b-ad13-7fce114e75db" />

_[The 2nd NFT in poidh history minted on our v1 Arbitrum contract](https://opensea.io/item/arbitrum/0xdfFE8A4a4103f968Ffd61fd082D08c41dCf9b940/1)_

---

## what's inside a claim NFT?

Every claim NFT gives you access to the following information within fully onchain data:

* The claim id (chronological and based on the corresponding NFT smart contract)
* The wallet address that minted the claim
* When the claim was minted
* The corresponding bounty id
* The claim NFT title
* The claim NFT description
* The IPFS link for the claim NFT media

<img width="796" height="279" alt="claim nft info" src="https://github.com/user-attachments/assets/f635e45a-bbf5-4325-990d-f76482ac6b61" />

Beyond this purely onchain information, the poidh frontend provides additional context:

* The poidh score of the wallet that submitted the claim
* The Farcaster profile associated with the wallet that submitted the claim (if available)
* The X profile associated with the wallet that submitted the claim (if available)
* The wallet's corresponding ENS/GNS/WNS or DNS (if available)

Together, these pieces create a permanent record of both the work and the people involved.

<img width="472" alt="jackpot" src="https://github.com/user-attachments/assets/93bfba5e-16cc-4274-9d01-d8637bc42a2f" />

<br>

<img width="472" alt="clicked nft" src="https://github.com/user-attachments/assets/768de9c7-a69f-445e-bb65-a4fbf414c3da" />

_Clicking a claim image expands the view to allow you to zoom into images and see claimant poidh scores._

---

## permanent media storage

The media attached to every claim NFT is stored on the **InterPlanetary File System (IPFS)** rather than on a traditional centralized server.

poidh partners with **Pinata** to pin and distribute claim media across the IPFS network, helping ensure that the evidence associated with each claim remains accessible over time.

Unlike a traditional web application where uploaded files live on a company's servers, IPFS uses content addressing. Each file receives a unique cryptographic identifier based on its contents, making it easy to verify that the media has not been altered.

Combined with the NFT itself, this creates a durable record of both the evidence and the onchain transaction associated with every completed bounty.

---

## why mint claims as NFTs?

There are several reasons every claim becomes an NFT.

### bringing offchain actions onchain

Many valuable actions happen outside the blockchain.

A community cleanup.

A photograph.

An event.

A software contribution.

A piece of research.

A blockchain can easily verify transactions, but it cannot directly observe what happens in the physical world.

By attaching evidence to an NFT, poidh creates a durable, verifiable record connecting an onchain transaction to an offchain event.

It's a simple idea inspired by an internet meme that most people already understand:

**pics or it didn't happen.**

---

### improving claim quality

Submitting a claim requires minting an NFT.

While the minting cost is intentionally small, it introduces enough friction to discourage some low-effort spam submissions.

No system completely prevents fraudulent claims.

But requiring contributors to create a permanent onchain record encourages higher-quality submissions than anonymous, cost-free uploads.

---

### preserving provenance

Every claim NFT records who completed the work, who requested it, and when it happened.

That provenance cannot be separated from the collectible itself.

Years later, anyone can still verify the history behind the NFT.

Rather than collecting random images, bounty creators collect proof of the real-world actions they helped make possible.

---

## collecting the outcomes you created

One of the most unique aspects of poidh is that bounty creators don't simply pay for work.

They collect the proof that the work happened.

When you create a bounty, you're building a collection of outcomes you've helped bring into existence.

Maybe it's a new open source feature.

Maybe it's a successful community event.

Maybe it's artwork, research, photography, or something that changed a local neighborhood.

Each completed bounty leaves behind a collectible representing that contribution.

Over time, your collection tells the story of what you've chosen to incentivize.

<img width="832" height="896" alt="eljunior poidh profile" src="https://github.com/user-attachments/assets/186a5217-bd4d-4be3-b2b9-16510085b61a" />

_Just a portion of poidh OG [eljuniordiaz.eth's NFT collection](https://poidh.xyz/account/0x71cbbe6ecf1a9c4d8b9115757ebcc5ff45902177?tab=nfts)_

---

## are claim NFTs valuable?

The poidh team makes no promises about the present or future value of any claim NFT.

Most claims will likely remain valuable primarily to the people and communities involved in creating them.

But history shows that collectibles often derive their value from the events they represent—not simply from the object itself.

An ordinary ticket stub can become historically significant because of the event it came from.

A signed photograph may matter because of the person in it.

A seemingly ordinary artifact can become meaningful because of what happened around it.

Claim NFTs follow the same principle.

Their significance comes from the actions they document.

Imagine collecting the NFT representing:

* The first implementation of an important open source feature.
* A world record being broken.
* Artwork commissioned by a major online community.
* A historic public goods initiative.
* A bounty completed by a well-known builder or creator.

The collectible itself doesn't create the significance.

The underlying action does.

As poidh grows, some claim NFTs may become meaningful historical artifacts for the communities that created them. 

With this in mind, we plan to build a future marketplace for poidh NFTs in-app allowing users to browse, list, and buy the most popular claims in app history.

---

## permanent records of coordination

The internet has countless places to post photos.

It has countless ways to pay people.

Very few systems permanently connect the two.

Claim NFTs do exactly that.

They combine proof, provenance, payment, and participation into a single onchain artifact representing a completed outcome.

Every completed bounty leaves behind more than a transaction.

It leaves behind a permanent record of coordination.

---

## relevant github files

https://github.com/picsoritdidnthappen/poidh-app/tree/prod/src/components/claims

