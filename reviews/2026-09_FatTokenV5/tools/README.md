# Target selection and survey scripts

Everything used to pick the review target and to survey the template's other
deployments. Published so the review is reproducible rather than asserted.

No API key is needed for any of it.

| Script | Does |
|---|---|
| `hunt.py` | Pulls ERC-20s from Blockscout across ten memecoin keywords into `pool.json` |
| `score.py` | Scores cached sources against six tax-token markers, writes `shortlist.json` |
| `liq.sh` | Reads real Uniswap V2 WETH reserves per candidate — the step that removed two "dead" tokens still holding 12.7 and 5.4 ETH |
| `state.sh` | Dumps the specimen's live configuration: ownership, every feature flag, every fee, the pair |
| `inspect.py` | Structural scan of a cached source: owner-only functions and red-flag patterns |
| `siblings.py` | Probes every pooled address for `airdropNumbs()` and `kb()` to find other deployments of the template, then reads `owner()` on each |

`state.txt` and `siblings.json` are the outputs those last two produced for this
review, kept as the evidence behind sections 5 and 6 of the report.

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

- **Blockscout** `eth.blockscout.com/api/v2` for token lists and verified
  source. Etherscan's v2 API now requires a key; Blockscout does not.
- **Public RPC** `ethereum-rpc.publicnode.com` for all on-chain reads and for
  the `--fork-url` the proofs of concept run against.
- **Foundry** `cast` for single reads, `forge test` for the fork PoCs.

`siblings.py` batches `eth_call` over plain JSON-RPC rather than shelling out to
`cast` once per address — 485 addresses in a handful of requests instead of 485
process starts.

## A caveat worth repeating

The pool is 485 tokens from ten keyword searches. Any count derived from it is a
floor, not a census.
