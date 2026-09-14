# Security Assessment — MemeTax

**Target** `src/MemeTax.sol`
**Type** ERC-20 tax token with DEX fee swap, wallet limits, blacklist and an ETH dividend pool
**Auditor** Vu Duy Khang — [github.com/Vuduykhang2306](https://github.com/Vuduykhang2306)
**Review period** September 2026
**Report version** 1.0

> **This is a self-directed practice engagement.** The target contract was written
> for this repository to reproduce the bug classes that real meme-coin launches
> ship. It is not a client deliverable and no third-party code was reviewed. The
> report follows the structure and severity conventions used by public audit
> firms so that the workflow — scope, findings, proof of concept, remediation,
> retest — is the same one a real engagement uses.

---

## 1. Scope

| File | nSLOC | In scope |
|---|---:|:--:|
| `src/MemeTax.sol` | 106 | Yes |
| `src/base/MinimalERC20.sol` | 56 | No — plain ERC-20 base, reviewed for context only |
| `src/interfaces/IDexRouter.sol` | 11 | No — interface |

Out of scope: the DEX router and pair implementations, which are modelled by
`test/mocks/MockDexRouter.sol`. Their behaviour is assumed to match Uniswap V2 —
in particular that `swapExactTokensForETHSupportingFeeOnTransferTokens` pulls the
input tokens directly to the pair with `transferFrom`, which re-enters the token's
`_transfer`. That assumption is what makes M-01 reachable.

Compiler: `solc 0.8.24`, optimizer on, 200 runs. Arithmetic is checked by default;
no `unchecked` block in the target performs user-influenced arithmetic.

## 2. Methodology

1. **Threat modelling.** Enumerate the actors (deployer/owner, LP, holder,
   arbitrary caller, fee wallets, router) and what each one should *not* be able
   to do. For a tax token the two questions that matter are "can a holder be
   stopped from selling?" and "can value leave along a path nobody intended?".
2. **Manual review**, function by function, against the checklist in
   [`docs/checklist-erc20.md`](../docs/checklist-erc20.md). Every external
   function was checked for access control, every state-changing path for
   Checks-Effects-Interactions, and every arithmetic expression for operation
   order.
3. **Static analysis.** `forge lint` was run over the target; its findings are
   noted in section 5 and were treated as leads, not conclusions.
4. **Proof of concept.** Each accepted finding was reproduced as a failing
   security property in Foundry before it was written up. A finding without a
   runnable PoC is reported as informational.
5. **Remediation and retest.** Fixes were implemented in
   `src/fixed/MemeTaxFixed.sol` and every PoC was replayed against it in
   `test/Retest_Fixed.t.sol`.

## 3. Severity classification

Severity is `impact x likelihood`, the convention used by Code4rena and Sherlock.

| | Low likelihood | Medium likelihood | High likelihood |
|---|---|---|---|
| **High impact** | Medium | High | High |
| **Medium impact** | Low | Medium | Medium |
| **Low impact** | Low | Low | Low |

*Impact* is measured as loss of user funds, loss of protocol funds, or loss of
availability. *Likelihood* accounts for who must act and what must be true first.
Centralisation risks are reported at the severity they carry for a holder who
cannot exit, not at the severity they carry for the deployer.

## 4. Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| [H-01](#h-01) | High | Reentrancy in `claimDividend()` drains the entire dividend pool | Fixed |
| [H-02](#h-02) | High | `setBlacklist()` has no access control — anyone can freeze any holder | Fixed |
| [H-03](#h-03) | High | `setTaxes()` has no upper bound — the token can be turned into a honeypot after launch | Fixed |
| [M-01](#m-01) | Medium | `_swapBack()` has no reentrancy lock and relies on an undocumented invariant | Fixed |
| [M-02](#m-02) | Medium | Fee payouts ignore their return value — distribution fails silently | Fixed |
| [L-01](#l-01) | Low | Fee arithmetic divides before it multiplies | Fixed |
| [L-02](#l-02) | Low | `setMaxWallet(0)` freezes every non-exempt transfer | Fixed |
| [I-01](#i-01) | Info | Privileged setters emit no events | Fixed |

Totals: 3 High, 2 Medium, 2 Low, 1 Informational.

---

<a id="h-01"></a>
### H-01 — Reentrancy in `claimDividend()` drains the entire dividend pool

**Severity** High (high impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:106-114`

#### Description

`claimDividend()` sends ETH before it clears the caller's recorded balance:

```solidity
function claimDividend() external {
    uint256 amount = pendingDividend[msg.sender];
    require(amount > 0, "NOTHING_TO_CLAIM");

    (bool ok,) = msg.sender.call{value: amount}("");   // interaction
    require(ok, "ETH_TRANSFER_FAILED");

    pendingDividend[msg.sender] = 0;                   // effect, too late
}
```

The low-level `call` forwards all remaining gas, so a contract recipient runs
arbitrary code inside its `receive()` hook. At that moment `pendingDividend`
still holds the caller's original entitlement, so re-entering `claimDividend()`
passes the `require` again and sends the same amount a second time. The loop
continues until the contract's ETH balance is smaller than one payout.

This is a Checks-Effects-Interactions violation. There is no reentrancy guard on
the function or anywhere else in the contract.

#### Impact

Any holder able to deploy a contract steals the whole dividend pool, including
every other holder's share. Victims keep a non-zero `pendingDividend` balance
that is no longer backed by ETH, so their claims revert on
`ETH_TRANSFER_FAILED` — the loss is silent until they try to withdraw.

#### Proof of concept

`test/H01_ReentrancyClaimDividend.t.sol`, attacker in
`test/attackers/ReentrantClaimer.sol`.

```
forge test --match-contract H01 -vv
```

Pool: 10 ETH. Attacker entitlement: 1 ETH. Alice entitlement: 9 ETH.
After `attacker.attack()` the attacker holds 10 ETH, the contract holds 0, and
Alice's claim reverts.

#### Recommendation

Apply Checks-Effects-Interactions — zero the balance before the external call —
and add an explicit `nonReentrant` guard so the invariant does not depend on
statement order surviving future edits.

#### Remediation

Fixed in `src/fixed/MemeTaxFixed.sol`. The balance is cleared before the call and
`claimDividend()` carries a `nonReentrant` modifier. Retest:
`test_retest_H01_reentrancy_no_longer_drains_the_pool` — the attacker receives
exactly 1 ETH, `reentries() == 0`, and Alice still withdraws 9 ETH.

---

<a id="h-02"></a>
### H-02 — `setBlacklist()` has no access control

**Severity** High (high impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:77-79`

#### Description

Every other privileged setter in the contract carries `onlyOwner`.
`setBlacklist()` does not:

```solidity
function setBlacklist(address account, bool blacklisted) external {
    isBlacklisted[account] = blacklisted;
}
```

`_transfer()` reverts when either party is blacklisted, so the mapping is a hard
freeze on an address's balance.

The omission is easy to miss in review precisely because the surrounding
functions are guarded — the eye reads the block as uniformly protected. It is
the single most common high-severity finding in token contracts.

#### Impact

Any address can permanently freeze any holder, including the liquidity pair —
blacklisting `pair` halts all trading. An attacker can also clear a blacklist
entry set by the owner, so the control is useless as a defensive tool as well.
No funds move, but arbitrary holders lose access to theirs.

#### Proof of concept

`test/H02_BlacklistAccessControl.t.sol`

```
forge test --match-contract H02 -vv
```

`mallory`, an address with no role, blacklists `alice`; Alice's transfers and
sells then revert with `BLACKLISTED`. A second test shows `mallory` removing an
owner-set blacklist entry on itself.

#### Recommendation

Add `onlyOwner`. More generally, do not rely on reading a block of setters and
assuming consistency: enumerate every `external`/`public` state-changing
function and record its expected caller before checking the modifiers.

#### Remediation

Fixed. `setBlacklist()` is `onlyOwner` and emits `BlacklistUpdated`. Retest:
`test_retest_H02_blacklist_is_owner_only`.

---

<a id="h-03"></a>
### H-03 — `setTaxes()` has no upper bound

**Severity** High (high impact, medium likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:69-72`

#### Description

```solidity
function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
    buyTax = _buyTax;
    sellTax = _sellTax;
}
```

The function is correctly restricted to the owner, but there is no ceiling on
the value. With `sellTax = 100`, `_transfer()` routes the entire amount to the
contract as fee and delivers `net == 0` to the pair.

The owner key is a single EOA; there is no timelock, no multisig and no
two-step transfer. The change takes effect in the same block it is sent.

#### Impact

The contract can be converted into a honeypot at any time after launch: buyers
get in at 5% and then cannot get out. This is the exact shape of the majority of
rug pulls on tax tokens, and it is indistinguishable from a compromised owner
key. A holder has no on-chain guarantee that the tax they bought under is the
tax they will sell under.

Reported as High rather than as a centralisation note because the affected party
— a holder who cannot exit — loses their full position, and because nothing
about the deployed bytecode constrains the outcome.

#### Proof of concept

`test/H03_UnboundedTax.t.sol`

```
forge test --match-contract H03 -vv
```

After `setTaxes(0, 100)`, Alice's sell of 1,000 tokens delivers 0 to the pair
while her balance still decreases.

#### Recommendation

Enforce a hard cap in the setter — a `MAX_TAX` constant checked on every write,
so the ceiling lives in the bytecode rather than in a policy document. Transfer
ownership to a timelock or multisig and publish the delay. Do not rely on
`renounceOwnership()` alone: it removes the ability to fix a bug along with the
ability to abuse one.

#### Remediation

Fixed. `MAX_TAX = 10` is enforced on both values; `setTaxes(0, 100)` reverts with
`TaxTooHigh(100, 10)`. Retest: `test_retest_H03_tax_is_capped`.

---

<a id="m-01"></a>
### M-01 — `_swapBack()` has no reentrancy lock

**Severity** Medium (high impact, low likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:126-131`, `src/MemeTax.sol:157-176`

#### Description

The fee swap is triggered from inside `_transfer()`:

```solidity
if (to == pair && !isExcludedFromFee[from] && balanceOf[address(this)] >= swapThreshold) {
    _swapBack();
}
```

`_swapBack()` calls the router, and the router moves the tokens to the pair with
`transferFrom(token, pair, amountIn)` — which re-enters `_transfer()` with
`to == pair`. The only reason that re-entry does not trigger a second
`_swapBack()` is the `!isExcludedFromFee[from]` term: `from` is the token
contract, which the constructor marks fee-exempt.

So the contract is protected, but by a mapping whose documented purpose is fee
exemption, not reentrancy. The dependency is not stated anywhere and is not
enforced. `setExcludedFromFee(address(this), false)` is a perfectly ordinary
looking admin call, and it is enough to remove the guard.

This is the reason production tax tokens carry an explicit `lockTheSwap`
modifier. The contract behaves correctly today and would break on a change that
nothing flags as dangerous.

#### Impact

Once the token contract is un-excluded, every sell re-enters until the call
stack is exhausted and reverts. Buys and wallet-to-wallet transfers keep
working, so the token silently becomes one-way — holders cannot exit while the
pool can still be bought into. Recovery requires an owner transaction; if the
owner key is lost or the owner has renounced, the state is permanent.

Likelihood is rated low because it needs a specific owner action, not because
the consequence is mild.

#### Proof of concept

`test/M01_SwapBackNoLock.t.sol`

```
forge test --match-contract M01 -vv
```

The first test shows a sell succeeding while the implicit guard holds. The
second calls `setExcludedFromFee(address(token), false)` and shows the next sell
reverting, with Alice's balance unchanged.

#### Recommendation

Add an explicit `inSwap` flag set by a `lockTheSwap` modifier on `_swapBack()`
and checked in the trigger condition. Keep the fee exemption as well — it should
be redundant, not load-bearing.

#### Remediation

Fixed. `MemeTaxFixed` carries `bool private _inSwap`, a `lockTheSwap` modifier,
and a `!_inSwap` term in the trigger. Retest:
`test_retest_M01_swap_lock_survives_un_excluding_the_token` — the same admin
action is now harmless.

---

<a id="m-02"></a>
### M-02 — Fee payouts ignore their return value

**Severity** Medium (medium impact, medium likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:173-175`

#### Description

```solidity
uint256 half = address(this).balance / 2;

marketingWallet.call{value: half}("");
devWallet.call{value: address(this).balance}("");
```

A low-level `call` reports failure through its boolean return value; it does not
revert. Both return values are discarded, so a fee wallet that cannot accept ETH
— a multisig whose fallback exceeds the forwarded gas, a contract wallet
deployed over the address after launch, or simply a wrong address — causes the
payout to fail while the surrounding sell succeeds normally.

`solc` raises `Warning (9302): Return value of low-level calls not used` on both
lines, and `forge lint` flags them as `unchecked-call`. Neither is an error, so
the contract ships.

#### Impact

ETH accumulates in the token contract with no event, no revert, and no
withdrawal function to recover it. Nothing on-chain distinguishes "fees were
distributed" from "fees were lost", so the condition can persist across many
sells before anyone notices. The loss is bounded by accumulated fees, not by
user balances, which is why this is Medium rather than High.

#### Proof of concept

`test/M02_UncheckedEthTransfer.t.sol`

```
forge test --match-contract M02 -vv
```

Both fee wallets are contracts without a `receive` function. The sell succeeds,
the fee tokens reach the pair, both wallets receive 0, and 2 ETH is stranded in
the token contract.

#### Recommendation

Prefer accrual over pushing: credit `feesOwed[wallet]` in `_swapBack()` and let
each wallet pull with a separate `withdrawFees()`. That removes the failure mode
entirely rather than converting it into a revert — checking the return value and
reverting would let a broken fee wallet block every user's sell, trading a
silent accounting loss for a denial of service.

#### Remediation

Fixed with the pull pattern. `_swapBack()` credits `feesOwed` and emits
`FeesAccrued`; `withdrawFees()` is `nonReentrant` and reverts on a failed
transfer. Retests: `test_retest_M02_fees_are_accrued_not_pushed` and
`test_retest_M02_working_wallet_can_withdraw`.

---

<a id="l-01"></a>
### L-01 — Fee arithmetic divides before it multiplies

**Severity** Low (low impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:147`

#### Description

```solidity
uint256 fee = amount / 100 * taxRate;
```

Integer division truncates, so dividing first discards the remainder before the
multiplication can use it. Any `amount` below 100 wei is taxed at exactly zero,
and every other amount is undercharged by up to `taxRate - 1` wei. For
`amount = 199` and `taxRate = 5` the correct fee is 9; this expression charges 5.

#### Impact

The shortfall is at most 9 wei per transfer on an 18-decimal token, and
extracting a meaningful sum by splitting a sell into sub-100-wei transfers costs
far more gas than the tax avoided. There is no realistic economic attack.

It is reported because the pattern is a correctness defect that becomes severe
the moment it is copied into a context with different magnitudes — a token with
fewer decimals, or a share-price calculation — and because it is free to fix.

#### Proof of concept

`test/L01_FeeRounding.t.sol`

```
forge test --match-contract L01 -vv
```

99 wei transfers untaxed; 100 wei pays 5; 199 wei pays 5 where 9 is correct.

#### Recommendation

Multiply before dividing: `amount * taxRate / 100`. The intermediate product
cannot overflow for any realistic supply under `solc 0.8`'s checked arithmetic.

#### Remediation

Fixed. Retests: `test_retest_L01_small_transfers_are_taxed_correctly` (99 wei now
pays 4) and `test_retest_L01_ordinary_amounts_are_no_longer_undercharged`
(199 wei pays 9).

---

<a id="l-02"></a>
### L-02 — `setMaxWallet(0)` freezes every non-exempt transfer

**Severity** Low (high impact, low likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:87-89`

#### Description

`setMaxWallet()` accepts any value including zero. `_transfer()` enforces
`balanceOf[to] + net <= maxWallet` for every destination other than the pair, so
`maxWallet == 0` makes each of those transfers revert.

#### Impact

Buys and wallet-to-wallet transfers stop; sells keep working because the pair is
exempt from the check. The pool can therefore only be drained. Reachable only by
owner error or a compromised key, and reversible by the owner, so the likelihood
is low — but the state is indistinguishable from a deliberate trap while it
lasts.

#### Proof of concept

`test/L02_MaxWalletZero.t.sol`

```
forge test --match-contract L02 -vv
```

#### Recommendation

Enforce a floor in the setter, expressed as a fraction of supply rather than an
absolute number so it survives changes to the token's decimals.

#### Remediation

Fixed. `MIN_MAX_WALLET_BPS = 10` (0.10% of supply) is enforced;
`setMaxWallet(0)` reverts with `MaxWalletTooLow`. Retest:
`test_retest_L02_max_wallet_has_a_floor`.

---

<a id="i-01"></a>
### I-01 — Privileged setters emit no events

**Severity** Informational · **Status** Fixed

`setTaxes`, `setBlacklist`, `setExcludedFromFee`, `setMaxWallet`,
`setSwapThreshold` and `setPair` all change state that holders depend on, and
none of them emits an event. Off-chain monitoring cannot alert on a tax change
or a blacklist entry without polling storage every block, which is exactly the
kind of change holders need to see in real time.

Fixed: `MemeTaxFixed` emits a typed event from every privileged setter and from
both ETH paths.

---

## 5. Static analysis

`forge lint` was run over `src/MemeTax.sol`. Its output is recorded here for
completeness; each item was verified by hand before being accepted or dismissed.

| Lint | Location | Outcome |
|---|---|---|
| `unchecked-call` | `_swapBack()`, both payouts | Confirmed — became M-02 |
| `arbitrary-send-eth` | `_swapBack()`, both payouts | Dismissed — the destinations are owner-configured, not caller-supplied. Kept as context for M-02. |
| `reentrancy-events` | `_transfer` / `_swapBack` | Dismissed as written, but the underlying observation led to M-01 |

The two findings the linter did not raise — H-02 (missing modifier) and H-03
(missing bound) — are both absence-of-code defects. Nothing is present to
pattern-match on, which is why the checklist pass in section 2 step 2 exists.

## 6. Notes on what this report does not cover

- No economic or MEV analysis of the swap path. The router is mocked at a fixed
  rate; slippage, sandwiching of `_swapBack()` and LP behaviour were not modelled.
- No fuzzing or invariant campaign. The PoCs are deterministic unit tests. The
  natural next step is a Foundry invariant suite asserting that the sum of
  balances equals `totalSupply` and that `sum(feesOwed) <= address(this).balance`.
- No formal verification.
- Gas optimisation was not in scope and no gas findings are reported.

## 7. Reproducing this report

```bash
git clone https://github.com/Vuduykhang2306/smart-contract-security-lab
cd smart-contract-security-lab
forge test -vv                      # 20 tests: 11 exploits, 9 retests
forge test --match-contract H01 -vvv  # one finding, with traces
```
