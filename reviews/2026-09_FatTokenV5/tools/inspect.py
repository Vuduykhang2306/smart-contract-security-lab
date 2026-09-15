import re, sys, json, os

CANDS = [
    ("Shibmerican", "0x440238CC07186aDEA6653a2E8cb9a24737615609"),
    ("BABYSAITAMA", "0xf79F9020560963422eCC9C0c04D3a21190BBf045"),
    ("BHIBA",       "0x4A6Be56a211a4c4E0dd4474D524138933c17f3e3"),
    ("BabyGOAT",    "0x26d86F942D514B470Ba5dF311027a870110F6699"),
]

RED = {
    "mint sau deploy":      r"function\s+mint\s*\(",
    "doi owner":            r"function\s+transferOwnership|renounceOwnership",
    "blacklist":            r"[Bb]lacklist|blackList|_isBot|isBot",
    "set thue khong tran":  r"function\s+(setFee|setTaxes|setFees|updateFee|setTax)\w*\s*\(",
    "gioi han vi/giao dich": r"maxWallet|_maxWalletSize|maxTxAmount|_maxTxAmount",
    "rut ETH/token ra":     r"function\s+(rescue|withdraw|clearStuck|manualSend|sweep|emergency)\w*\s*\(",
    "goi router trong transfer": r"swapTokensForEth|swapAndLiquify|swapBack",
    "call{value:}":         r"\.call\{\s*value:",
    "transfer\\(\\) 2300 gas": r"\.transfer\(\s*address\(this\)\.balance",
    "SafeMath":             r"using SafeMath",
    "khoa swap (lockTheSwap)": r"lockTheSwap|inSwap|swapping",
}

for sym, addr in CANDS:
    f = "src/%s.sol" % addr
    if not os.path.exists(f):
        print("%s: chua cache source" % sym); continue
    src = open(f, encoding="utf-8", errors="ignore").read()
    meta = json.load(open(f + ".meta")) if os.path.exists(f + ".meta") else {}
    ext = re.findall(r"function\s+(\w+)\s*\([^)]*\)\s*(?:public|external)", src)
    owner_only = re.findall(r"function\s+(\w+)\s*\([^)]*\)[^{]*onlyOwner", src)
    print("\n=== %s  %s" % (sym, addr))
    print("  solc %s | %d dong | %d ham public/external | %d ham onlyOwner"
          % (meta.get("solc", "?"), len(src.splitlines()), len(set(ext)), len(set(owner_only))))
    print("  quyen cua owner: %s" % (", ".join(sorted(set(owner_only))[:9]) or "khong co"))
    found = [k for k, p in RED.items() if re.search(p, src)]
    print("  dau hieu: %s" % ", ".join(found))
