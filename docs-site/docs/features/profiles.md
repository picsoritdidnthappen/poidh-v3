# profiles 👤

Every wallet on poidh has its own public profile page.

Profiles bring together a user's activity across the protocol, making it easy to understand who they are, what they've contributed, and how they've participated in coordination over time.

Whether you're reviewing a bounty creator before funding their work or evaluating someone who submitted a claim, profile pages provide the context needed to make informed decisions.

<img width="1000" alt="profile with zkpassport" src="https://github.com/user-attachments/assets/083041c0-b56a-46dc-b3eb-3ddb9f9a852f" />

---

## identity and social profiles

At the top of every profile you'll find the user's primary identity.

Depending on what they've connected, this may include:

* Wallet address (via the "copy" icon)
* ENS, GNS, WNS, or DNS name
* Profile picture
* Farcaster profile
* X profile
* ZKPassport-verified country

Profiles also include quick actions for copying the wallet address and sharing the profile with others.

Together, these identifiers make it easier to recognize contributors across both the blockchain and the broader social web.

<img width="362" height="156" alt="mathew profile" src="https://github.com/user-attachments/assets/c3294a70-1445-4719-ac85-c6acf2e516f1" />

---

## poidh score

Every profile prominently displays the user's poidh score.

This score summarizes a person's participation across the protocol and grows as they create bounties, complete work, fund contributors, and collect claim NFTs.

While no single number tells the full story, the poidh score provides a quick snapshot of someone's history within the ecosystem.

To learn more about how scores are calculated, see the [**poidh score** documentation](/features/poidh-score).

<img width="147" height="113" alt="poidh score" src="https://github.com/user-attachments/assets/4465adb0-a861-4dcd-a0cf-172259c4d2a7" />

---

## activity statistics

Every profile includes a collection of activity statistics that summarize a user's history on poidh.

These include:

* Completed bounties (bounties that they created + paid out)
* Active bounties (bounties they created which have not been paid out or cancelled)
* Completed claims (claims they submitted which were accepted)
* ETH paid
* ETH currently held in bounty contracts
* ETH earned
* DEGEN paid
* DEGEN currently held in bounty contracts
* DEGEN earned

These statistics help paint a picture of how someone participates within the protocol, whether they primarily create bounties, complete work, fund contributors, or a combination of all three.

<img width="1015" height="191" alt="profile stats" src="https://github.com/user-attachments/assets/0bdf4d06-37a1-4122-a3fd-0cb5a1a1e7e6" />

---

## NFT collection

The **NFTs** tab displays every claim NFT currently owned by the wallet.

Each NFT represents a completed bounty that the user helped bring into existence by funding and accepting a successful claim. It also lists any NFTs they purchased or were sent by other users.

Over time, a collection of claim NFTs becomes a visual history of the real-world outcomes someone has chosen to incentivize.

Clicking any NFT will take you to its corresponding bounty page.

<img width="1000" alt="good nfts" src="https://github.com/user-attachments/assets/45bdfe5b-3c20-480e-a929-a8ef3222c081" />

---

## created bounties

The **Bounties** tab lists every bounty created by the user.

From here, you can explore the work they've requested, the communities they participate in, and the kinds of outcomes they choose to incentivize.

This is often the best place to understand someone's interests and long-term involvement with poidh.

The following icons let you know the status of a bounty:

💰 = the user has funds available to claim in this bounty
✅ = the user funded this bounty and it's now complete
❌ = the user funded this bounty and then it was cancelled 

<img width="1000" alt="bounty cards" src="https://github.com/user-attachments/assets/3e25cfa3-5994-4c93-bf70-3b70f5f6cc8d" />

---

## submitted claims

The **Claims** tab displays every claim submitted by the user.

Reviewing someone's previous claims is a great way to understand the quality of their work and the kinds of contributions they've made across the ecosystem.

Each claim links directly back to its original bounty, making it easy to explore the full context surrounding every submission.

A red "accepted" badge also appears on any claim that was selected as the winner of a bounty.

<img width="1000" alt="claims from hank" src="https://github.com/user-attachments/assets/da4e1ef8-4067-454a-bf5d-84acfa75d1ae" />

---

## sharing profiles

Every profile includes a **Share** button in the header that generates a link you can easily send to others.

Whether you're showcasing your contributions, introducing yourself to a new community, or highlighting another user's work, profile pages provide a simple way to share your history on poidh.

<img width="333" height="335" alt="share poidh profile" src="https://github.com/user-attachments/assets/71c33423-b5d7-475d-a791-914458484728" />

---

## your public reputation

Unlike traditional resumes or portfolios, poidh profiles are built directly from your onchain activity.

Every completed claim.

Every funded bounty.

Every collected claim NFT.

Every contribution becomes part of your public history.

As you continue participating in poidh, your profile naturally evolves into a transparent record of the work you've helped coordinate and the outcomes you've made possible.

---

## relevant github files

https://github.com/picsoritdidnthappen/poidh-app/tree/46b31232867c77e26a7826b03e0c1334757114fe/src/components/account
