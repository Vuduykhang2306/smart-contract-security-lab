# Echidna campaign

The four properties from [`test/invariant/`](../invariant/) restated for a
second fuzzer, plus a negative control that proves the properties can actually
fail.

```bash
# needs echidna >= 2.3 and crytic-compile on PATH
echidna . --contract MemeTaxFixedEchidna --config echidna.yaml          # expect 4 passing
echidna . --contract MemeTaxEchidna      --config echidna.control.yaml  # expect 2 failing
```

## Why run a second tool over the same properties

Foundry and Echidna both fuzz call sequences, and they choose those sequences
differently. Foundry draws each call from a handler and reruns whole sequences
from scratch. Echidna keeps a corpus: a sequence that reaches new code is saved
and mutated, so it builds on what worked. Neither strictly dominates, so a
property that survives both is better tested than one that survived either.

The honest result here is that **they agree**. All four properties pass under
both engines, and neither found anything the other missed. That is a negative
result and it is written down as one. What the exercise did produce is the
control below, which is the part worth keeping.

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

`MemeTaxEchidna` against the unpatched `src/MemeTax.sol`, same properties, same
action set, same bounds, 20,000 calls on a fixed seed:

```
echidna_supplyIsConserved:       passing
echidna_maxWalletHasFloor:       passing
echidna_ethObligationsAreBacked: FAILED   <- H-04
echidna_taxNeverExceedsCap:      FAILED   <- H-03
```

Failing sequences are kept in [`reproducers/`](reproducers/).

## The control is the point

A fuzzing run that comes back green tells you one of two things: the code holds,
or the harness never reached it. The two are indistinguishable from the output.
So the same file is pointed at the contract that is known to be broken, and the
run has to go red. It does, on the two findings those properties describe.

INV-02 failing on the unpatched contract is H-04, the finding the manual review
missed. Echidna reaches it in five calls without being told anything about
`_swapBack()`.

INV-04 passes on both, which is not a hole in the control but a limit of it
stated plainly: `setMaxWallet` is bounded by the harness to at least 1% of
supply, because a campaign that keeps freezing every transfer stops exploring.
The floor itself is covered by
[`Retest_Fixed.test_retest_L02_max_wallet_has_a_floor`](../Retest_Fixed.t.sol).

## Checking coverage rather than trusting it

Echidna prints no call summary, so the Foundry harness's `callSummary()` has no
equivalent. Coverage is read off `echidna-corpus/covered.*.txt` instead, where
an executed line is marked `*`:

```bash
grep -E 'feesOwed\[|received = |revert TaxTooHigh' echidna-corpus/covered.*.txt
```

All ten actions and every ETH path in the remediated contract are marked
executed for the run above — the fee accrual in `_swapBack`, both withdrawal
paths, and the two reverts the caps live in.

## Differences from the Foundry harness, and why

Echidna has no cheatcodes, which forces three changes. They are marked in the
source where they occur.

1. **No `vm.prank`.** The harness deploys the token, so it is the owner and
   holds the supply. Every other participant is a [`Puppet`](Puppet.sol) the
   harness forwards calls through, which is what puts somebody else in
   `msg.sender`.
2. **No `vm.deal`.** ETH comes from the harness's own starting balance, set by
   `balanceContract` in the config, and the constructor is `payable` because
   Echidna delivers that balance with the deployment transaction. Funding the
   router became a fuzzed action instead of setup.
3. **No `bound`.** `StdUtils` is forge-std, so the harness has its own modulo
   version. It skews towards the low end of a wide range; every call site uses a
   range narrow enough for that not to matter.

One configuration note that cost some time: `crytic-compile` skips `test/` when
it drives Foundry, so `cryticArgs: ["--foundry-compile-all"]` is required or
Echidna reports the harness as not found.
