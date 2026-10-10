# Checklist: ERC-20 and tax tokens

The checklist I use for the kind of contract in `src/MemeTax.sol`. Items marked
[found] have a working proof of concept in this repository.

## Access control

- [ ] Every `external`/`public` function that changes state has the intended
      modifier. List them all. Don't read a block of setters and assume they
      are consistent. [found: H-02]
- [ ] Ownership transfer is two-step (`pendingOwner`), or ownership sits behind
      a timelock/multisig.
- [ ] `renounceOwnership()` is either removed or understood to be
      irreversible. It removes the ability to fix bugs along with the ability
      to abuse power.
- [ ] The constructor sets every privileged address, and none can be left at
      `address(0)`.
- [ ] No function relies on `tx.origin`.

## Economic parameters

- [ ] Every fee/tax setter enforces a hard maximum in the bytecode. [found: H-03]
- [ ] Wallet and transaction limits have a floor as well as a ceiling. [found: L-02]
- [ ] Limits are a fraction of supply, not an absolute number that breaks if
      decimals change.
- [ ] `swapThreshold` can't be set so high that fees never swap, or so low that
      every transfer triggers a swap.
- [ ] Trading-enabled flags are one-way: once trading is on, it can't be turned
      off.

## Transfer path

- [ ] Fee arithmetic multiplies before it divides. [found: L-01]
- [ ] Rounding favours the protocol, and that's a deliberate choice.
- [ ] Tests cover buy, sell and wallet-to-wallet transfers.
- [ ] The pair address is excluded from wallet limits, and the token contract
      is excluded from fees.
- [ ] Fee exemptions can't be set in a way that lets an arbitrary user exempt
      themselves.
- [ ] Transferring 0 doesn't revert (some integrations depend on it).
- [ ] `transferFrom` decrements the allowance, and `type(uint256).max` is
      treated as infinite everywhere.

## Fee swap

- [ ] `swapBack` has an explicit `lockTheSwap` flag, and the trigger condition
      checks it. Don't rely on the fee-exemption mapping as a hidden guard.
      [found: M-01]
- [ ] The swap isn't triggered on buys (`from == pair`), which would make a
      buyer pay for the project's swap.
- [ ] The router allowance is set to exactly the amount being swapped, or reset
      afterwards.
- [ ] A failing swap can't brick transfers. Wrap it in `try/catch` if the
      router can revert on low liquidity.
- [ ] The swap can't be sandwiched into a much worse price at a size the
      project controls (`amountOutMin == 0` is a known, accepted risk; say so
      in the report).

## ETH handling

- [ ] Every `call{value:}` has its return value checked, or the design uses
      pull payments. [found: M-02]
- [ ] Prefer accrual + `withdraw()` over pushing ETH to third parties inside a
      user's transaction. A broken recipient must not be able to block users.
- [ ] Checks-Effects-Interactions on every path that sends ETH. [found: H-01]
- [ ] `nonReentrant` on every ETH withdrawal, even when CEI already holds.
- [ ] There is a way to recover ETH and other tokens sent to the contract by
      mistake, and that function can't touch the token's own accounting.

## Blacklists and pausing

- [ ] Freeze powers are owner-only and emit events. [found: H-02, I-01]
- [ ] The pair itself can't be blacklisted (that would stop all trading).
- [ ] No honeypot shapes: no one-way sell block, no per-address sell cooldown
      that can be set to infinity, no hidden `require(seller == owner)`.

## Observability

- [ ] Every privileged setter emits a typed event. [found: I-01]
- [ ] Events are emitted after the state change, with indexed addresses.
- [ ] Custom errors instead of string reverts (cheaper, and easier for tools to
      parse).

## Before signing off

- [ ] Every finding has a Foundry PoC that fails on the original contract.
- [ ] Every fix has a retest that passes on the patched contract.
- [ ] The diff between original and patched has nothing but the agreed fixes.
- [ ] Assumptions about out-of-scope dependencies are written into the report.
