# Failing sequences from the negative control

Written by Echidna when `MemeTaxEchidna` — the same four properties pointed at
the unpatched `src/MemeTax.sol` — broke two of them. The control runs on a fixed
seed with one worker, so these are the sequences it produces every time.

| File | Property broken | Sequence |
|---|---|---|
| `1703917803655028910.txt` | INV-03, tax cap | `setTaxes(11, 0)` |
| `382105036653941296.txt` | INV-02, ETH obligations backed | `depositDividend` → `setMaxWallet` → `fundRouter` → `buy` → `sell` |

The second one is H-04. Nothing in the harness mentions `_swapBack()`; the
fuzzer gets there from a deposit followed by an ordinary trade, which is exactly
how a holder loses the money in production.

The one-call sequence for INV-03 is worth noticing too. `setTaxes(11, 0)` is the
smallest input that breaks the cap, and Echidna shrank to it — the sequence that
first failed used a 21-digit tax.

Reproduce:

```bash
echidna . --contract MemeTaxEchidna --config echidna.control.yaml
```

To have Echidna replay these before it starts fuzzing, drop them into the
configured `corpusDir`:

```bash
mkdir -p echidna-corpus-control/reproducers
cp test/echidna/reproducers/*.txt echidna-corpus-control/reproducers/
```
