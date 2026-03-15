#!/bin/bash
# 清理 Docker Pod 资源

echo "=========================================="
echo "  清理 Docker Pod 资源"
echo "=========================================="

# 获取当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" == "192.168.30.132" ]]; then
    POD_NAME="pod-a"
    NET_NAME="pod-net-a"
else
    POD_NAME="pod-b"
    NET_NAME="pod-net-b"
fi

echo "[*] 清理 Pod: $POD_NAME"

# 删除容器
echo "[*] 删除容器..."
docker rm -f ${POD_NAME}-pause ${POD_NAME}-app1 ${POD_NAME}-app2 2>/dev/null || true

# 删除网络
echo "[*] 删除网络..."
docker network rm $NET_NAME 2>/dev/null || true

echo ""
echo "[OK] 清理完成"
