#!/bin/bash
# 测试 Docker Pod + IP-in-IP 通信

echo "=========================================="
echo "  Docker Pod + IP-in-IP 通信测试"
echo "=========================================="

CURRENT_IP=$(hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" == "192.168.30.132" ]]; then
    MY_POD="pod-a"
    PEER_POD="pod-b"
    PEER_IP="10.0.2.2"
else
    MY_POD="pod-b"
    PEER_POD="pod-a"
    PEER_IP="10.0.1.2"
fi

echo "[*] 当前宿主机: $CURRENT_IP"
echo "[*] 本地 Pod: $MY_POD"
echo "[*] 对端 Pod: $PEER_IP"
echo ""

# 1. 检查容器
echo "=== 1. 检查 Pod 容器 ==="
for c in ${MY_POD}-pause ${MY_POD}-app1 ${MY_POD}-app2; do
    docker ps --format "{{.Names}}" | grep -q "^${c}$" && echo "[OK] $c" || echo "[!] $c 未运行"
done

# 2. 检查网桥
echo ""
echo "=== 2. 检查网桥 br0 ==="
ip addr show br0 2>/dev/null | grep "inet " && echo "[OK] br0 正常" || echo "[!] br0 异常"

# 3. 检查隧道
echo ""
echo "=== 3. 检查 IP-in-IP 隧道 ==="
ip tunnel show tunl0 2>/dev/null && echo "[OK] 隧道正常" || echo "[!] 隧道异常"

# 4. 检查路由
echo ""
echo "=== 4. 检查路由 ==="
ip route | grep "10.0."

# 5. 测试 Pod 内通信
echo ""
echo "=== 5. 测试 Pod 内通信 ==="
echo "[*] 从 app1 ping localhost:"
docker exec ${MY_POD}-app1 ping -c 2 -W 1 127.0.0.1 | tail -2

# 6. 测试本 Pod IP
echo ""
echo "=== 6. 测试本 Pod IP ==="
docker exec ${MY_POD}-app1 ping -c 2 -W 1 ${MY_POD}-app1 | tail -2

# 7. 测试跨主机 Pod 通信
echo ""
echo "=== 7. 测试跨宿主机 Pod 通信 ==="
echo "[*] Ping 对端 Pod: $PEER_IP"
if docker exec ${MY_POD}-app1 ping -c 3 -W 3 $PEER_IP &>/dev/null; then
    echo ""
    echo "=========================================="
    echo "  ✓ 跨宿主机 Pod 通信成功!"
    echo "=========================================="

    echo ""
    echo "[*] 隧道统计:"
    ip -s tunnel show tunl0
else
    echo ""
    echo "=========================================="
    echo "  ✗ 通信失败"
    echo "=========================================="
    echo "检查:"
    echo "1. 对端宿主机是否运行了 setup_docker_ipip.sh"
    echo "2. 两台宿主机之间是否可以 ping 通"
    echo "3. 防火墙是否允许 IP 协议 4"
fi
