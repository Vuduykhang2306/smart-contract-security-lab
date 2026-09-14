# Checklist — ERC-20 and tax tokens

Working checklist for the contract class in `src/MemeTax.sol`. Items marked
**[found]** are ones this repository has a live proof of concept for.

## Access control

- [ ] Every `external`/`public` state-changing function has the intended
      modifier. Enumerate them all; do not read a block of setters and assume
      consistency. **[found — H-02]**
- [ ] Ownership transfer is two-step (`pendingOwner`), or ownership sits behind
      a timelock/multisig.
- [ ] `renounceOwnership()` is either removed or understood to be irreversible —
      it disables the ability to fix bugs as well as to abuse power.
- [ ] Constructor sets every privileged address; none can be left at `address(0)`.
- [ ] No function relies on `tx.origin`.

## Economic parameters

- [ ] Every fee/tax setter enforces a hard maximum in the bytecode. **[found — H-03]**
- [ ] Wallet and transaction limits have a floor as well as a ceiling. **[found — L-02]**
- [ ] Limits are expressed as a fraction of supply, not as an absolute number
      that breaks if decimals change.
- [ ] `swapThreshold` cannot be set so high that fees never swap, or so low that
      every transfer triggers a swap.
- [ ] Trading-enabled flags are one-way: once trading is on it cannot be turned off.

## Transfer path

- [ ] Fee arithmetic multiplies before it divides. **[found — L-01]**
- [ ] Rounding direction favours the protocol, and the direction is deliberate.
- [ ] Buy, sell and wallet-to-wallet paths are all covered by tests.
- [ ] The pair address is excluded from wallet limits; the token contract is
      excluded from fees.
- [ ] Fee-exempt addresses cannot be set in a way that lets an arbitrary user
      exempt themselves.
- [ ] Transferring 0 does not revert (some integrations depend on it).
- [ ] `transferFrom` decrements the allowance, and `type(uint256).max` is
      treated as infinite consistently.

## Fee swap

- [ ] `swapBack` carries an explicit `lockTheSwap` flag, and the trigger
      condition checks it. Do not rely on the fee-exemption mapping as an
      implicit guard. **[found — M-01]**
- [ ] The swap is not triggered on buys (`from == pair`), which would let a
      buyer pay for the project's swap.
- [ ] The router allowance is set to exactly the amount being swapped, or reset
      after.
- [ ] A failing swap cannot brick transfers — wrap in `try/catch` if the router
      can revert on low liquidity.
- [ ] The swap cannot be sandwiched into a materially worse price at a size the
      project controls (`amountOutMin == 0` is a known accepted risk; say so).

## ETH handling

- [ ] Every `call{value:}` has its return value checked, or the design uses
      pull-payments. **[found — M-02]**
- [ ] Prefer accrual + `withdraw()` over pushing ETH to third parties inside a
      user transaction — a broken recipient must not be able to block users.
- [ ] Checks-Effects-Interactions on every path that sends ETH. **[found — H-01]**
- [ ] `nonReentrant` on every ETH withdrawal, even when CEI already holds.
- [ ] There is a way to recover ETH and foreign tokens sent to the contract by
      mistake, and that function cannot touch the token's own accounting.

## Blacklists and pausing

- [ ] Freeze powers are owner-only and emit events. **[found — H-02, I-01]**
- [ ] The pair itself cannot be blacklisted (that halts all trading).
- [ ] Honeypot shapes are absent: no one-way sell block, no per-address sell
      cooldown that can be set to infinity, no hidden `require(seller == owner)`.

## Observability

- [ ] Every privileged setter emits a typed event. **[found — I-01]**
- [ ] Events are emitted after the state change, with indexed addresses.
- [ ] Custom errors instead of string reverts (cheaper, and machine-readable).

## Before signing off

- [ ] Every finding has a Foundry PoC that fails on the original contract.
- [ ] Every fix has a retest that passes on the patched contract.
- [ ] The diff between original and patched contains nothing but the agreed fixes.
- [ ] Assumptions about out-of-scope dependencies are written into the report.
