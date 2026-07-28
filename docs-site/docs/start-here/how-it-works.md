# how poidh works 🛠️

poidh turns a desired outcome into an open coordination process.

Think of each bounty as an ephemeral DAO: it forms around a specific outcome, pools capital from anyone who believes in it, verifies completion through collective judgment, and dissolves automatically once funds are paid out.

A typical bounty follows six steps:

**create → fund → do → prove → verify → pay**

---

## 1. create a bounty

<img width="472" height="754" alt="Screen Shot 2026-07-27 at 3 43 28 PM" src="https://github.com/user-attachments/assets/51556d5a-d0ef-469c-8701-14ce884b5ff4" />

Everything starts with an outcome someone wants to see happen.

A bounty creator describes:

- **what should happen**
- **what counts as completion**
- **what proof is required**

The best bounties make the desired outcome and requirements easy to understand before anyone attempts them. The more ambiguity a bounty contains, the harder it becomes for participants and voters to agree on what constitutes success.

A few things worth knowing before you post:

- **Values fluctuate.** Bounty rewards are denominated in ETH or DEGEN, so the dollar equivalent will change with the market. Dollar figures in bounty descriptions are estimates, not guarantees.
- **Deadlines are suggestions, not rules.** You can include a suggested timeline in your description to set expectations, but nothing in the protocol enforces a hard cutoff. Bounties can stay open as long as you want.
- **Your funds are yours.** They live in an immutable smart contract controlled by your wallet. poidh never touches them.

### writing a good bounty

A useful way to evaluate a bounty before posting is the **poidh framework**:

**precise** — is it clear exactly what needs to happen?

**observable** — will there be enough evidence to determine whether it happened?

**impactful** — is the outcome worth incentivizing?

**doable** — can someone realistically accomplish it?

**horizoned** — is there a suggested timeline that sets expectations for claimants?

---

## 2. fund it

Once a bounty exists, it needs an incentive.

The creator can fund it directly — but they don't have to be the only one who does.

**Anyone can add funds to a bounty.**

<img width="411" height="496" alt="Screen Shot 2026-07-27 at 3 48 38 PM" src="https://github.com/user-attachments/assets/8a76d3cb-3b10-4302-b1b2-a1a82db4d2bd" />

Up to 150 wallets can contribute to a single bounty. This means a group of people can collectively fund an outcome without needing to coordinate payments among themselves. The money follows the bounty, not the funder.

For example:

> Alice creates a bounty with 0.05 ETH to get someone to photograph a rare bird.
> Bob contributes 0.01 ETH. Three other people contribute another 0.04 ETH total.
> The bounty now offers 0.1 ETH — and it all happened without anyone having to exchange payment details.

This is what makes poidh bounties social objects rather than static listings. A 0.01 ETH bounty can become a 10 ETH bounty overnight if the right people see it and believe in it. There's no cap on how much can be added. The virality comes from skin in the game, not a like or a repost.

---

## 3. do it

Once a bounty is funded, anyone can attempt to complete it.

poidh doesn't assign the task to a particular person. The bounty is an open invitation:

> **whoever can make this happen can claim the reward.**

There's no hiring process, no roster of approved workers, no central authority assigning jobs. The incentive is public. Participants decide for themselves whether the opportunity is worth pursuing.

---

## 4. prove it

Completing the action isn't enough. The participant needs to demonstrate that they completed the bounty.

They submit a **claim** — evidence that the outcome happened.

Evidence might include:

- a photograph or video
- a link to a social post
- an onchain transaction
- multiple pieces of evidence combined
- an explanation of what happened and why it satisfies the bounty

The exact evidence required depends on the bounty. This is why writing clear proof requirements upfront matters.

<img width="456" height="717" alt="Screen Shot 2026-07-27 at 3 53 15 PM" src="https://github.com/user-attachments/assets/710239cb-e1fc-4ed1-969e-cc9e1400de06" /> <br>

<img width="452" height="724" alt="Screen Shot 2026-07-27 at 3 53 25 PM" src="https://github.com/user-attachments/assets/3cac266f-4f56-46ea-9270-fdc44575f8bd" /> <br>

<img width="449" height="717" alt="Screen Shot 2026-07-27 at 3 53 32 PM" src="https://github.com/user-attachments/assets/3020ad5c-2af3-4ca1-a402-38830196bcbd" /> <br>

### good proof is contextual

poidh doesn't attempt to define a universal standard for "proof."

Instead, the bounty creator defines what would make the outcome observable — and the community evaluates the resulting evidence.

Consider a bounty asking someone to **cook their grandmother's dish**.

A photo of finished food demonstrates that food exists. It doesn't necessarily demonstrate that the claimant cooked it.

A photo with an older woman demonstrates they were together. It doesn't necessarily demonstrate she's their grandmother.

A stronger claim might include evidence of the cooking process, the grandmother participating, and other context that establishes the relationship.

**Proof is about demonstrating the outcome, not merely producing a related photograph.**

---

## 5. verify it

Claims are evaluated by the poidh community.

Every wallet that has contributed funds to a bounty earns voting rights proportional to their contribution. When a claim is submitted for vote, contributors have **48 hours** to vote yes or no.

- if **>50% of participating voters approve**, the claim passes and payment executes automatically
- if **>50% vote no**, the bounty resets — the creator can submit a new claim or cancel entirely, and contributors can withdraw their funds

This is the mechanism that makes poidh trustless. No single party controls the outcome. The bounty creator can't unilaterally pay a fake claim. Contributors can't steal the funds. The protocol enforces the result.

**The claimant provides evidence. The community evaluates it. The protocol records the result.**

---

## 6. pay

If a claim passes the vote, the bounty pays out automatically to the claimant — minus a 2.5% protocol fee.

No manual disbursement. No trusted intermediary. No waiting on anyone.

The result is a complete coordination cycle:

> a desired outcome was expressed.
> an incentive was attached.
> someone made it happen.
> they provided evidence.
> the community verified it.
> the incentive was paid.

The ephemeral DAO dissolves. The onchain record of what happened remains forever.

---

## what makes poidh different from a traditional bounty board?

Most bounty platforms are one-to-one: one poster, one worker, one approver.

poidh is many-to-many:

**One person can ask. Many people can fund. Anyone can do. The community verifies.**

This creates a social dynamic that traditional bounty boards don't have. When you contribute to a poidh bounty, you're not just adding money — you're signaling that you believe this outcome is worth achieving. Other people can see that signal and add their own. The bounty price becomes a real-time measure of how much a community values a specific outcome happening in the world.

---

## what happens if a claim doesn't satisfy the bounty?

The reward is attached to the outcome, not the attempt.

If a claim doesn't pass the vote, the bounty resets. The creator can submit a different claim, contributors can withdraw, or the bounty can be cancelled entirely — returning all funds to contributor wallets.

---

## the complete lifecycle

A poidh bounty can be understood as five layers:

**intent** → *"I want this to happen."*

**incentive** → *"I'm willing to pay for it."*

**action** → *"Someone is willing to make it happen."*

**evidence** → *"Here's why you should believe it happened."*

**verification** → *"The community agrees the evidence is sufficient."*

The payout is the final consequence of that verification.

This is the fundamental mechanism behind poidh.

## further reading

- [The Ephemeral DAO Machine](https://words.poidh.xyz/the-ephemeral-dao-machine)
- [poidh open bounties guide](https://words.poidh.xyz/poidh-open-bounties-guide)


