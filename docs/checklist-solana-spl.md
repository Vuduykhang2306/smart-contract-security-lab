# Checklist — Solana SPL tokens and Anchor programs

Review checklist for the Solana side. Unlike `checklist-erc20.md` this one is
not yet backed by proofs of concept in this repository — building an Anchor test
suite is the next thing on the roadmap in the README. It is published as a
checklist, and labelled as one, rather than dressed up as work that has been done.

The account model, not the language, is where Solana bugs come from: a program
receives accounts it did not choose and must prove each one is the account it
expects.

## Mint configuration

- [ ] `mint_authority` is `None`. If it is set, supply can be increased at will.
- [ ] `freeze_authority` is `None`. If it is set, any holder's token account can
      be frozen — the Solana equivalent of an EVM blacklist.
- [ ] `decimals` matches what the front end and the pool assume.
- [ ] Metadata (Metaplex) update authority is revoked, or the risk of a rename
      is accepted and documented.

## Account validation

- [ ] Every account that must have signed is typed `Signer<'info>` or checked
      with `is_signer`.
- [ ] Every account is checked for the expected **owner program** — a
      `TokenAccount` must be owned by the SPL Token program, not merely look
      like one.
- [ ] Relationships between accounts are enforced (`has_one`, or an explicit
      `require_keys_eq!`) instead of being assumed from the instruction's shape.
- [ ] `UncheckedAccount` / `AccountInfo` appears only where a `/// CHECK:`
      comment explains what validates it.
- [ ] Token account `.owner` and `.mint` are verified before any transfer.

## PDAs

- [ ] PDAs are derived with the canonical bump (`ctx.bumps`), never a
      user-supplied bump.
- [ ] Seeds cannot collide: variable-length seeds are length-prefixed or fixed.
- [ ] Any account used as a signing authority is a PDA of this program, and that
      is checked rather than assumed.

## CPI

- [ ] The target program id of every CPI is verified against a constant. An
      unvalidated program account lets a caller substitute their own program.
- [ ] Accounts forwarded into a CPI are re-validated; do not pass caller-supplied
      accounts straight through.
- [ ] Re-entrancy through CPI is considered where the program calls out and then
      reads its own state.

## Lifecycle

- [ ] `close` returns lamports to a validated destination, and the closed account
      is zeroed — otherwise it can be revived within the same transaction.
- [ ] Initialization is guarded against being run twice.
- [ ] Rent-exemption is ensured for every account the program creates.

## Arithmetic and state

- [ ] `checked_add` / `checked_mul` / `checked_div` — Rust release builds wrap
      silently unless `overflow-checks = true` is set in `Cargo.toml`. Verify
      that setting.
- [ ] Multiplication before division, as on the EVM.
- [ ] Account data layout changes are versioned; a redeploy over a different
      struct layout misreads existing accounts.

## Distribution and liquidity (memecoin-specific)

- [ ] LP tokens are burned or locked, and the lock is verifiable on-chain.
- [ ] Team and treasury allocations are visible; check the top holders against
      the claimed distribution.
- [ ] No authority remains that can mint, freeze, or unilaterally withdraw
      pooled liquidity.

## Tooling

`anchor test`, `solana-test-validator` for local runs; `cargo-audit` for
dependency CVEs; Solscan and RugCheck for reviewing an already-deployed mint's
authorities and holder distribution.
