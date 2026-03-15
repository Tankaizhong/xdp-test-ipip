#!/bin/bash
# 清理脚本 - 移除所有创建的 网络设备

echo "=========================================="
echo "  清理网络配置"
echo "=========================================="

# 删除 veth 设备
echo "[*] 删除 veth 设备..."
ip link del veth0 2>/dev/null || true

# 删除网桥
echo "[*] 删除网桥 br0..."
ip link del br0 2>/dev/null || true

# 删除隧道
echo "[*] 删除 IP-in-IP 隧道..."
ip link del tunl0 2>/dev/null || true
ip tunnel del tunl0 2>/dev/null || true

# 清理 iptables 规则
echo "[*] 清理 iptables 规则..."
iptables -D FORWARD -s 10.0.1.0/24 -d 10.0.2.0/24 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -s 10.0.2.0/24 -d 10.0.1.0/24 -j ACCEPT 2>/dev/null || true

echo ""
echo "[OK] 清理完成"
