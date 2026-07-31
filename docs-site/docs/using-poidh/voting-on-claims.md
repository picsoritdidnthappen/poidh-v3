# voting on claims

Open bounties allow multiple people to fund the same outcome.

Because multiple contributors are putting their money behind a bounty, no single person should have permanent control over how those funds are spent.

That's where claim voting comes in.

The voting process balances two important responsibilities:

* **The bounty creator** decides which claim best fulfills the bounty.
* **Contributors** decide whether they're willing to release their funds to that claim.

Neither party has complete control over the bounty on their own.

> **Note:** Solo bounties do not use this process. If you're the only contributor to a bounty, confirming a winner immediately transfers the reward. Claim voting only exists for open bounties with multiple contributors.

---

## why voting exists

Imagine you discover a bounty you really care about.

You contribute funds because you want that outcome to happen.

Would you be comfortable if the bounty creator could permanently decide where your money goes without your approval?

Probably not.

Now imagine the opposite.

What if anyone who contributed funds could nominate any claim they wanted?

A contributor could simply submit their own fake claim, vote for it with their contribution, and attempt to take the reward for themselves.

Neither extreme works.

Instead, poidh divides responsibility:

* The bounty creator proposes **which claim should win.**
* Contributors approve **whether their funds should actually be spent on that claim.**

This creates a system where ideas can be crowdfunded without requiring contributors to blindly trust the bounty creator.

---

## the bounty creator chooses the winning claim

When claims are submitted, the bounty creator reviews them and decides which submission best fulfills the bounty.

Only the bounty creator can nominate a claim for vote.

This is intentional.

The bounty creator wrote the bounty and defined its requirements, so they're in the best position to determine which claim most accurately completed the requested outcome.

---

## why contributors can't nominate claims

This is an important design decision.

Imagine this scenario:

* Alice creates a bounty with a 1 ETH reward.
* Bob contributes another 2 ETH.
* Bob now has the majority of the voting power.

If contributors could nominate claims, Bob could simply submit a fake claim, nominate himself as the winner, vote yes with his majority voting power, and take everyone's money.

By reserving nomination exclusively for the bounty creator, poidh prevents this type of hostile takeover.

The bounty creator always decides **which** claim is proposed.

Contributors decide whether they agree with that decision.

---

## contributors vote on the nominated claim

Once a claim has been nominated, contributors can vote:

* **Yes**
* **No**
* **Abstain** (by simply not voting)

<img width="600" alt="voting-interface" src="https://github.com/user-attachments/assets/dec9e98d-31df-4be9-94cb-2472bbb5fc92" />
<br>
<br>
Every contributor's voting power is determined by how much they contributed to the bounty.

Voting power is based on **funds contributed**, not the number of wallets.

---

## how voting power works

Suppose an open bounty has received:

| Contributor | Contribution | Voting Power |
| ----------- | -----------: | -----------: |
| Alice       |        2 ETH |          40% |
| Bob         |        1 ETH |          20% |
| Carol       |        1 ETH |          20% |
| Dave        |        1 ETH |          20% |

Total bounty funding: **5 ETH**

If Alice and Bob vote **Yes**, they represent 60% of the voting power.

If Carol and Dave vote **No**, they represent 40%.

The claim passes because more than 50% of participating voting power approved it.

[DIAGRAM: 40% + 20% = 60% YES → Claim Approved]

---

## participating votes determine the outcome

Only contributors who actually vote are counted.

For example:

| Contributor | Voting Power | Vote |
| ----------- | -----------: | ---- |
| Alice       |          25% | Yes  |
| Bob         |          25% | —    |
| Carol       |          25% | —    |
| Dave        |          25% | —    |

Alice is the only contributor who votes.

That means:

* Participating voting power: **25%**
* Yes: **100%**
* No: **0%**

The claim passes because **100% of participating voting power voted yes.**

Abstaining is not the same as voting no. It is more akin to delegating your voting power to the bounty creator (whose vote is cast automatically as "yes" when they nominate a claim for vote).

If you don't participate, your voting power simply isn't counted for that vote.

---

## the 48-hour voting period

When the bounty creator nominates a claim:

* The voting period immediately begins.
* The bounty creator's voting power is automatically cast as **Yes**.
* Contributors have **48 hours** to submit their votes.

After 48 hours, anyone can resolve the vote.

---

## nominating a claim is permanent

Starting a vote is an onchain action.

Once the bounty creator nominates a claim:

* The nomination cannot be undone.
* A different claim cannot be nominated instead.
* The voting process cannot be restarted.

This is especially important if the bounty creator is also the majority contributor.

In that situation, their automatic **Yes** vote may already represent enough voting power for the claim to pass once the 48-hour voting period ends.

Treat nomination as your final decision—not as a draft or a way to "see what happens." There is no undo button.

---

## communicate before nominating

The protocol does **not** require bounty creators to ask contributors for permission before nominating a claim.

In many cases, they won't need to.

However, if a bounty has multiple contributors, it's often a good idea to communicate first.

A quick conversation can answer questions like:

* Is everyone comfortable with this submission?
* Did anyone notice something I missed?
* Are there concerns about the evidence?

Doing this can avoid an awkward situation where a bounty creator nominates a claim that contributors ultimately reject.

Good communication isn't required.

But it often leads to smoother coordination.

---

## if the vote passes

If more than 50% of participating voting power votes **Yes**, the vote succeeds.

When the vote is resolved:

* The bounty reward is sent to the winning claimant (minus the 2.5% protocol fee).
* The winning claim NFT is transferred to the bounty creator.
* The bounty is complete.

Even contributors who voted **No** still have their funds included in the payout.

The vote determines whether the nominated claim receives the bounty—not which contributors participate in paying it.

---

## if the vote fails

If more than 50% of participating voting power votes **No**, the claim is vetoed.

No funds are distributed.

The bounty returns to its previous state.

After a failed vote:

* Contributors can withdraw their funds.
* The bounty creator can nominate a different claim.
* The bounty creator can cancel the bounty entirely, returning funds to contributors.

This prevents contributor funds from becoming permanently locked behind a disagreement.

---

## resolving votes

Resolving votes does not happen automatically. It requires someone to call the "resolve vote" function after the 48-hour voting window has concluded.

<img width="1061" height="703" alt="resolve vote button" src="https://github.com/user-attachments/assets/2aa4d8e9-b75a-4c30-8c6d-6699acd1201b" />
<br>
<br>
Any wallet can fulfill this function, even wallets which were not involved in the bounty to begin with. 

---

## before you vote

Before casting your vote, ask yourself:

**Does this claim satisfy the bounty as it was written?**

**Does the evidence support the submission?**

**Would I be comfortable releasing my contribution to this claimant?**

If the answer is yes, vote **Yes**.

If not, vote **No**.

If you don't have enough information to make a decision, you can simply abstain by not voting.

---

# coordination without centralized control

The voting process exists to protect everyone involved.

The bounty creator decides which claim best fulfills the requested outcome.

Contributors decide whether that claim should receive the pooled reward.

Neither side has complete control.

Instead, they work together to coordinate around a shared goal.

That's the core idea behind poidh open bounties:

**Crowdfund an outcome.
Find the best submission.
Verify it together.
Reward the work.**

