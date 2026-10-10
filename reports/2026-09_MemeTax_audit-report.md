# Security Assessment: MemeTax

**Target** `src/MemeTax.sol`
**Type** ERC-20 tax token with DEX fee swap, wallet limits, blacklist and an ETH dividend pool
**Auditor** Vu Duy Khang ([github.com/Vuduykhang2306](https://github.com/Vuduykhang2306))
**Review period** September 2026
**Report version** 1.0

> This is a practice engagement I set myself. I wrote the target contract for
> this repository to reproduce the kinds of bugs that real meme-coin launches
> ship with. It is not a client deliverable and no third-party code was
> reviewed. The report follows the structure and severity conventions of
> public audit reports, so the workflow (scope, findings, proof of concept,
> remediation, retest) is the same one a real engagement uses.

---

## 1. Scope

| File | nSLOC | In scope |
|---|---:|:--:|
| `src/MemeTax.sol` | 106 | Yes |
| `src/base/MinimalERC20.sol` | 56 | No (plain ERC-20 base, read for context only) |
| `src/interfaces/IDexRouter.sol` | 11 | No (interface) |

Out of scope: the DEX router and pair implementations, which are modelled by
`test/mocks/MockDexRouter.sol`. Their behaviour is assumed to match Uniswap V2.
In particular, `swapExactTokensForETHSupportingFeeOnTransferTokens` is assumed
to pull the input tokens straight to the pair with `transferFrom`, which
re-enters the token's `_transfer`. M-01 depends on that assumption.

Compiler: `solc 0.8.24`, optimizer on, 200 runs. Arithmetic is checked by
default, and no `unchecked` block in the target does arithmetic that a user can
influence.

## 2. Methodology

1. **Threat modelling.** List the actors (deployer/owner, LP, holder, arbitrary
   caller, fee wallets, router) and what each of them should not be able to do.
   For a tax token the two main questions are "can a holder be stopped from
   selling?" and "can value leave along a path nobody intended?".
2. **Manual review**, function by function, against the checklist in
   [`docs/checklist-erc20.md`](../docs/checklist-erc20.md). Every external
   function was checked for access control, every state-changing path for
   Checks-Effects-Interactions, and every arithmetic expression for the order
   of operations.
3. **Static analysis.** `forge lint` was run over the target. Its results are in
   section 5 and were used as leads to check by hand.
4. **Proof of concept.** Each accepted finding was reproduced as a failing
   security property in Foundry before it was written up. A finding without a
   runnable PoC is reported as informational.
5. **Remediation and retest.** Fixes were made in `src/fixed/MemeTaxFixed.sol`,
   and every PoC was run again against it in `test/Retest_Fixed.t.sol`.

## 3. Severity classification

Severity is `impact x likelihood`:

| | Low likelihood | Medium likelihood | High likelihood |
|---|---|---|---|
| **High impact** | Medium | High | High |
| **Medium impact** | Low | Medium | Medium |
| **Low impact** | Low | Low | Low |

Impact is measured as loss of user funds, loss of protocol funds, or loss of
availability. Likelihood takes into account who has to act and what has to be
true first. Centralisation risks are rated by what they cost a holder who
cannot exit, not by what they mean for the deployer.

## 4. Findings

| ID | Severity | Title | Status |
|---|---|---|---|
| [H-01](#h-01) | High | Reentrancy in `claimDividend()` drains the entire dividend pool | Fixed |
| [H-02](#h-02) | High | `setBlacklist()` has no access control, so anyone can freeze any holder | Fixed |
| [H-03](#h-03) | High | `setTaxes()` has no upper bound, so the token can be turned into a honeypot after launch | Fixed |
| [H-04](#h-04) | High | `_swapBack()` pays out the whole ETH balance, sweeping the dividend pool into the fee wallets | Fixed |
| [M-01](#m-01) | Medium | `_swapBack()` has no reentrancy lock and relies on an undocumented invariant | Fixed |
| [M-02](#m-02) | Medium | Fee payouts ignore their return value, so a failed distribution goes unnoticed | Fixed |
| [L-01](#l-01) | Low | Fee arithmetic divides before it multiplies | Fixed |
| [L-02](#l-02) | Low | `setMaxWallet(0)` freezes every non-exempt transfer | Fixed |
| [I-01](#i-01) | Info | Privileged setters emit no events | Fixed |

Totals: 4 High, 2 Medium, 2 Low, 1 Informational.

H-04 was not found in the manual pass. It came up later, while writing the
invariant suite. See the finding and `test/invariant/`.

---

<a id="h-01"></a>
### H-01: Reentrancy in `claimDividend()` drains the entire dividend pool

**Severity** High (high impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:102-110`

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

The low-level `call` forwards all remaining gas, so a contract recipient can
run any code it wants in its `receive()` hook. At that point `pendingDividend`
still holds the caller's original entitlement, so calling `claimDividend()`
again passes the `require` and pays the same amount a second time. This
repeats until the contract's ETH balance is smaller than one payout.

This is a Checks-Effects-Interactions violation. There is no reentrancy guard
on this function or anywhere else in the contract.

#### Impact

Any holder who can deploy a contract can take the whole dividend pool,
including every other holder's share. The other holders are left with a
non-zero `pendingDividend` balance that no ETH backs, so their claims revert
with `ETH_TRANSFER_FAILED`. Nobody sees the loss until they try to withdraw.

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

Follow Checks-Effects-Interactions by zeroing the balance before the external
call. Also add an explicit `nonReentrant` guard, so the protection doesn't
depend on the statement order staying the same in later edits.

#### Remediation

Fixed in `src/fixed/MemeTaxFixed.sol`. The balance is cleared before the call
and `claimDividend()` has a `nonReentrant` modifier. Retest:
`test_retest_H01_reentrancy_no_longer_drains_the_pool`. The attacker receives
exactly 1 ETH, `reentries() == 0`, and Alice can still withdraw 9 ETH.

---

<a id="h-02"></a>
### H-02: `setBlacklist()` has no access control

**Severity** High (high impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:74-76`

#### Description

Every other privileged setter in the contract has `onlyOwner`.
`setBlacklist()` does not:

```solidity
function setBlacklist(address account, bool blacklisted) external {
    isBlacklisted[account] = blacklisted;
}
```

`_transfer()` reverts when either party is blacklisted, so being on the list
freezes an address's whole balance.

This is easy to miss in review because the functions around it are guarded,
and the whole block reads as if it were protected.

#### Impact

Any address can freeze any holder permanently, including the liquidity pair.
Blacklisting `pair` stops all trading. An attacker can also remove a blacklist
entry the owner set, so the owner can't use the blacklist as a defence either.
No funds move, but any holder can lose access to theirs.

#### Proof of concept

`test/H02_BlacklistAccessControl.t.sol`

```
forge test --match-contract H02 -vv
```

`mallory`, an address with no role, blacklists `alice`. Alice's transfers and
sells then revert with `BLACKLISTED`. A second test shows `mallory` removing
the blacklist entry the owner had put on its own address.

#### Recommendation

Add `onlyOwner`. More generally, don't assume a block of setters is consistent
just because it reads that way. List every `external`/`public` function that
changes state and write down who should be able to call it before checking the
modifiers.

#### Remediation

Fixed. `setBlacklist()` is `onlyOwner` and emits `BlacklistUpdated`. Retest:
`test_retest_H02_blacklist_is_owner_only`.

---

<a id="h-03"></a>
### H-03: `setTaxes()` has no upper bound

**Severity** High (high impact, medium likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:68-71`

#### Description

```solidity
function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
    buyTax = _buyTax;
    sellTax = _sellTax;
}
```

Only the owner can call the function, which is correct, but there is no
ceiling on the value. With `sellTax = 100`, `_transfer()` sends the entire
amount to the contract as fee and delivers `net == 0` to the pair.

The owner key is a single EOA. There is no timelock, no multisig and no
two-step transfer, and a change takes effect in the same block it is sent.

#### Impact

The owner can turn the token into a honeypot at any time after launch: buyers
get in at 5% and then can't get out. Many tax-token rug pulls work this way,
and from the outside it looks the same as a compromised owner key. A holder has
no on-chain guarantee that the tax they bought under is the tax they will sell
under.

This is rated High instead of being a centralisation note because the affected
party, a holder who can't exit, loses their whole position, and nothing in the
deployed bytecode limits the outcome.

#### Proof of concept

`test/H03_UnboundedTax.t.sol`

```
forge test --match-contract H03 -vv
```

After `setTaxes(0, 100)`, Alice sells 1,000 tokens. The pair receives 0 and
her balance still goes down.

#### Recommendation

Put a hard cap in the setter: a `MAX_TAX` constant checked on every write, so
the limit lives in the bytecode and not only in a policy document. Move
ownership to a timelock or multisig and publish the delay. Don't rely on
`renounceOwnership()` alone, because it removes the ability to fix a bug along
with the ability to abuse one.

#### Remediation

Fixed. `MAX_TAX = 10` is enforced on both values, and `setTaxes(0, 100)`
reverts with `TaxTooHigh(100, 10)`. Retest: `test_retest_H03_tax_is_capped`.

---

<a id="h-04"></a>
### H-04: `_swapBack()` pays out the whole ETH balance

**Severity** High (high impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:170-175`

#### Description

```solidity
uint256 half = address(this).balance / 2;

marketingWallet.call{value: half}("");
devWallet.call{value: address(this).balance}("");
```

The payout is measured against `address(this).balance` instead of what the
swap returned, so anything else the contract holds goes out with it. The
contract also holds the dividend pool, because `depositDividend()` is payable
and keeps the ETH in the same balance.

So the first sell after any dividend deposit pays the depositors' money to the
fee wallets. `pendingDividend` is never updated, so the books still say the
holders are owed that ETH.

The correct amount to pay out is the change in balance across the swap.

#### Impact

Every ETH deposited for dividends goes to the fee wallets on the next sell that
crosses the swap threshold. No attacker and no unusual ordering is needed. It
happens on the first ordinary sell. Holders keep a non-zero `pendingDividend`
balance with nothing behind it, and their claims revert with
`ETH_TRANSFER_FAILED`, the same silent failure as in H-01.

#### Proof of concept

`test/H04_SwapBackSweepsDividendPool.t.sol`

```
forge test --match-contract H04 -vv
```

10 ETH is deposited for one holder. A different holder then sells 1,000
tokens, and the swap returns 2 ETH of real fee proceeds. Each fee wallet
receives 6 ETH, 12 ETH in total, of which 10 was the dividend pool. The
contract balance ends at zero while the books still show 10 ETH owed.

#### How this was found

Not from reading the function again. It came from writing INV-02 for the
invariant suite: every ETH the contract has promised must be backed by its
balance. Once that property is written down, the next question is which paths
move the balance without updating the books, and `_swapBack` is one of them.
The manual pass had looked at `_swapBack` twice, for M-01 and M-02. Both times
the question was "is this call safe" and never "whose money is this".

#### Recommendation

Measure the swap proceeds and distribute only those:

```solidity
uint256 before = address(this).balance;
router.swapExactTokensForETHSupportingFeeOnTransferTokens(...);
uint256 received = address(this).balance - before;
```

More generally, a contract that holds ETH for several purposes needs to keep
them apart in its accounting. Any path that pays out the raw balance will
sooner or later pay out someone else's share.

#### Remediation

Already fixed by the M-02 change, which was made for a different reason.
`MemeTaxFixed._swapBack()` computes `received` as the balance difference and
credits exactly that to `feesOwed`. Confirmed by
`invariant_ethObligationsAreBacked` in
`test/invariant/MemeTaxFixed.invariant.t.sol`, which holds for the whole
campaign.

---

<a id="m-01"></a>
### M-01: `_swapBack()` has no reentrancy lock

**Severity** Medium (high impact, low likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:123-125`, `src/MemeTax.sol:156-176`

#### Description

The fee swap is triggered from inside `_transfer()`:

```solidity
if (to == pair && !isExcludedFromFee[from] && balanceOf[address(this)] >= swapThreshold) {
    _swapBack();
}
```

`_swapBack()` calls the router, and the router moves the tokens to the pair
with `transferFrom(token, pair, amountIn)`. That call re-enters `_transfer()`
with `to == pair`. The only reason it doesn't trigger a second `_swapBack()` is
the `!isExcludedFromFee[from]` term: `from` is the token contract, and the
constructor marks it as fee-exempt.

So the contract is protected, but by a mapping that exists for fee exemption.
Nothing documents that it also prevents reentrancy, and nothing enforces it.
`setExcludedFromFee(address(this), false)` looks like a normal admin call, and
it is enough to remove the guard.

This is why production tax tokens have an explicit `lockTheSwap` modifier. The
contract works today, and it would break after a change that nothing marks as
dangerous.

#### Impact

Once the token contract is no longer excluded, every sell re-enters until the
call stack runs out and the sell reverts. Buys and wallet-to-wallet transfers
still work, so the token quietly becomes one-way: holders can't sell, but
people can still buy into the pool. Fixing it needs an owner transaction. If
the owner key is lost or ownership was renounced, the token stays that way.

Likelihood is rated low because it needs a specific owner action. The
consequence itself is serious.

#### Proof of concept

`test/M01_SwapBackNoLock.t.sol`

```
forge test --match-contract M01 -vv
```

The first test shows a sell succeeding while the implicit guard is in place.
The second calls `setExcludedFromFee(address(token), false)` and shows the next
sell reverting, with Alice's balance unchanged.

#### Recommendation

Add an explicit `inSwap` flag, set by a `lockTheSwap` modifier on
`_swapBack()` and checked in the trigger condition. Keep the fee exemption as
well, but nothing should depend on it.

#### Remediation

Fixed. `MemeTaxFixed` has `bool private _inSwap`, a `lockTheSwap` modifier,
and a `!_inSwap` term in the trigger. Retest:
`test_retest_M01_swap_lock_survives_un_excluding_the_token`. The same admin
action no longer breaks sells.

---

<a id="m-02"></a>
### M-02: Fee payouts ignore their return value

**Severity** Medium (medium impact, medium likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:172-175`

#### Description

```solidity
uint256 half = address(this).balance / 2;

marketingWallet.call{value: half}("");
devWallet.call{value: address(this).balance}("");
```

A low-level `call` reports failure through its boolean return value and does
not revert. Both return values are discarded. So if a fee wallet can't accept
ETH (a multisig whose fallback needs more gas than is forwarded, a contract
wallet deployed at the address after launch, or just a wrong address), the
payout fails while the sell around it goes through normally.

`solc` raises `Warning (9302): Return value of low-level calls not used` on
both lines, and `forge lint` flags them as `unchecked-call`. Neither is an
error, so the contract still compiles and ships.

#### Impact

ETH builds up in the token contract with no event, no revert, and no
withdrawal function to get it out. Nothing on-chain shows the difference
between "fees were paid" and "fees were lost", so this can go on for many sells
before anyone notices. The loss is limited to accumulated fees and doesn't
touch user balances, which is why this is Medium and not High.

#### Proof of concept

`test/M02_UncheckedEthTransfer.t.sol`

```
forge test --match-contract M02 -vv
```

Both fee wallets are contracts without a `receive` function. The sell
succeeds, the fee tokens reach the pair, both wallets receive 0, and 2 ETH is
stuck in the token contract.

#### Recommendation

Accrue fees instead of pushing them: credit `feesOwed[wallet]` in
`_swapBack()` and let each wallet pull with a separate `withdrawFees()`. That
removes the failure mode completely. Checking the return value and reverting
would only turn it into a different problem: a broken fee wallet would block
every user's sell, and a silent accounting loss would become a denial of
service.

#### Remediation

Fixed with the pull pattern. `_swapBack()` credits `feesOwed` and emits
`FeesAccrued`. `withdrawFees()` is `nonReentrant` and reverts if the transfer
fails. Retests: `test_retest_M02_fees_are_accrued_not_pushed` and
`test_retest_M02_working_wallet_can_withdraw`.

---

<a id="l-01"></a>
### L-01: Fee arithmetic divides before it multiplies

**Severity** Low (low impact, high likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:141`

#### Description

```solidity
uint256 fee = amount / 100 * taxRate;
```

Integer division truncates, so dividing first throws away the remainder before
the multiplication can use it. Any `amount` below 100 wei pays exactly zero
tax, and every other amount is undercharged by up to `taxRate - 1` wei. For
`amount = 199` and `taxRate = 5` the correct fee is 9, but this expression
charges 5.

#### Impact

The shortfall is at most 9 wei per transfer on an 18-decimal token. Splitting
a sell into transfers under 100 wei to avoid a meaningful amount of tax costs
far more gas than it saves, so there is no realistic economic attack.

It is still reported because the same expression becomes a real problem once
it's copied somewhere with different magnitudes, like a token with fewer
decimals or a share-price calculation, and because it costs nothing to fix.

#### Proof of concept

`test/L01_FeeRounding.t.sol`

```
forge test --match-contract L01 -vv
```

99 wei transfers untaxed; 100 wei pays 5; 199 wei pays 5 where 9 is correct.

#### Recommendation

Multiply before dividing: `amount * taxRate / 100`. Under `solc 0.8`'s checked
arithmetic, the intermediate product can't overflow for any realistic supply.

#### Remediation

Fixed. Retests: `test_retest_L01_small_transfers_are_taxed_correctly` (99 wei
now pays 4) and `test_retest_L01_ordinary_amounts_are_no_longer_undercharged`
(199 wei pays 9).

---

<a id="l-02"></a>
### L-02: `setMaxWallet(0)` freezes every non-exempt transfer

**Severity** Low (high impact, low likelihood) · **Status** Fixed
**Location** `src/MemeTax.sol:83-85`

#### Description

`setMaxWallet()` accepts any value, including zero. `_transfer()` enforces
`balanceOf[to] + net <= maxWallet` for every destination except the pair, so
with `maxWallet == 0` each of those transfers reverts.

#### Impact

Buys and wallet-to-wallet transfers stop. Sells keep working because the pair
is exempt from the check, so the pool can only be drained. This can only
happen through an owner mistake or a compromised key, and the owner can undo
it, so likelihood is low. While it lasts, though, it looks exactly like a
deliberate trap.

#### Proof of concept

`test/L02_MaxWalletZero.t.sol`

```
forge test --match-contract L02 -vv
```

#### Recommendation

Enforce a floor in the setter. Express it as a fraction of supply instead of
an absolute number, so it still works if the token's decimals change.

#### Remediation

Fixed. `MIN_MAX_WALLET_BPS = 10` (0.10% of supply) is enforced, and
`setMaxWallet(0)` reverts with `MaxWalletTooLow`. Retest:
`test_retest_L02_max_wallet_has_a_floor`.

---

<a id="i-01"></a>
### I-01: Privileged setters emit no events

**Severity** Informational · **Status** Fixed

`setTaxes`, `setBlacklist`, `setExcludedFromFee`, `setMaxWallet`,
`setSwapThreshold` and `setPair` all change state that holders rely on, and
none of them emits an event. Off-chain monitoring can't alert on a tax change
or a new blacklist entry without polling storage every block, and those are
exactly the changes holders need to see quickly.

Fixed: `MemeTaxFixed` emits a typed event from every privileged setter and from
both ETH paths.

---

## 5. Static analysis

`forge lint` (Foundry 1.8.5, as run in CI) reports 11 warnings on
`src/MemeTax.sol`. All of them are listed here with the finding each one
corresponds to.

| Lint | Location | Outcome |
|---|---|---|
| `reentrancy-eth` | `claimDividend()`, line 106 | Matches H-01 |
| `unchecked-call` (x2) | `_swapBack()`, lines 174-175 | Confirmed, became M-02 |
| `arbitrary-send-eth` (x2) | `_swapBack()`, lines 174-175 | Dismissed: the destinations are set by the owner, not supplied by the caller. Kept as context for M-02. |
| `divide-before-multiply` | `_transfer()`, line 141 | Matches L-01 |
| `missing-events-arithmetic` | `setTaxes()`, line 70 | Part of I-01 |
| `uninitialized-local` | `_transfer()`, line 141 (`taxRate`) | Dismissed: `taxRate` stays 0 when a transfer is neither a buy nor a sell, which is the intended untaxed path. `MemeTaxFixed` keeps the same pattern. |
| `missing-zero-check` (x2) | constructor `_marketingWallet` and `_devWallet` (line 40) | Not triaged in version 1.0 |
| `missing-zero-check` | `setPair()`, line 62 | Reproduced, not yet rated (see below) |

The linter does not raise H-02, H-03, H-04, M-01 or L-02. H-02 (missing
modifier) and H-03 (missing bound) are defects of absence: there is nothing in
the code to pattern-match on, which is why the checklist pass in section 2
step 2 exists. The warnings on lines 174-175 are about the return values and
the destinations, not about how much is paid out, so they don't point at H-04
either.

The `setPair()` warning points at a real problem. `pair` starts as address(0)
and, in `MemeTax`, can be set back to it. While it is zero, a sell into the
real pool goes through the max-wallet check as if the pool were a holder.
The pool holds far more than `maxWallet`, so every sell reverts while buys
keep working. `MemeTaxFixed` rejects zero in `setPair()`, but it still starts
with `pair` unset, so the same thing happens between deployment and the first
`setPair()` call. Proof of concept: `test/triage/Triage_SetPair.t.sol`
(4 tests). It is not rated or numbered in this version of the report.

## 6. Notes on what this report does not cover

- No economic or MEV analysis of the swap path. The router is mocked at a fixed
  rate, and slippage, sandwiching of `_swapBack()` and LP behaviour were not
  modelled.
- A Foundry invariant campaign was added after the first version of this
  report (`test/invariant/`, four properties over the remediated contract).
  That is what produced H-04. The same four properties were later run under
  Echidna (`test/echidna/`), together with a negative control against the
  unpatched contract. Echidna found nothing the Foundry campaign had missed.
- No formal verification.
- Gas optimisation was out of scope and no gas findings are reported.

## 7. Reproducing this report

```bash
git clone https://github.com/Vuduykhang2306/smart-contract-security-lab
cd smart-contract-security-lab
forge test -vv                      # 27 tests: 13 exploits, 9 retests, 1 invariant campaign, 4 triage
forge test --match-contract H01 -vvv  # one finding, with traces
```
