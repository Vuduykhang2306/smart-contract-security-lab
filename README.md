# Smart Contract Security Lab

A smart contract audit carried out end to end. There is a tax token with bugs
in it, a runnable proof of concept for each one, a report, a patched version of
the contract, and a retest suite that replays every exploit against the patch.

This is self-directed practice. I wrote the target myself; no third-party code
was reviewed and nothing here is a client deliverable. The point is the
workflow: threat model, manual review, PoC, report, fix, retest.

**Read first:** [`reports/2026-09_MemeTax_audit-report.md`](reports/2026-09_MemeTax_audit-report.md)

```bash
git clone https://github.com/Vuduykhang2306/smart-contract-security-lab
cd smart-contract-security-lab
forge test -vv
```

```
Ran 8 test suites: 20 tests passed, 0 failed
  11 exploits against src/MemeTax.sol
   9 retests against src/fixed/MemeTaxFixed.sol
```

## Findings

`src/MemeTax.sol` is an ERC-20 tax token in the shape meme-coin launches
actually ship: buy/sell tax swapped through a DEX from inside `_transfer`, a
max-wallet cap, a blacklist, and an ETH dividend pool.

| ID | Severity | Finding | PoC |
|---|---|---|---|
| H-01 | High | Reentrancy in `claimDividend()` drains the entire dividend pool | [`test/H01_ReentrancyClaimDividend.t.sol`](test/H01_ReentrancyClaimDividend.t.sol) |
| H-02 | High | `setBlacklist()` has no access control — anyone can freeze any holder | [`test/H02_BlacklistAccessControl.t.sol`](test/H02_BlacklistAccessControl.t.sol) |
| H-03 | High | `setTaxes()` has no upper bound — the token can become a honeypot after launch | [`test/H03_UnboundedTax.t.sol`](test/H03_UnboundedTax.t.sol) |
| M-01 | Medium | `_swapBack()` has no reentrancy lock and relies on an undocumented invariant | [`test/M01_SwapBackNoLock.t.sol`](test/M01_SwapBackNoLock.t.sol) |
| M-02 | Medium | Fee payouts ignore their return value — distribution fails silently | [`test/M02_UncheckedEthTransfer.t.sol`](test/M02_UncheckedEthTransfer.t.sol) |
| L-01 | Low | Fee arithmetic divides before it multiplies | [`test/L01_FeeRounding.t.sol`](test/L01_FeeRounding.t.sol) |
| L-02 | Low | `setMaxWallet(0)` freezes every non-exempt transfer | [`test/L02_MaxWalletZero.t.sol`](test/L02_MaxWalletZero.t.sol) |
| I-01 | Info | Privileged setters emit no events | — |

Run one finding on its own, with traces:

```bash
forge test --match-contract H01 -vvv
```

If you only read two, read **M-01** and **M-02**.

M-01 is not a bug today, which is what makes it interesting. The fee swap
re-enters `_transfer` through the router. The only thing stopping a second swap
is that the token contract happens to sit in the fee-exemption mapping, and that
mapping exists for an unrelated reason. So the contract is correct by accident.
One ordinary-looking admin call takes the guard away and every sell starts
reverting. The PoC shows both states, before and after.

M-02 is about choosing the right fix rather than the first one. My instinct was
to check the ignored return value and revert. That would have been worse: the
payout runs inside a user's sell, so a fee wallet that cannot accept ETH would
block everybody's sell. A silent accounting loss traded for a system-wide DoS.
The patch accrues fees and lets wallets pull them.

I kept a working log of the dead ends in [`docs/notes.md`](docs/notes.md),
including the two attempts at M-01 that went nowhere.

## Layout

```
src/
  MemeTax.sol              audit target - deliberately vulnerable, do not deploy
  fixed/MemeTaxFixed.sol   remediated version, each change tagged with its finding ID
  base/MinimalERC20.sol    plain ERC-20 base, out of scope
test/
  H0*/M0*/L0*.t.sol        one file per finding
  Retest_Fixed.t.sol       every exploit replayed against the fix
  attackers/, mocks/       attacker contract and a Uniswap V2 router stand-in
reports/
  2026-09_MemeTax_audit-report.md
  report-template.md
docs/
  audit-process.md         the sequence I follow on every contract
  checklist-erc20.md       per-function checklist for tax tokens
  checklist-solana-spl.md  Solana/Anchor checklist - no PoCs yet, see roadmap
  notes.md                 working log, in Vietnamese - what went wrong and why
```

## Method

Documented in full in [`docs/audit-process.md`](docs/audit-process.md). The short
version:

1. **Threat model.** For a token, two questions find most bugs: *can a holder be
   stopped from selling?* and *can value leave along a path nobody intended?*
2. **Manual review** against [`docs/checklist-erc20.md`](docs/checklist-erc20.md),
   cheapest checks first — access control, then CEI, then arithmetic, then bounds.
3. **Static analysis** (`forge lint`) as a source of leads, not conclusions. It
   caught M-02 and pointed at M-01. It could not catch H-02 or H-03: both are
   defects of absence, so there is nothing for a pattern to match on. Section 5
   of the report lists what I dismissed and why.
4. **PoC before write-up.** A finding with no failing test does not go in the
   report. Roughly half of what I suspected died at this step.
5. **Severity as `impact × likelihood`**, with centralisation risk rated by what
   it costs a holder who cannot exit, not by how trustworthy the team looks.
6. **Retest**, plus a diff check that the patch contains the agreed fixes and
   nothing else.

## Roadmap

- Foundry invariant suite: `sum(balances) == totalSupply`,
  `sum(feesOwed) <= address(this).balance`
- Echidna property tests over the same invariants
- Anchor/Solana lab backing `docs/checklist-solana-spl.md` with real PoCs
- Writeups for Ethernaut and Damn Vulnerable DeFi

## About

Vu Duy Khang — first-year Information Security student at PTIT (blockchain track),
Ho Chi Minh City. Looking for a Smart Contract Auditor internship.

- GitHub [@Vuduykhang2306](https://github.com/Vuduykhang2306)
- Email vuduykhang23062008@gmail.com

Tiếng Việt: [README.vi.md](README.vi.md)

## Licence

MIT. The contracts in `src/` are vulnerable on purpose and exist for study.
Do not deploy them.
