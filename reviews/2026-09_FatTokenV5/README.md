# Template review: FatTokenV5

**Subject** the `FatTokenV5` launchpad token template
**Specimen** Baby Goatseus Maximus (BabyGOAT), Ethereum mainnet
[`0x26d86F942D514B470Ba5dF311027a870110F6699`](https://etherscan.io/address/0x26d86F942D514B470Ba5dF311027a870110F6699)
**Reviewer** Vu Duy Khang ([github.com/Vuduykhang2306](https://github.com/Vuduykhang2306))
**Date** September 2026

> Unsolicited public review. Nobody asked me to do this, and I have no
> connection to anyone who deployed this template. I chose a dead contract on
> purpose: the specimen's liquidity pool holds 0.54 ETH and its ownership is
> renounced, so nothing written here can cost anyone money. No vulnerability in
> this report lets a third party steal funds. Every serious finding is a power
> the deployer holds over holders, and holders are better off knowing about it.
>
> What I reviewed is the template, not this one deployment. Most of the
> findings below can't be reached on the specimen because its owner renounced.
> They can be reached on deployments where the owner didn't.

---

## 1. Why the template and not the deployment

The specimen doesn't do anything anymore. Ownership is `0x…dEaD`, every fee is
0 and every limit is off. A review of only this address would be a two-line
report saying that.

The code is what's worth reviewing. A launchpad deploys the same bytecode again
and again, and each deployment picks its own configuration in the constructor.
So the question I cared about was "what does this code let a deployer do, and
can a buyer tell before buying?", more than "has this particular token been
abused?".

The answer was cleaner than I expected, and it's the main result of this
review:

> Every dangerous power in this template is switched on or off in the
> constructor, and no function can switch any of them back on.
> `enableKillBlock`, `enableRewardList` and `enableChangeTax` have no setters.
> `disableChangeTax()` exists and only works one way. So a buyer can read five
> values on-chain and know exactly which of the findings below apply to the
> token in front of them, for good, before buying.

Section 6 lists the five calls.

## 2. Scope

| | |
|---|---|
| Source | Verified source of the specimen, vendored unmodified at [`FatTokenV5.sol`](FatTokenV5.sol) |
| Compiler | `0.8.4+commit.c7e474f2`, reviewed under `0.8.24` |
| Lines | 876 |
| Out of scope | Uniswap V2 router/pair and WETH, treated as trusted |

Proofs of concept: [`test/fork/FatTokenV5.t.sol`](../../test/fork/FatTokenV5.t.sol).
Findings that need the owner are proved on a fresh instance, configured the way
the template allows. Findings that don't depend on configuration are proved
against the specimen's live bytecode on a mainnet fork.

## 3. Method

1. Target selection, done with scripts. I pulled about 485 ERC-20s from
   Blockscout across ten memecoin keywords and kept the ones with no price and
   no market cap. Then I filtered for verified source plus six tax-token
   markers. I read liquidity on-chain instead of trusting the indexer, and that
   removed two candidates that looked dead but still held 12.7 and 5.4 ETH.
2. Manual review of all 876 lines, function by function, against
   [`docs/checklist-erc20.md`](../../docs/checklist-erc20.md).
3. Read the on-chain state before deciding whether anything is exploitable:
   ownership, every feature flag, every fee, the pair reserves.
4. A PoC for each finding, on a mainnet fork.
5. A deployment survey, to find other instances of the same template and check
   whether they had renounced (section 5).

## 4. Findings

| ID | Severity | Title | Reachable on specimen |
|---|---|---|---|
| [T-01](#t-01) | High | Kill block permanently blacklists early buyers, and `setkb()` has no ceiling | No, `enableKillBlock` is false at construction |
| [T-02](#t-02) | High | `multi_bclist()` freezes any holder on demand | No, ownership renounced |
| [T-03](#t-03) | Medium | `completeCustoms()` moves the sell tax to 24.99% at any time | No, ownership renounced |
| [T-04](#t-04) | Medium | `setNumTokensSellRate()` is unbounded; a large value makes every sell revert | No, ownership renounced |
| [T-05](#t-05) | Low | `setEnableTransferFee()` never writes the flag it is named after | Latent |
| [T-06](#t-06) | Low | Airdrop loop underflows on trades below `airdropNumbs` | Yes |
| [T-07](#t-07) | Low | `transferFrom()` moves tokens before touching the allowance | Yes |
| [T-08](#t-08) | Info | `decimals()` returns `uint256`, breaking strict `IERC20` consumers | Yes |

Totals: 2 High, 2 Medium, 3 Low, 1 Informational.

No finding in this review lets an arbitrary third party take funds. The two
Highs are powers the deployer holds, and that's why I think the report is fine
to publish as it is.

---

<a id="t-01"></a>
### T-01: Kill block, plus an uncapped `setkb()`

**Severity** High · **Reachable on specimen** No

`_transfer` blacklists anyone who buys inside a window after launch:

```solidity
if (enableOffTrade && enableKillBlock && block.number < startTradeBlock + kb) {
    if (!_swapPairList[to]) _rewardList[to] = true;
}
```

and the first lines of `_transfer` make that permanent:

```solidity
if (isReward(from) > 0) { require(false, "isReward > 0 !"); }
```

The check is on `from`, so a flagged address keeps its balance but can never
move it. `_rewardList` has no expiry, and only the owner can clear it.

It's sold as anti-sniper protection, but it can't tell a sniper from anyone
else who buys in the first `kb` blocks. On top of that, `setkb()` takes any
`uint256`, can be called after launch, and has no ceiling:

```solidity
function setkb(uint256 a) public onlyOwner { kb = a; }
```

So the window isn't fixed at launch. The owner can reopen it at any time, and
every buyer after that is frozen the moment they buy. That's a full honeypot in
one transaction, with no warning.

PoC: `forge test --match-contract T01 -vv`.
A buyer inside the window is flagged by their own purchase and still can't sell
100,000 blocks later. A second test shows the window closing normally, then the
owner calling `setkb(100_000_000)`, and the next buyer getting trapped.

Recommendation: cap `kb` in the setter and don't allow raising it after
`startTradeBlock`. Give `_rewardList` entries an expiry. Better still, drop the
mechanism. An anti-sniper feature that permanently takes away the ability to
sell can't be told apart from a trap.

---

<a id="t-02"></a>
### T-02: `multi_bclist()` freezes arbitrary holders

**Severity** High · **Reachable on specimen** No

```solidity
function multi_bclist(address[] calldata addresses, bool value) public onlyOwner {
    require(enableRewardList, "rewardList disabled");
    require(addresses.length < 201);
    for (uint256 i; i < addresses.length; ++i) { _rewardList[addresses[i]] = value; }
}
```

Together with the `isReward(from)` check, this lets the owner freeze any
holder's whole balance whenever they want, 200 addresses at a time, with no
notice, no delay and no way to appeal. The name is a problem on its own: a
mapping called `_rewardList` that is really a blacklist reads like deliberate
obfuscation to anyone skimming the source.

PoC: `forge test --match-contract T02 -vv`. A holder is blacklisted and can no
longer sell, or even send tokens to another wallet.

Recommendation: remove it. If a freeze feature is really needed, put it behind
a timelock and emit an event.

---

<a id="t-03"></a>
### T-03: `completeCustoms()` raises the tax to 24.99% instantly

**Severity** Medium · **Reachable on specimen** No

One call rewrites six fees, limited only by a total under 2500 basis points per
side. While `enableChangeTax` is true, a token that launched at 5% can be at
24.99% in the next block, with no timelock and no event.

The bound is checked after the values are assigned instead of before. That
isn't exploitable, since a failed `require` reverts the whole transaction, but
it's the wrong order and should be fixed.

PoC: `forge test --match-contract T03 -vv`. The token launches at 5%, the
owner raises the sell fee to 24.99%, and the next sell pays the new rate.

Recommendation: a ceiling in the low single digits, a timelock, and an event.

---

<a id="t-04"></a>
### T-04: `setNumTokensSellRate()` is unbounded

**Severity** Medium · **Reachable on specimen** No

```solidity
function setNumTokensSellRate(uint256 newValue) public onlyOwner {
    require(newValue != 0, "greater than 0");
    numTokensSellRate = newValue;
}
```

The value is used as `(amount * numTokensSellRate) / 100` in the sell path, and
only zero is rejected. A large enough value makes the multiplication overflow
under checked arithmetic, so it reverts, and every sell reverts with it while
buys keep working. It's a second way to get the same honeypot as T-01, through
a setter that looks like a tuning knob.

Recommendation: bound it to a sensible percentage range.

---

<a id="t-05"></a>
### T-05: `setEnableTransferFee()` does not set `enableTransferFee`

**Severity** Low · **Reachable on specimen** Latent

```solidity
function setEnableTransferFee(bool status) public onlyOwner {
    // enableTransferFee = status;
    if (status) { transferFee = _sellFundFee + _sellLPFee + _sellBurnFee; }
    else { transferFee = 0; }
}
```

The assignment is commented out. The constructor sets `enableTransferFee`
correctly, so a fresh deployment is consistent. After any call to this setter,
though, the public flag no longer matches what the contract does. A holder or a
scanner that reads `enableTransferFee()` to see whether wallet-to-wallet
transfers are taxed gets the wrong answer, and only `transferFee()` shows the
real value.

PoC: `forge test --match-contract T05 -vv`. After `setEnableTransferFee(true)`,
`transferFee()` returns 500 while `enableTransferFee()` still returns `false`.

Recommendation: restore the assignment, or delete the variable so there is only
one source of truth.

---

<a id="t-06"></a>
### T-06: Airdrop loop underflows on small trades

**Severity** Low · **Reachable on specimen** Yes

Every buy and sell sends 1 wei to each of `airdropNumbs` addresses derived from
`keccak256(abi.encodePacked(i, amount, block.timestamp))`, then does:

```solidity
amount -= airdropNumbs * 1;
```

When `amount < airdropNumbs` this underflows and reverts, so trades below that
size are impossible. In practice that costs almost nothing, 3 wei of an
18-decimal token. On the specimen, though, it can never be turned off:
`setAirDropEnable()` and `setAirdropNumbs()` are both `onlyOwner` and ownership
is renounced. So every trade for the rest of the contract's life pays gas for
three extra transfers and emits three junk `Transfer` events that no indexer
can tell apart from real activity.

The derived addresses are also fully predictable. With 1 wei at stake that
isn't worth exploiting, but the same pattern would matter if the amount were
more than dust.

PoC: `forge test --match-contract T06 -vv`, run against the live specimen. A
2 wei transfer reverts and a 3 wei transfer succeeds.

Recommendation: subtract before transferring, and require `amount >
airdropNumbs`. The author hasn't documented any legitimate purpose for the
loop.

---

<a id="t-07"></a>
### T-07: `transferFrom()` transfers before checking the allowance

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

The tokens move first and the allowance is reduced afterwards, with no
explicit check that it was large enough. An overspend is only stopped because
the subtraction underflows and reverts the transaction.

That's safe today for one reason: the compiler. Put this under `unchecked`, or
port it to a compiler without checked arithmetic, and it becomes an
unlimited-spend bug. Access control that holds by accident has the same shape
as M-01 in [the lab report](../../reports/2026-09_MemeTax_audit-report.md).

There's also a smaller side effect. When the airdrop loop runs, `_transfer`
reduces `amount` internally, but `transferFrom` still takes the original
amount off the allowance, so the spender is charged a few wei more than
actually moved.

Recommendation: `require(allowance >= amount)` before the transfer, and reduce
the allowance before the external effect.

---

<a id="t-08"></a>
### T-08: `decimals()` returns `uint256`

**Severity** Informational · **Reachable on specimen** Yes

The interface declares `function decimals() external view returns (uint256)`,
but the ERC-20 standard specifies `uint8`. Integrations that decode a `uint8`
happen to read the value correctly, but a consumer using a strict ABI, or
decoding a packed struct, won't. There's no reason to differ from the
standard.

---

## 5. How many deployments are affected

The template can be recognised on-chain by two unusual public getters,
`airdropNumbs()` and `kb()`. I probed the 485 addresses collected during target
selection:

| | |
|---|---|
| Deployments of this template found | 4 |
| Ownership renounced | 3 |
| Still owned | 1 |

The one still owned is `0xC01018662C0dF010Ad284cdE77D054e5943a2CD6` ("PEPE",
4,632 holders), owner `0x8290619A3FFC07ab573e1cfB7b7D34C5BF9F96C8`. Its
constructor flags put it in a specific position:

- `enableChangeTax = true` -> T-03 is reachable. The owner can move the sell
  tax to 24.99% at any time.
- `enableKillBlock = false`, `enableRewardList = false` -> T-01 and T-02 are
  not reachable, and can't become reachable, because neither flag has a setter.

This is only a sample. 485 tokens from ten keyword searches is a small slice of
all ERC-20s, so 4 is a lower bound. A full survey would scan every contract
that exposes both selectors.

## 6. What a buyer can check in five calls

Because exposure in this template is readable and permanent, you can check any
token you suspect is built on it:

```bash
cast call $TOKEN "owner()(address)"             --rpc-url $RPC   # renounced?
cast call $TOKEN "enableKillBlock()(bool)"      --rpc-url $RPC   # T-01
cast call $TOKEN "enableRewardList()(bool)"     --rpc-url $RPC   # T-02
cast call $TOKEN "enableChangeTax()(bool)"      --rpc-url $RPC   # T-03
cast call $TOKEN "kb()(uint256)"                --rpc-url $RPC   # size of the T-01 window
```

If `owner()` is not a burn address, every one of those booleans that is `true`
is a power that address has over you for as long as you hold the token. If it
is a burn address, none of T-01 to T-04 can ever be used.

## 7. What this review does not cover

- No economic or MEV analysis of the swap path.
- `swapTokenForFund` and the `TokenDistributor` were read but have no PoC. On
  the specimen every fee is zero, so that path never runs and couldn't be
  tested against live state.
- No fuzzing or invariant campaign against this template.
- The deployment survey is a sample (section 5).
- I found no vulnerability that lets a third party take funds. That doesn't
  prove there isn't one.

## 8. Reproducing

```bash
export ETH_RPC_URL=https://ethereum-rpc.publicnode.com
forge test --match-path "test/fork/*" -vv
```

Seven proofs of concept. T-01 to T-05 deploy a fresh instance of the vendored
source on a mainnet fork, and T-06 runs against the specimen's live bytecode.
