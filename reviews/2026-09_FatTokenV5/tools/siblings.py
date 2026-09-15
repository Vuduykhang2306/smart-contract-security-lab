"""Tim cac token khac dung chung template FatTokenV5 va xem con chu so huu khong.

Nhan dien bang chu ky ham dac trung cua template, goi eth_call theo lo qua JSON-RPC.
"""
import json, urllib.request, sys

RPC = "https://ethereum-rpc.publicnode.com"
# selector 4 byte, lay bang: cast sig "airdropNumbs()"
SEL = {
    "airdropNumbs": "0xe32759cf",
    "kb":           "0x2dab693f",
    "owner":        "0x8da5cb5b",
}

def batch(calls):
    """calls: list of (id, to, data). Tra ve dict id -> result hex hoac None."""
    payload = [{"jsonrpc": "2.0", "id": i, "method": "eth_call",
                "params": [{"to": to, "data": data}, "latest"]} for i, to, data in calls]
    req = urllib.request.Request(RPC, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            out = json.loads(r.read().decode())
    except Exception as e:
        print("  loi lo:", str(e)[:70], file=sys.stderr)
        return {}
    res = {}
    for item in out if isinstance(out, list) else []:
        res[item.get("id")] = item.get("result")
    return res

def probe(addrs, sel, chunk=40):
    got = {}
    for i in range(0, len(addrs), chunk):
        part = addrs[i:i + chunk]
        calls = [(j, part[j], sel) for j in range(len(part))]
        r = batch(calls)
        for j, a in enumerate(part):
            v = r.get(j)
            if v and v != "0x" and len(v) >= 66:
                got[a] = v
    return got

pool = json.load(open("pool.json"))
addrs = sorted({(v.get("address_hash") or "") for v in pool.values() if v.get("address_hash")})
print("dia chi trong pool:", len(addrs), file=sys.stderr)

# Tang 1: co ham airdropNumbs() -> rat nhieu kha nang la template nay
a1 = probe(addrs, SEL["airdropNumbs"])
print("co airdropNumbs():", len(a1), file=sys.stderr)

# Tang 2: xac nhan them bang kb()
a2 = probe(sorted(a1), SEL["kb"])
print("xac nhan them bang kb():", len(a2), file=sys.stderr)

# Tang 3: doc owner()
owners = probe(sorted(a2), SEL["owner"])

byaddr = {(v.get("address_hash") or "").lower(): v for v in pool.values()}
rows = []
for a in sorted(a2):
    o = owners.get(a, "")
    own = "0x" + o[-40:] if len(o) >= 42 else "?"
    renounced = own.lower() in ("0x" + "0" * 40, "0x" + "0" * 36 + "dead")
    m = byaddr.get(a.lower(), {})
    rows.append({"addr": a, "sym": m.get("symbol"), "name": m.get("name"),
                 "holders": m.get("holders_count"), "owner": own, "renounced": renounced})
json.dump(rows, open("siblings.json", "w"), indent=1)

live = [r for r in rows if not r["renounced"]]
print("\n%-12s %-20s %-8s %-44s %s" % ("SYM", "NAME", "HOLDER", "OWNER", "ADDRESS"))
for r in rows:
    print("%-12s %-20s %-8s %-44s %s" % (str(r["sym"])[:12], str(r["name"])[:20],
                                         r["holders"], r["owner"], r["addr"]))
print("\nTONG: %d token dung template | %d CON CHU SO HUU | %d da tu bo"
      % (len(rows), len(live), len(rows) - len(live)))
