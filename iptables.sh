#!/bin/bash
# =============================================================================
# ClearNDR iptables ruleset — ICT30016 lab
# RHEL host — Suricata IPS inline via NFQUEUE
#
# Interfaces:
#   eth0  — host management (Docker bridge access)
#   eth1  — sWINT-CTRL    (internal control segment)
#   eth2  — sWINT-SMARTB  (smart building segment)
#   eth3  — sWINT-OUTSIDE (external/untrusted)
#   eth4  — 192.168.1.0/24 out-of-band management
#   br+   — Docker bridge networks (wildcard)
# =============================================================================

set -e

echo "=== ClearNDR iptables setup starting ==="

# -----------------------------------------------------------------------------
# 0. Prerequisites
# -----------------------------------------------------------------------------
# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
echo "[OK] IP forwarding enabled"

# Install iptables-services if not present (RHEL/Rocky)
if ! systemctl is-enabled iptables &>/dev/null; then
    dnf install -y iptables-services
    systemctl enable iptables
    echo "[OK] iptables-services installed and enabled"
fi

# -----------------------------------------------------------------------------
# 1. Flush existing rules — start clean
# -----------------------------------------------------------------------------
echo "--- Flushing existing rules ---"
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT
iptables -F DOCKER-USER 2>/dev/null || true
echo "[OK] Chains flushed"

# -----------------------------------------------------------------------------
# 2. Default policies
# -----------------------------------------------------------------------------
echo "--- Setting default policies ---"
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT
echo "[OK] INPUT=DROP  FORWARD=DROP  OUTPUT=ACCEPT"

# -----------------------------------------------------------------------------
# 3. INPUT chain — management services on eth0
# -----------------------------------------------------------------------------
echo "--- Building INPUT chain ---"

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# SSH
iptables -A INPUT -i eth0 -p tcp --dport 22 \
    -j LOG --log-prefix "IPT-ALLOW-SSH: " --log-level 4
iptables -A INPUT -i eth0 -p tcp --dport 22 -j ACCEPT

# Kibana
iptables -A INPUT -i eth0 -p tcp --dport 5601 \
    -j LOG --log-prefix "IPT-ALLOW-KIBANA: " --log-level 4
iptables -A INPUT -i eth0 -p tcp --dport 5601 -j ACCEPT

# ClearNDR Manager API
iptables -A INPUT -i eth0 -p tcp --dport 8080 \
    -j LOG --log-prefix "IPT-ALLOW-API: " --log-level 4
iptables -A INPUT -i eth0 -p tcp --dport 8080 -j ACCEPT

# Allow established return traffic on management
iptables -A INPUT -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow established return on eth4 out-of-band management
iptables -A INPUT -i eth4 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log everything else hitting INPUT
iptables -A INPUT -j LOG --log-prefix "IPT-INPUT-DROP: " --log-level 4

echo "[OK] INPUT chain built"

# -----------------------------------------------------------------------------
# 4. FORWARD chain — management eth0 <-> Docker bridge
# -----------------------------------------------------------------------------
echo "--- Building FORWARD chain (management) ---"

# eth0 → Docker containers (log then allow)
iptables -A FORWARD -i eth0 -o br+ \
    -j LOG --log-prefix "IPT-ALLOW-MGMT-OUT: " --log-level 4
iptables -A FORWARD -i eth0 -o br+ -j ACCEPT

# Docker → eth0 return traffic (log then allow)
iptables -A FORWARD -i br+ -o eth0 -m state --state ESTABLISHED,RELATED \
    -j LOG --log-prefix "IPT-ALLOW-MGMT-RTN: " --log-level 4
iptables -A FORWARD -i br+ -o eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT

echo "[OK] Management FORWARD rules added"

# -----------------------------------------------------------------------------
# 5. FORWARD chain — IPS inline (NFQUEUE) inter-segment rules
# -----------------------------------------------------------------------------
echo "--- Building FORWARD chain (NFQUEUE IPS) ---"

# CTRL <-> SMARTB (east-west)
iptables -A FORWARD -i eth1 -o eth2 -j NFQUEUE --queue-num 0
iptables -A FORWARD -i eth2 -o eth1 -j NFQUEUE --queue-num 0

# OUTSIDE <-> CTRL
iptables -A FORWARD -i eth3 -o eth1 -j NFQUEUE --queue-num 0
iptables -A FORWARD -i eth1 -o eth3 -j NFQUEUE --queue-num 0

# OUTSIDE <-> SMARTB
iptables -A FORWARD -i eth3 -o eth2 -j NFQUEUE --queue-num 0
iptables -A FORWARD -i eth2 -o eth3 -j NFQUEUE --queue-num 0

echo "[OK] NFQUEUE IPS rules added (all inter-segment pairs)"

# -----------------------------------------------------------------------------
# 6. FORWARD chain — catch-all DROP logger
# -----------------------------------------------------------------------------
iptables -A FORWARD -j LOG --log-prefix "IPT-FORWARD-DROP: " --log-level 4
echo "[OK] DROP logger added"

# -----------------------------------------------------------------------------
# 7. DOCKER-USER chain — allow management into containers
# -----------------------------------------------------------------------------
echo "--- Building DOCKER-USER chain ---"

# Flush first — safe to modify, Docker never touches DOCKER-USER
iptables -F DOCKER-USER 2>/dev/null || true

# Log then allow eth0 management into any Docker bridge
iptables -I DOCKER-USER 1 -i eth0 -o br+ \
    -j LOG --log-prefix "IPT-DOCKER-ALLOW: " --log-level 4
iptables -I DOCKER-USER 2 -i eth0 -o br+ -j ACCEPT

# Required — return to DOCKER-FORWARD chain when done
iptables -A DOCKER-USER -j RETURN

echo "[OK] DOCKER-USER chain built"

# -----------------------------------------------------------------------------
# 8. Dedicated iptables log file (optional — requires rsyslog)
# -----------------------------------------------------------------------------
if [ -f /etc/rsyslog.conf ]; then
    if ! grep -q "iptables.log" /etc/rsyslog.conf; then
        echo "kern.warning /var/log/iptables.log" >> /etc/rsyslog.conf
        systemctl restart rsyslog
        echo "[OK] Dedicated iptables log → /var/log/iptables.log"
    else
        echo "[SKIP] iptables rsyslog entry already exists"
    fi
fi

# -----------------------------------------------------------------------------
# 9. Save rules
# -----------------------------------------------------------------------------
echo "--- Saving rules ---"
service iptables save
echo "[OK] Rules saved to /etc/sysconfig/iptables"

# -----------------------------------------------------------------------------
# 10. Verification output
# -----------------------------------------------------------------------------
echo ""
echo "=== Final ruleset ==="
echo ""
echo "--- FILTER FORWARD ---"
iptables -L FORWARD --line-numbers -v
echo ""
echo "--- FILTER INPUT ---"
iptables -L INPUT --line-numbers -v
echo ""
echo "--- DOCKER-USER ---"
iptables -L DOCKER-USER --line-numbers -v 2>/dev/null || echo "(Docker not running — DOCKER-USER not yet available)"
echo ""
echo "=== ClearNDR iptables setup complete ==="
echo ""
echo "To monitor logs:"
echo "  tail -f /var/log/messages | grep IPT-"
echo "  tail -f /var/log/iptables.log"
echo ""
echo "To verify NFQUEUE is running:"
echo "  docker exec <sensor_container> ps aux | grep suricata"
echo ""
echo "To check rule counters live:"
echo "  watch -n1 'iptables -L FORWARD -v --line-numbers'"