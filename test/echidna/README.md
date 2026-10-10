# Echidna campaign

The four properties from [`test/invariant/`](../invariant/), rewritten for a
second fuzzer, plus a negative control that shows the properties can actually
fail.

```bash
# needs echidna >= 2.3 and crytic-compile on PATH
echidna . --contract MemeTaxFixedEchidna --config echidna.yaml          # expect 4 passing
echidna . --contract MemeTaxEchidna      --config echidna.control.yaml  # expect 2 failing
```

## Why run a second tool over the same properties

Foundry and Echidna both fuzz sequences of calls, but they pick those
sequences differently. Foundry draws each call from a handler and reruns whole
sequences from scratch. Echidna keeps a corpus: a sequence that reaches new
code is saved and mutated, so it builds on what worked before. Neither one is
strictly better, so a property that survives both has been tested more than
one that survived only one of them.

The result here is that they agree. All four properties pass under both
engines, and neither found anything the other missed. What did turn out to be
useful is the control below.

## Results

`MemeTaxFixedEchidna` against `src/fixed/MemeTaxFixed.sol`, 50,000 calls,
sequences of 100, four workers, seed `3808471894293323190`:

```
echidna_supplyIsConserved:       passing
echidna_ethObligationsAreBacked: passing
echidna_taxNeverExceedsCap:      passing
echidna_maxWalletHasFloor:       passing

Unique instructions: 7779    Corpus size: 19    Total calls: 50251
```

`MemeTaxEchidna` against the unpatched `src/MemeTax.sol`, with the same
properties, the same action set and the same bounds, 20,000 calls on a fixed
seed:

```
echidna_supplyIsConserved:       passing
echidna_maxWalletHasFloor:       passing
echidna_ethObligationsAreBacked: FAILED   <- H-04
echidna_taxNeverExceedsCap:      FAILED   <- H-03
```

The failing sequences are kept in [`reproducers/`](reproducers/).

## Why the control matters

A passing fuzz run tells you one of two things: the code holds, or the harness
never reached it. You can't tell which from the output. So the same file is
pointed at the contract that's known to be broken, and the run has to fail. It
does, on the two findings those properties describe.

INV-02 failing on the unpatched contract is H-04, the finding the manual review
missed. Echidna reaches it in five calls without being told anything about
`_swapBack()`.

INV-04 passes on both, and that's a limit of the control. The harness bounds
`setMaxWallet` to at least 1% of supply, because a campaign that keeps freezing
every transfer stops exploring. The floor itself is covered by
[`Retest_Fixed.test_retest_L02_max_wallet_has_a_floor`](../Retest_Fixed.t.sol).

## Checking coverage instead of trusting it

Echidna doesn't print a call summary, so there's no equivalent of the Foundry
harness's `callSummary()`. I read coverage from `echidna-corpus/covered.*.txt`
instead, where executed lines are marked with `*`:

```bash
grep -E 'feesOwed\[|received = |revert TaxTooHigh' echidna-corpus/covered.*.txt
```

For the run above, all ten actions and every ETH path in the remediated
contract are marked as executed: the fee accrual in `_swapBack`, both
withdrawal paths, and the two reverts where the caps are enforced.

## Differences from the Foundry harness

Echidna has no cheatcodes, which forced three changes. Each one is marked in
the source where it happens.

1. No `vm.prank`. The harness deploys the token, so it is the owner and holds
   the supply. Every other participant is a [`Puppet`](Puppet.sol) that the
   harness forwards calls through, which is how someone else ends up as
   `msg.sender`.
2. No `vm.deal`. ETH comes from the harness's own starting balance, set by
   `balanceContract` in the config. The constructor is `payable` because
   Echidna sends that balance with the deployment transaction. Funding the
   router became a fuzzed action instead of part of the setup.
3. No `bound`. `StdUtils` is part of forge-std, so the harness has its own
   modulo version. It leans towards the low end of a wide range, but every call
   site uses a range narrow enough that this doesn't matter.

One config detail that cost me some time: `crytic-compile` skips `test/` when
it builds a Foundry project, so you need `cryticArgs: ["--foundry-compile-all"]`
or Echidna reports the harness as not found.
