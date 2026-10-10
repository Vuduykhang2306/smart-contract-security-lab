# Smart Contract Security Lab

[![CI](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml)

One smart contract audit, done start to finish. There's a tax token with bugs
in it, a runnable proof of concept for each bug, a report, a patched version of
the contract, and a retest suite that runs every exploit again against the
patch.

This is practice I set myself. I wrote the target contract, so no third-party
code was reviewed and nothing here was delivered to a client. What I wanted to
practise is the workflow: threat model, manual review, PoC, report, fix,
retest.

Start with the report: [`reports/2026-09_MemeTax_audit-report.md`](reports/2026-09_MemeTax_audit-report.md)

```bash
git clone https://github.com/Vuduykhang2306/smart-contract-security-lab
cd smart-contract-security-lab
forge test -vv
```

```
Ran 11 test suites: 27 tests passed, 0 failed
  13 exploits against src/MemeTax.sol
   9 retests against src/fixed/MemeTaxFixed.sol
   1 invariant campaign over the remediated contract (4 properties)
   4 triage tests for the setPair lint (not a numbered finding yet)
```

The same four properties also run under [Echidna](test/echidna/). There's also
a negative control that runs them against the unpatched contract, where they
have to fail.

## Findings

`src/MemeTax.sol` is an ERC-20 tax token built the way meme-coin launches
usually are: buy/sell tax swapped through a DEX from inside `_transfer`, a
max-wallet cap, a blacklist, and an ETH dividend pool.

| ID | Severity | Finding | PoC |
|---|---|---|---|
| H-01 | High | Reentrancy in `claimDividend()` drains the entire dividend pool | [`test/H01_ReentrancyClaimDividend.t.sol`](test/H01_ReentrancyClaimDividend.t.sol) |
| H-02 | High | `setBlacklist()` has no access control, so anyone can freeze any holder | [`test/H02_BlacklistAccessControl.t.sol`](test/H02_BlacklistAccessControl.t.sol) |
| H-03 | High | `setTaxes()` has no upper bound, so the token can become a honeypot after launch | [`test/H03_UnboundedTax.t.sol`](test/H03_UnboundedTax.t.sol) |
| H-04 | High | `_swapBack()` pays out the whole ETH balance, dividend pool included | [`test/H04_SwapBackSweepsDividendPool.t.sol`](test/H04_SwapBackSweepsDividendPool.t.sol) |
| M-01 | Medium | `_swapBack()` has no reentrancy lock and relies on an undocumented invariant | [`test/M01_SwapBackNoLock.t.sol`](test/M01_SwapBackNoLock.t.sol) |
| M-02 | Medium | Fee payouts ignore their return value, so a failed payout goes unnoticed | [`test/M02_UncheckedEthTransfer.t.sol`](test/M02_UncheckedEthTransfer.t.sol) |
| L-01 | Low | Fee arithmetic divides before it multiplies | [`test/L01_FeeRounding.t.sol`](test/L01_FeeRounding.t.sol) |
| L-02 | Low | `setMaxWallet(0)` freezes every non-exempt transfer | [`test/L02_MaxWalletZero.t.sol`](test/L02_MaxWalletZero.t.sol) |
| I-01 | Info | Privileged setters emit no events | none |

Run one finding on its own, with traces:

```bash
forge test --match-contract H01 -vvv
```

If you only read two findings, read M-01 and M-02.

M-01 isn't a bug today, and that's why I find it interesting. The fee swap
re-enters `_transfer` through the router. The only thing that stops a second
swap is that the token contract is in the fee-exemption mapping, and that
mapping is there for a different reason. So the contract works by accident.
One normal-looking admin call removes the guard, and after that every sell
reverts. The PoC shows the state before and after.

M-02 is about picking the right fix instead of the first one. My first idea was
to check the return value and revert. That would have been worse. The payout
runs inside a user's sell, so a fee wallet that can't accept ETH would block
everyone's sells. I'd have swapped a silent accounting loss for a DoS on the
whole token. The patch records the fees owed and lets each wallet withdraw
them.

H-04 is the one I'm least happy about. My manual pass missed it. It only came
up when I wrote the invariant suite and had to write down, as a property, that
every ETH the contract has promised must be covered by its balance.
`_swapBack()` pays out `address(this).balance`, and the dividend pool is in
that same balance. So the first ordinary sell after a deposit sends someone
else's money to the fee wallets. I had already read that function twice, for
M-01 and M-02. Both times I asked whether the call was safe. I never asked
whose money it was sending.

My working log, including the dead ends and the two attempts at M-01 that went
nowhere, is in [`docs/notes.md`](docs/notes.md) (in Vietnamese).

## Two fuzzers, and a control

The four properties in [`test/invariant/`](test/invariant/) run under Foundry
and again under Echidna in [`test/echidna/`](test/echidna/). Both pass. Neither
found anything the other missed, and I've left that result as it is.

The useful part came from the second engine. A passing fuzz run can mean the
code holds, or it can mean the harness never reached the code that breaks, and
the output looks the same in both cases. So I point the same property file at
`src/MemeTax.sol`, which I know is broken, and it has to fail:

```
echidna_supplyIsConserved:       passing
echidna_maxWalletHasFloor:       passing
echidna_ethObligationsAreBacked: FAILED   <- H-04, in five calls
echidna_taxNeverExceedsCap:      FAILED   <- H-03, in one
```

CI fails if either of those two ever starts passing. The harness never
mentions `_swapBack()`. The fuzzer gets to H-04 from a dividend deposit
followed by an ordinary trade.

## Public review

[`reviews/2026-09_FatTokenV5/`](reviews/2026-09_FatTokenV5/) is a review nobody
asked me for, of a launchpad token template, using a dead mainnet token as the
example. 8 findings (2 High, 2 Medium, 3 Low, 1 Info), 7 PoCs on a mainnet fork,
and an on-chain check of how many deployments of the template still have a
live owner.

The main result: the template decides every dangerous power in its
constructor, and there's no way to switch any of them back on later. So a buyer
can read five values on-chain and know for good what they're exposed to.
Section 6 of the review has the five commands.

## Layout

```
src/
  MemeTax.sol              audit target - deliberately vulnerable, do not deploy
  fixed/MemeTaxFixed.sol   remediated version, each change tagged with its finding ID
  base/MinimalERC20.sol    plain ERC-20 base, out of scope
test/
  H0*/M0*/L0*.t.sol        one file per finding
  Retest_Fixed.t.sol       every exploit replayed against the fix
  invariant/               4 properties over the remediated contract
  echidna/                 the same 4 under Echidna, plus the negative control
  triage/                  PoCs for lint warnings that aren't numbered findings yet
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

The full version is in [`docs/audit-process.md`](docs/audit-process.md). In
short:

1. Threat model. For a token, two questions find most bugs: can a holder be
   stopped from selling, and can value leave along a path nobody intended?
2. Manual review against [`docs/checklist-erc20.md`](docs/checklist-erc20.md),
   cheapest checks first: access control, then CEI, then arithmetic, then
   bounds.
3. Static analysis (`forge lint`) for leads. I don't treat its output as
   findings. In CI it flags the lines behind H-01, M-02 and L-01. It can't
   catch H-02 or H-03, because both are missing code and there's nothing for a
   pattern to match. Section 5 of the report lists every warning and what it
   corresponds to.
4. PoC before write-up. A finding without a failing test doesn't go in the
   report. About half of what I suspected was dropped at this step.
5. Severity is impact × likelihood. Centralisation risk is rated by what it
   costs a holder who can't exit, not by how trustworthy the team looks.
6. Retest, and check the diff to make sure the patch has the agreed fixes and
   nothing else.

## Roadmap

Tracked as issues, in the order I plan to do them.

- ~~[#1](../../issues/1) Foundry invariant suite~~ done, and it found H-04
- ~~[#2](../../issues/2) Echidna property tests over the same invariants~~ done, see the negative control above
- [#3](../../issues/3) Anchor lab to put real PoCs behind the Solana checklist
- [#4](../../issues/4) Ethernaut and Damn Vulnerable DeFi writeups

## About

Vu Duy Khang, first-year Information Security student at PTIT (blockchain
track), Ho Chi Minh City. Looking for a smart contract auditor internship.

- GitHub [@Vuduykhang2306](https://github.com/Vuduykhang2306)
- Email vuduykhang23062008@gmail.com

Tiếng Việt: [README.vi.md](README.vi.md)

## Licence

MIT. The contracts in `src/` are vulnerable on purpose and are only here to
study. Do not deploy them.
