# Checklist: Solana SPL tokens and Anchor programs

My review checklist for Solana. Unlike `checklist-erc20.md`, nothing here has a
proof of concept in this repository yet. Building an Anchor test suite is the
next item on the roadmap in the README. Until that's done this is only a
checklist, and I've labelled it that way.

On Solana, most bugs come from the account model more than from the language.
A program receives accounts it didn't choose, and it has to check that each one
is the account it expects.

## Mint configuration

- [ ] `mint_authority` is `None`. If it's set, supply can be increased at will.
- [ ] `freeze_authority` is `None`. If it's set, any holder's token account can
      be frozen. This is the Solana version of an EVM blacklist.
- [ ] `decimals` matches what the front end and the pool assume.
- [ ] The metadata (Metaplex) update authority is revoked, or the risk of a
      rename is accepted and written down.

## Account validation

- [ ] Every account that must have signed is typed `Signer<'info>` or checked
      with `is_signer`.
- [ ] Every account is checked for the expected owner program. A
      `TokenAccount` has to be owned by the SPL Token program; looking like one
      isn't enough.
- [ ] Relationships between accounts are enforced (`has_one`, or an explicit
      `require_keys_eq!`) instead of being assumed from the instruction's
      shape.
- [ ] `UncheckedAccount` / `AccountInfo` only appears where a `/// CHECK:`
      comment explains what validates it.
- [ ] Token account `.owner` and `.mint` are checked before any transfer.

## PDAs

- [ ] PDAs are derived with the canonical bump (`ctx.bumps`), never a bump the
      user supplies.
- [ ] Seeds can't collide: variable-length seeds are length-prefixed or
      fixed-length.
- [ ] Any account used as a signing authority is a PDA of this program, and
      that is checked, not assumed.

## CPI

- [ ] The target program id of every CPI is checked against a constant. If the
      program account isn't validated, a caller can substitute their own
      program.
- [ ] Accounts passed into a CPI are validated again. Don't pass
      caller-supplied accounts straight through.
- [ ] Re-entrancy through CPI is considered wherever the program calls out and
      then reads its own state.

## Lifecycle

- [ ] `close` sends the lamports to a validated destination, and the closed
      account is zeroed. Otherwise it can be revived within the same
      transaction.
- [ ] Initialization can't run twice.
- [ ] Every account the program creates is rent-exempt.

## Arithmetic and state

- [ ] `checked_add` / `checked_mul` / `checked_div`: Rust release builds wrap
      silently unless `overflow-checks = true` is set in `Cargo.toml`. Check
      that setting.
- [ ] Multiply before dividing, same as on the EVM.
- [ ] Changes to the account data layout are versioned. A redeploy with a
      different struct layout misreads existing accounts.

## Distribution and liquidity (memecoins)

- [ ] LP tokens are burned or locked, and the lock can be verified on-chain.
- [ ] Team and treasury allocations are visible. Compare the top holders with
      the claimed distribution.
- [ ] No authority is left that can mint, freeze, or withdraw pooled liquidity
      on its own.

## Tooling

`anchor test` and `solana-test-validator` for local runs, `cargo-audit` for
dependency CVEs, and Solscan and RugCheck to look at the authorities and holder
distribution of a mint that's already deployed.
