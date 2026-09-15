#!/usr/bin/env bash
# Doc trang thai that cua BabyGOAT tren mainnet.
export PATH="$PATH:/home/vuduykhang/.foundry/bin"
RPC=https://ethereum-rpc.publicnode.com
T=0x26d86F942D514B470Ba5dF311027a870110F6699

q() { # ten  chuky
  v=$(timeout 40 cast call "$T" "$2" --rpc-url "$RPC" 2>/dev/null | head -1)
  printf "  %-22s %s\n" "$1" "${v:-<loi>}"
}

echo "=== QUYEN SO HUU ==="
q "owner()"              "owner()(address)"
echo
echo "=== CO CHE BAT/TAT ==="
for f in enableOffTrade enableKillBlock enableRewardList enableSwapLimit enableWalletLimit enableChangeTax antiSYNC airdropEnable enableTransferFee currencyIsEth; do
  q "$f" "$f()(bool)"
done
echo
echo "=== THAM SO KINH TE ==="
for f in _buyFundFee _buyLPFee _buyBurnFee _sellFundFee _sellLPFee _sellBurnFee transferFee kb airdropNumbs numTokensSellRate swapAtAmount maxBuyAmount maxWalletAmount startTradeBlock totalSupply; do
  q "$f" "$f()(uint256)"
done
echo
echo "=== DIA CHI ==="
q "fundAddress"          "fundAddress()(address)"
q "_mainPair"            "_mainPair()(address)"
q "currency"             "currency()(address)"
q "generateLpReceiverAddr" "generateLpReceiverAddr()(address)"
echo
echo "=== KHAC ==="
q "name"                 "name()(string)"
q "symbol"               "symbol()(string)"
q "decimals"             "decimals()(uint256)"
