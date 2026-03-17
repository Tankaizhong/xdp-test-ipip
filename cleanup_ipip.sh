#!/bin/bash
# 清理 Docker Pod + IP-in-IP 资源

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo "=========================================="
echo "  清理 Docker Pod + IP-in-IP 资源"
echo "=========================================="

CURRENT_IP=$(hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" == "192.168.30.132" ]]; then
    POD_NAME="pod-a"
else
    POD_NAME="pod-b"
fi

echo "[*] 删除容器 $POD_NAME..."
docker rm -f $POD_NAME 2>/dev/null || true

echo "[*] 删除 veth-host..."
ip link del veth-host 2>/dev/null || true

echo "[*] 删除网桥 br0 (如有)..."
ip link del br0 2>/dev/null || true

echo "[*] 清理 iptables MASQUERADE..."
iptables -t nat -D POSTROUTING -s 10.244.1.0/24 ! -d 10.244.0.0/16 -o ens33 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -s 10.244.2.0/24 ! -d 10.244.0.0/16 -o ens33 -j MASQUERADE 2>/dev/null || true

echo "[*] 删除 IP-in-IP 隧道..."
ip tunnel del ipip0 2>/dev/null || true

echo ""
echo "[OK] 清理完成"
