#!/bin/bash
# 清理 Docker Pod + IP-in-IP 资源

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

echo "[*] 删除 veth-pod..."
ip link del veth-pod 2>/dev/null || true

echo "[*] 删除网桥 br0..."
ip link del br0 2>/dev/null || true

echo "[*] 删除 IP-in-IP 隧道..."
ip tunnel del ipip0 2>/dev/null || true

echo ""
echo "[OK] 清理完成"
