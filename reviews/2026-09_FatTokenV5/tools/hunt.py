import json, urllib.request, urllib.parse, time, re, sys
B = "https://eth.blockscout.com/api/v2"
def get(path, params=None, retries=2):
    url = B + path + ("?" + urllib.parse.urlencode(params) if params else "")
    for a in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if a == retries: return {"__err": str(e)[:60]}
            time.sleep(1.5)

KEYWORDS = ["inu", "pepe", "moon", "elon", "doge", "shib", "floki", "wojak", "chad", "baby"]
pool = {}
for k in KEYWORDS:
    d = get("/tokens", {"q": k, "type": "ERC-20"})
    for it in (d.get("items") or []):
        a = it.get("address_hash") or it.get("address")
        if a: pool.setdefault(a, it)
    time.sleep(0.4)
print("ứng viên thô:", len(pool), file=sys.stderr)
json.dump(pool, open("pool.json", "w"))
