# poidh score 🕹️

Your poidh score is a public measure of your participation across the poidh ecosystem.

As you create bounties, complete work, fund contributors, and participate in coordination, your score grows alongside your contributions.

Rather than representing financial wealth or token ownership, a poidh score reflects your history of activity within the protocol.

You'll see poidh scores throughout the application, making it easy to understand how active someone has been before collaborating with them.

---

## how poidh score is calculated

Your total poidh score is the sum of your reputation across every supported blockchain.

For **Arbitrum**, **Base**, and **Ethereum Mainnet**, the formula is:

```text
poidh score =
(ETH earned × 1000)
+ (ETH paid × 1000)
+ (poidh NFTs held × 10)
```

For **Degen Chain**, the formula is adjusted to account for the different token denomination:

```text
poidh score =
(DEGEN earned ÷ 500)
+ (DEGEN paid ÷ 500)
+ (poidh NFTs held × 10)
```

This means your score increases in three ways:

* Completing bounties and earning rewards.
* Funding bounties and paying contributors.
* Collecting poidh claim NFTs.

Because scores are calculated independently for each supported blockchain, the leaderboard displays both individual chain scores and your combined total.

The formula is intentionally straightforward and transparent so anyone can independently understand how scores are derived.

As poidh evolves, the reputation system may continue to improve based on community feedback and real-world usage.

---

## where your score appears

Your poidh score is visible in several places throughout poidh.

### profile pages

Every profile displays a user's current poidh score alongside their activity, completed claims, created bounties, NFT collection, and connected social accounts.

This provides a quick overview of someone's history within the protocol.

<img width="708" height="401" alt="good poidh score" src="https://github.com/user-attachments/assets/7aa84ec5-f126-4663-879e-70e5760684f9" />

---

### claim NFTs

Clicking on a claim image expands the NFT and displays additional information about the contributor, including their poidh score.

This helps reviewers better understand the history of the person submitting the claim while keeping the focus on the evidence itself.

<img width="478" height="809" alt="claim score" src="https://github.com/user-attachments/assets/3f041d4c-13dd-441b-b872-800cf4d6cb19" />

---

### leaderboard

The [poidh leaderboard page](https://poidh.xyz/leaderboard) ranks participants by poidh score across every supported blockchain.

Scores are broken down by network—including Ethereum Mainnet, Base, Arbitrum, and Degen—alongside a combined total.

Each entry links directly to the user's profile, making it easy to explore the people contributing most actively across the protocol.

<img width="1343" height="874" alt="poidh high scores" src="https://github.com/user-attachments/assets/2a54cad9-b633-4e71-8869-7a2763cbffe9" />

---

## reputation across chains

poidh supports multiple blockchain networks.

Rather than treating activity on each network separately, your poidh score aggregates your contributions across every supported chain while also showing a per-chain breakdown.

This allows you to build a unified reputation regardless of where coordination happens.

---

## reputation should be earned

poidh scores are earned through participation.

Creating bounties.

Completing work.

Funding contributors.

Helping coordinate outcomes.

The goal isn't simply to measure activity.

It's to recognize the people who consistently contribute to making things happen.

---

## a signal, not a guarantee

A high poidh score doesn't automatically mean someone's next contribution will be successful.

Likewise, everyone starts with a score of zero.

The score is simply one signal among many.

When reviewing a claim or deciding whether to participate in a bounty, it's often helpful to consider the contributor's previous activity, connected social profiles, NFT history, and the quality of the evidence they've provided—not just their poidh score alone.

---

## building on reputation

As poidh evolves, we expect reputation to become increasingly important.

Future features may use poidh scores alongside other community signals to improve discovery, highlight experienced contributors, and help communities recognize people who consistently create value.

Like many parts of poidh, the reputation system will continue to evolve based on real-world usage and community feedback.

---

## relevant github files

* https://github.com/picsoritdidnthappen/poidh-app/tree/prod/src/app/leaderboard
* https://github.com/picsoritdidnthappen/poidh-app/tree/prod/src/app/account
* https://github.com/picsoritdidnthappen/poidh-app/tree/prod/src/components/claims

