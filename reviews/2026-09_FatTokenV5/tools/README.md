# Target selection and survey scripts

Everything I used to pick the review target and to find the template's other
deployments. It's published so anyone can reproduce the review.

No API key is needed for any of it.

| Script | What it does |
|---|---|
| `hunt.py` | Pulls ERC-20s from Blockscout across ten memecoin keywords into `pool.json` |
| `score.py` | Scores cached sources against six tax-token markers, writes `shortlist.json` |
| `liq.sh` | Reads the real Uniswap V2 WETH reserves for each candidate. This is the step that removed two "dead" tokens still holding 12.7 and 5.4 ETH |
| `state.sh` | Dumps the specimen's live configuration: ownership, every feature flag, every fee, the pair |
| `inspect.py` | Structural scan of a cached source: owner-only functions and red-flag patterns |
| `siblings.py` | Probes every address in the pool for `airdropNumbs()` and `kb()` to find other deployments of the template, then reads `owner()` on each |

`state.txt` (from `state.sh`) and `siblings.json` (from `siblings.py`) are the
outputs from this review. They're kept as the evidence behind sections 5 and 6
of the report.

## Running

```bash
export PATH="$PATH:$HOME/.foundry/bin"
python3 hunt.py                 # -> pool.json
python3 score.py                # needs src/<address>.sol cached alongside
./liq.sh < cands.txt            # lines of "SYMBOL 0xaddress"
./state.sh                      # specimen configuration
python3 siblings.py             # -> siblings.json
```

## Data sources

- Blockscout (`eth.blockscout.com/api/v2`) for token lists and verified source.
  Etherscan's v2 API now needs a key; Blockscout doesn't.
- Public RPC (`ethereum-rpc.publicnode.com`) for all on-chain reads, and as the
  `--fork-url` the proofs of concept run against.
- Foundry: `cast` for single reads, `forge test` for the fork PoCs.

`siblings.py` batches `eth_call` over plain JSON-RPC instead of running `cast`
once per address. That's 485 addresses in a handful of requests instead of 485
process starts.

## Caveat

The pool is 485 tokens from ten keyword searches. Any count taken from it is
only a lower bound.
