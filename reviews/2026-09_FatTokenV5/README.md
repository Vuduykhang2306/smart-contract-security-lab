# Template review — FatTokenV5

**Subject** the `FatTokenV5` launchpad token template
**Specimen** Baby Goatseus Maximus (BabyGOAT), Ethereum mainnet
[`0x26d86F942D514B470Ba5dF311027a870110F6699`](https://etherscan.io/address/0x26d86F942D514B470Ba5dF311027a870110F6699)
**Reviewer** Vu Duy Khang — [github.com/Vuduykhang2306](https://github.com/Vuduykhang2306)
**Date** September 2026

> **Unsolicited public review.** Nobody commissioned this and I have no
> relationship with anyone who deployed this template. I picked a dead contract
> on purpose: the specimen's liquidity pool holds 0.54 ETH and its ownership is
> renounced, so nothing written here takes money from anyone. No vulnerability
> in this report lets a third party steal funds — every serious finding is a
> power the *deployer* holds over holders, which is information holders benefit
> from having.
>
> The review subject is the **template**, not this one deployment. Most of the
> findings below are unreachable on the specimen precisely because its owner
> renounced. They are reachable on deployments that did not.

---

## 1. Why the template and not the deployment

The specimen is inert. Ownership is `0x…dEaD`, every fee is 0, every limit is
off. Reviewing only this address would produce a two-line report saying so.

What is worth reviewing is the code, because the same bytecode is deployed
repeatedly by a launchpad and each deployment chooses its own configuration at
construction. The interesting question is not *"has this one been abused"* but
*"what does this code let a deployer do, and can a buyer tell in advance"*.

The answer turns out to be unusually clean, and it is the main result of this
review:

> **Every dangerous power in this template is switched on or off in the
> constructor, and there is no function that can switch any of them back on.**
> `enableKillBlock`, `enableRewardList` and `enableChangeTax` have no setters.
> `disableChangeTax()` exists and is one-way. So a buyer can read five booleans
> on-chain and know exactly which of the findings below apply to the token in
> front of them, permanently, before buying.

Section 6 lists the five calls.

## 2. Scope

| | |
|---|---|
| Source | Verified source of the specimen, vendored unmodified at [`FatTokenV5.sol`](FatTokenV5.sol) |
| Compiler | `0.8.4+commit.c7e474f2`, reviewed under `0.8.24` |
| Lines | 876 |
| Out of scope | Uniswap V2 router/pair and WETH, treated as trusted |

Proofs of concept: [`test/fork/FatTokenV5.t.sol`](../../test/fork/FatTokenV5.t.sol).
Owner-gated findings are proved on a fresh instance configured the way the
template permits. Configuration-independent findings are proved against the
specimen's live bytecode on a mainnet fork.

## 3. Method

1. **Target selection, scripted.** Pulled ~485 ERC-20s from Blockscout across
   ten memecoin keywords, kept those with no price and no market cap, then
   filtered on verified source plus six tax-token markers. Liquidity was then
   read on-chain rather than trusted from the indexer — that check removed two
   candidates that looked dead but still held 12.7 and 5.4 ETH.
2. **Manual review** of all 876 lines, function by function, against
   [`docs/checklist-erc20.md`](../../docs/checklist-erc20.md).
3. **On-chain state read** before drawing any conclusion about exploitability:
   ownership, every feature flag, every fee, the pair reserves.
4. **PoC per finding**, on a mainnet fork.
5. **Deployment survey** to find other instances of the same template and check
   whether they had renounced (section 5).

## 4. Findings

| ID | Severity | Title | Reachable on specimen |
|---|---|---|---|
| [T-01](#t-01) | High | Kill block permanently blacklists early buyers, and `setkb()` has no ceiling | No — `enableKillBlock` false at construction |
| [T-02](#t-02) | High | `multi_bclist()` freezes any holder on demand | No — ownership renounced |
| [T-03](#t-03) | Medium | `completeCustoms()` moves the sell tax to 24.99% at any time | No — ownership renounced |
| [T-04](#t-04) | Medium | `setNumTokensSellRate()` is unbounded; a large value makes every sell revert | No — ownership renounced |
| [T-05](#t-05) | Low | `setEnableTransferFee()` never writes the flag it is named after | Latent |
| [T-06](#t-06) | Low | Airdrop loop underflows on trades below `airdropNumbs` | **Yes** |
| [T-07](#t-07) | Low | `transferFrom()` moves tokens before touching the allowance | **Yes** |
| [T-08](#t-08) | Info | `decimals()` returns `uint256`, breaking strict `IERC20` consumers | **Yes** |

Totals: 2 High, 2 Medium, 3 Low, 1 Informational.

**No finding in this review lets an arbitrary third party take funds.** The two
Highs are powers the deployer holds. That distinction is why this report is
publishable as-is.

---

<a id="t-01"></a>
### T-01 — Kill block, plus an uncapped `setkb()`

**Severity** High · **Reachable on specimen** No

`_transfer` blacklists any buyer inside a window after launch:

```solidity
if (enableOffTrade && enableKillBlock && block.number < startTradeBlock + kb) {
    if (!_swapPairList[to]) _rewardList[to] = true;
}
```

and the first lines of `_transfer` make that permanent:

```solidity
if (isReward(from) > 0) { require(false, "isReward > 0 !"); }
```

The blacklist is checked on `from`, so a flagged address keeps its balance and
can never move it. `_rewardList` has no expiry; only the owner can clear it.

Sold as anti-sniper protection, the mechanism does not distinguish a sniper
from anyone else who buys in the first `kb` blocks. Worse, `setkb()` takes any
`uint256`, can be called after launch, and has no ceiling:

```solidity
function setkb(uint256 a) public onlyOwner { kb = a; }
```

So the window is not a launch-time decision. An owner can reopen it at any
point and every subsequent buyer is frozen on arrival — a complete honeypot,
one transaction, no warning.

**PoC** `forge test --match-contract T01 -vv`
A buyer inside the window is flagged by their own purchase and still cannot sell
100,000 blocks later. A second test shows the window closing normally, the owner
calling `setkb(100_000_000)`, and the next buyer being trapped.

**Recommendation** Cap `kb` in the setter and forbid raising it after
`startTradeBlock`. Give `_rewardList` entries an expiry. Better: drop the
mechanism — an anti-sniper device that permanently confiscates the ability to
sell is indistinguishable from a trap.

---

<a id="t-02"></a>
### T-02 — `multi_bclist()` freezes arbitrary holders

**Severity** High · **Reachable on specimen** No

```solidity
function multi_bclist(address[] calldata addresses, bool value) public onlyOwner {
    require(enableRewardList, "rewardList disabled");
    require(addresses.length < 201);
    for (uint256 i; i < addresses.length; ++i) { _rewardList[addresses[i]] = value; }
}
```

Combined with the `isReward(from)` check, the owner can freeze any holder's
entire balance at will, 200 at a time, with no notice, no delay and no appeal.
The naming is worth flagging on its own: a mapping called `_rewardList` that
functions purely as a blacklist reads as deliberate obfuscation for anyone
skimming the source.

**PoC** `forge test --match-contract T02 -vv` — a holder is blacklisted and can
no longer sell or even make a wallet-to-wallet transfer.

**Recommendation** Remove it. If a freeze capability is genuinely required, put
it behind a timelock and emit an event.

---

<a id="t-03"></a>
### T-03 — `completeCustoms()` raises the tax to 24.99% instantly

**Severity** Medium · **Reachable on specimen** No

Six fees are rewritten in one call, bounded only by a total under 2500 basis
points per side. While `enableChangeTax` holds, a token that launched at 5% can
be at 24.99% in the next block, with no timelock and no event.

The bound is checked after the assignments rather than before. That is not
exploitable — a failed `require` reverts the whole transaction — but it is the
wrong order and worth fixing.

**PoC** `forge test --match-contract T03 -vv` — launches at 5%, owner raises the
sell fee to 24.99%, the next sell settles at the new rate.

**Recommendation** A ceiling in the low single digits, a timelock, and an event.

---

<a id="t-04"></a>
### T-04 — `setNumTokensSellRate()` is unbounded

**Severity** Medium · **Reachable on specimen** No

```solidity
function setNumTokensSellRate(uint256 newValue) public onlyOwner {
    require(newValue != 0, "greater than 0");
    numTokensSellRate = newValue;
}
```

The value is used as `(amount * numTokensSellRate) / 100` inside the sell path.
Only zero is rejected. A sufficiently large value overflows the multiplication
under checked arithmetic, so the multiplication reverts and **every sell reverts
with it** while buys keep working. A second route to the same honeypot as T-01,
reached from a setter that looks like a tuning knob.

**Recommendation** Bound it to a sane percentage range.

---

<a id="t-05"></a>
### T-05 — `setEnableTransferFee()` does not set `enableTransferFee`

**Severity** Low · **Reachable on specimen** Latent

```solidity
function setEnableTransferFee(bool status) public onlyOwner {
    // enableTransferFee = status;
    if (status) { transferFee = _sellFundFee + _sellLPFee + _sellBurnFee; }
    else { transferFee = 0; }
}
```

The assignment is commented out. The constructor sets `enableTransferFee`
correctly, so a fresh deployment is consistent — but after any call to this
setter, the public flag and the behaviour it names disagree. A holder or a
scanner reading `enableTransferFee()` to decide whether wallet-to-wallet
transfers are taxed gets a wrong answer, and `transferFee()` is the only place
the truth appears.

**PoC** `forge test --match-contract T05 -vv` — after `setEnableTransferFee(true)`,
`transferFee()` returns 500 while `enableTransferFee()` still returns `false`.

**Recommendation** Restore the assignment, or delete the variable so there is
one source of truth.

---

<a id="t-06"></a>
### T-06 — Airdrop loop underflows on small trades

**Severity** Low · **Reachable on specimen** Yes

Every buy and sell sends 1 wei to each of `airdropNumbs` addresses derived from
`keccak256(abi.encodePacked(i, amount, block.timestamp))`, then:

```solidity
amount -= airdropNumbs * 1;
```

When `amount < airdropNumbs` this underflows and reverts, so trades below that
size are impossible. The practical cost is trivial — 3 wei of an 18-decimal
token — but on the specimen the behaviour is frozen: `setAirDropEnable()` and
`setAirdropNumbs()` are both `onlyOwner` and ownership is renounced, so every
trade for the rest of the contract's life pays gas for three extra transfers
and emits three junk `Transfer` events that no indexer can distinguish from
real activity.

The derived addresses are also fully deterministic. With 1 wei at stake this is
not worth exploiting, but the pattern would matter if the amount were not dust.

**PoC** `forge test --match-contract T06 -vv` — run against the live specimen:
a 2 wei transfer reverts, a 3 wei transfer succeeds.

**Recommendation** Subtract before transferring, and require `amount >
airdropNumbs`. The loop itself has no legitimate purpose that the author has
documented.

---

<a id="t-07"></a>
### T-07 — `transferFrom()` transfers before checking the allowance

**Severity** Low · **Reachable on specimen** Yes

```solidity
function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
    _transfer(sender, recipient, amount);
    if (_allowances[sender][msg.sender] != MAX) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
    }
    return true;
}
```

The tokens move first; the allowance is decremented afterwards, with no explicit
check that it was ever large enough. An over-spend is stopped only because the
subtraction underflows and reverts the transaction.

This is safe today, and safe for exactly one reason: the compiler. Restore this
under `unchecked`, or port it to a compiler without checked arithmetic, and it
becomes an unlimited-spend bug. Access control that holds by accident is the
same shape as M-01 in [the lab report](../../reports/2026-09_MemeTax_audit-report.md).

There is a second, minor consequence: when the airdrop loop fires, `_transfer`
reduces `amount` internally, but `transferFrom` still debits the allowance by
the original figure, so the spender is charged for a few wei more than moved.

**Recommendation** `require(allowance >= amount)` before the transfer, and
decrement before the external effect.

---

<a id="t-08"></a>
### T-08 — `decimals()` returns `uint256`

**Severity** Informational · **Reachable on specimen** Yes

The interface declares `function decimals() external view returns (uint256)`.
The ERC-20 standard specifies `uint8`. Integrations that decode a `uint8` will
read the value correctly by accident, but any consumer using a strict ABI, or
decoding a packed struct, will not. There is no reason to deviate.

---

## 5. How many deployments are affected

The template is identifiable on-chain by two unusual public getters,
`airdropNumbs()` and `kb()`. Probing the 485 addresses collected during target
selection:

| | |
|---|---|
| Deployments of this template found | 4 |
| Ownership renounced | 3 |
| **Still owned** | **1** |

The one still owned is `0xC01018662C0dF010Ad284cdE77D054e5943a2CD6` ("PEPE",
4,632 holders), owner `0x8290619A3FFC07ab573e1cfB7b7D34C5BF9F96C8`. Its
constructor flags put it in a specific position:

- `enableChangeTax = true` → **T-03 is reachable**. The owner can move the sell
  tax to 24.99% at any time.
- `enableKillBlock = false`, `enableRewardList = false` → T-01 and T-02 are
  **not** reachable, and cannot become reachable, because neither flag has a
  setter.

**This is a sample, not a census.** 485 tokens drawn from ten keyword searches
is a small slice of the ERC-20 space, so 4 is a floor. A full survey would scan
every contract exposing both selectors.

## 6. What a buyer can check in five calls

The practical value of this template's design is that exposure is readable and
permanent. Against any token suspected of using it:

```bash
cast call $TOKEN "owner()(address)"             --rpc-url $RPC   # renounced?
cast call $TOKEN "enableKillBlock()(bool)"      --rpc-url $RPC   # T-01
cast call $TOKEN "enableRewardList()(bool)"     --rpc-url $RPC   # T-02
cast call $TOKEN "enableChangeTax()(bool)"      --rpc-url $RPC   # T-03
cast call $TOKEN "kb()(uint256)"                --rpc-url $RPC   # size of the T-01 window
```

If `owner()` is not a burn address, whichever of those booleans is `true` is a
power that address holds over you for as long as you hold the token. If it is a
burn address, none of T-01 to T-04 can ever be exercised.

## 7. What this review does not cover

- No economic or MEV analysis of the swap path.
- `swapTokenForFund` and the `TokenDistributor` were read but have no PoC; on
  the specimen every fee is zero, so the path is dead and could not be
  exercised against live state.
- No fuzzing or invariant campaign against this template.
- The deployment survey is a sample (section 5).
- I found no vulnerability allowing a third party to take funds. Absence of a
  finding is not proof of absence.

## 8. Reproducing

```bash
export ETH_RPC_URL=https://ethereum-rpc.publicnode.com
forge test --match-path "test/fork/*" -vv
```

Seven proofs of concept. T-01 to T-05 deploy a fresh instance of the vendored
source on a mainnet fork; T-06 runs against the specimen's live bytecode.
