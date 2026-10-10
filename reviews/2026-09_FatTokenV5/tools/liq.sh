#!/usr/bin/env bash
# Reads the real Uniswap V2 WETH liquidity of each token through a public RPC.
# Input: lines of "SYMBOL 0xaddress" on stdin.
export PATH="$PATH:$HOME/.foundry/bin"
RPC=https://ethereum-rpc.publicnode.com
V2F=0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
WETH=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
ZERO=0x0000000000000000000000000000000000000000

printf "%-13s %-44s %-12s %-10s %s\n" "SYM" "ADDRESS" "V2_PAIR" "WETH_RES" "GHI_CHU"
while read -r SYM ADDR; do
  [ -z "$ADDR" ] && continue
  PAIR=$(timeout 40 cast call "$V2F" "getPair(address,address)(address)" "$ADDR" "$WETH" --rpc-url "$RPC" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$PAIR" ] || [ "${PAIR,,}" = "${ZERO,,}" ]; then
    printf "%-13s %-44s %-12s %-10s %s\n" "$SYM" "$ADDR" "khong-co" "-" "khong co cap V2"
    continue
  fi
  WBAL=$(timeout 40 cast call "$WETH" "balanceOf(address)(uint256)" "$PAIR" --rpc-url "$RPC" 2>/dev/null | awk '{print $1}')
  [ -z "$WBAL" ] && WBAL=0
  ETH=$(python3 -c "print('%.6f' % (int('${WBAL:-0}')/1e18))" 2>/dev/null || echo "?")
  NOTE=$(python3 -c "
v=float('$ETH')
print('CHET' if v < 0.05 else ('gan chet' if v < 1 else 'CON SONG - loai'))" 2>/dev/null)
  printf "%-13s %-44s %-12s %-10s %s\n" "$SYM" "$ADDR" "${PAIR:0:10}" "$ETH" "$NOTE"
done
