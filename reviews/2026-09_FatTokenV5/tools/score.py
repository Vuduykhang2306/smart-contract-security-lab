import json, re, os, glob

pool = json.load(open("pool.json"))
byaddr = {(v.get("address_hash") or "").lower(): v for v in pool.values()}

MARK = {
    "swap":    r"swapBack|swapTokensForEth|swapAndLiquify|manualSwap|manualSend",
    "limit":   r"maxWallet|_maxWalletSize|maxTxAmount|_maxTxAmount|maxTransaction",
    "block":   r"[Bb]lacklist|isBot|_isBot|_bots\b|blackList",
    "settax":  r"function\s+(setFee|setTax|removeLimit|setTaxes|reduceFee|updateFee|excludeFrom)",
    "ethcall": r"\.call\{value:|address\(this\)\.balance",
    "owner":   r"onlyOwner",
}

out = []
for f in glob.glob("src/*.sol"):
    a = os.path.basename(f)[:-4]
    src = open(f, encoding="utf-8", errors="ignore").read()
    v = byaddr.get(a.lower(), {})
    meta = json.load(open(f + ".meta")) if os.path.exists(f + ".meta") else {}
    hits = {k: bool(re.search(p, src)) for k, p in MARK.items()}
    out.append({
        "sym": v.get("symbol") or meta.get("name") or "?",
        "name": v.get("name") or "",
        "addr": a,
        "holders": v.get("holders_count"),
        "sloc": len(src.splitlines()),
        "solc": meta.get("solc", ""),
        "hits": "".join(k[0] if hits[k] else "." for k in MARK),
        "score": sum(hits.values()),
    })

out.sort(key=lambda x: (-x["score"], x["sloc"]))
json.dump(out, open("shortlist.json", "w"), indent=1)

print("%-12s %-17s %-7s %-5s %-13s %-7s %s" % ("SYM", "NAME", "HOLDER", "SLOC", "SOLC", "MARK", "ADDR"))
for c in out:
    print("%-12s %-17s %-7s %-5s %-13s %-7s %s" % (
        str(c["sym"])[:12], str(c["name"])[:17], c["holders"], c["sloc"], c["solc"], c["hits"], c["addr"]))
print("\nMARK = swap / limit / block / settax / ethcall / owner")
