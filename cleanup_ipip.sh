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

# 删除容器
echo "[*] 删除容器..."
docker rm -f ${POD_NAME}-pause ${POD_NAME}-app1 ${POD_NAME}-app2 2>/dev/null || true

# 删除 Docker 网络
echo "[*] 删除 Docker 网络..."
docker network rm pod-bridge 2>/dev/null || true

# 删除 Linux 网桥
echo "[*] 删除网桥 br0..."
ip link del br0 2>/dev/null || true

# 删除 IP-in-IP 隧道配置
echo "[*] 删除 IP-in-IP 隧道..."
ip tunnel del ipip0 2>/dev/null || true

echo ""
echo "[OK] 清理完成"
