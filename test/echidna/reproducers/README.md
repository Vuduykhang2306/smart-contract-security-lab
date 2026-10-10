# Failing sequences from the negative control

Echidna wrote these when `MemeTaxEchidna` (the same four properties, run
against the unpatched `src/MemeTax.sol`) broke two of them. The control runs on
a fixed seed with one worker, so it produces these sequences every time.

| File | Property broken | Sequence |
|---|---|---|
| `1703917803655028910.txt` | INV-03, tax cap | `setTaxes(11, 0)` |
| `382105036653941296.txt` | INV-02, ETH obligations backed | `depositDividend` -> `setMaxWallet` -> `fundRouter` -> `buy` -> `sell` |

The second one is H-04. The harness never mentions `_swapBack()`. The fuzzer
gets there from a deposit followed by an ordinary trade, which is also how a
holder would lose the money in production.

The INV-03 sequence is a single call. `setTaxes(11, 0)` is the smallest input
that breaks the cap, and Echidna shrank the failure down to it. The sequence
that failed first used a 21-digit tax.

Reproduce:

```bash
echidna . --contract MemeTaxEchidna --config echidna.control.yaml
```

To have Echidna replay these before it starts fuzzing, put them in the
configured `corpusDir`:

```bash
mkdir -p echidna-corpus-control/reproducers
cp test/echidna/reproducers/*.txt echidna-corpus-control/reproducers/
```
