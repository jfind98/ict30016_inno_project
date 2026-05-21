#!/bin/bash

# Usage: ./nmap_scan.sh <target_ip> [output_dir]
# Requires root/sudo for OS detection and SYN scans

TARGET="$1"
OUTPUT_DIR="${2:-./scan_results}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <target_ip_or_range> [output_dir]"
    echo "  Examples:"
    echo "    $0 192.168.1.1"
    echo "    $0 192.168.1.0/24"
    echo "    $0 10.0.0.5 /tmp/results"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASE="$OUTPUT_DIR/${TARGET//\//_}_$TIMESTAMP"

echo "[*] Target: $TARGET"
echo "[*] Output: $BASE.*"
echo ""

# 1. Fast ping sweep / host discovery
echo "[1/5] Host discovery..."
nmap -sn "$TARGET" -oN "${BASE}_discovery.txt" 2>/dev/null
echo "    Done."

# 2. Full TCP port scan (all 65535 ports)
echo "[2/5] Full TCP port scan (all ports)..."
nmap -sS -p- --min-rate 1000 -T4 "$TARGET" \
    -oN "${BASE}_tcp_full.txt" \
    -oX "${BASE}_tcp_full.xml" 2>/dev/null
echo "    Done."

# 3. Service/version detection + OS fingerprinting on open ports
echo "[3/5] Service & OS detection..."
nmap -sS -sV -O -p- --min-rate 1000 -T4 "$TARGET" \
    -oN "${BASE}_services.txt" \
    -oX "${BASE}_services.xml" 2>/dev/null
echo "    Done."

# 4. UDP scan (top 200 common UDP ports — full UDP is very slow)
echo "[4/5] UDP scan (top 200 ports)..."
nmap -sU --top-ports 200 -T4 "$TARGET" \
    -oN "${BASE}_udp.txt" \
    -oX "${BASE}_udp.xml" 2>/dev/null
echo "    Done."

# 5. Vulnerability scan using nmap NSE scripts
echo "[5/5] Vulnerability scan (NSE scripts)..."
nmap -sS -sV -p- --min-rate 1000 -T4 \
    --script vuln,exploit,auth,default,safe \
    "$TARGET" \
    -oN "${BASE}_vulns.txt" \
    -oX "${BASE}_vulns.xml" 2>/dev/null
echo "    Done."

echo ""
echo "[*] Scan complete. Results saved to: $OUTPUT_DIR"
echo ""
echo "--- Open ports summary ---"
grep "^[0-9]" "${BASE}_services.txt" 2>/dev/null || echo "(no open ports found or file missing)"
echo ""
echo "--- Vulnerability findings ---"
grep -E "(VULNERABLE|CVE-|exploitable)" "${BASE}_vulns.txt" 2>/dev/null | head -40 || echo "(no vulnerabilities flagged)"
