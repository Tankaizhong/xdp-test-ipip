#!/bin/bash
# 测试 Docker Pod 跨宿主机通信

echo "=========================================="
echo "  Docker Pod 通信测试"
echo "=========================================="

# 获取本机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" == "192.168.30.132" ]]; then
    MY_POD="pod-a"
    PEER_POD="pod-b"
    PEER_IP="10.244.1.2"
else
    MY_POD="pod-b"
    PEER_POD="pod-a"
    PEER_IP="10.244.2.2"
fi

echo "[*] 当前宿主机: $CURRENT_IP"
echo "[*] 本地 Pod: $MY_POD"
echo "[*] 对端 Pod IP: $PEER_IP"
echo ""

# 1. 检查 pause 容器
echo "=== 1. 检查 Pod 容器 ==="
for container in ${MY_POD}-pause ${MY_POD}-app1 ${MY_POD}-app2; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "[OK] $container 运行中"
    else
        echo "[!] $container 未运行"
    fi
done

# 2. 检查网络
echo ""
echo "=== 2. 检查 Pod 网络 ==="
docker exec ${MY_POD}-app1 ip addr show eth0 | grep inet

# 3. 测试 Pod 内通信
echo ""
echo "=== 3. 测试 Pod 内通信 ==="
echo "[*] 从 app1 ping localhost:"
docker exec ${MY_POD}-app1 ping -c 2 -W 1 127.0.0.1 | tail -2

# 4. 测试宿主机通信
echo ""
echo "=== 4. 测试宿主机连通性 ==="
echo "[*] Ping 对端宿主机 (测试物理网络):"
gateway_ip=$(docker network inspect pod-net-${MY_POD##pod-} | grep Gateway | grep -oE '10\.244\.[0-9]+\.[0-9]+')
if [ -n "$gateway_ip" ]; then
    echo "[*] Gateway: $gateway_ip"
fi

# 5. 测试跨 Pod 通信
echo ""
echo "=== 5. 测试跨宿主机 Pod 通信 ==="
echo "[*] Ping 对端 Pod: $PEER_IP"
if docker exec ${MY_POD}-app1 ping -c 3 -W 2 $PEER_IP &>/dev/null; then
    echo ""
    echo "=========================================="
    echo "  ✓ 跨宿主机 Pod 通信成功!"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "  ✗ 通信失败"
    echo "=========================================="
    echo "请检查:"
    echo "1. 对端宿主机是否运行了 setup_docker_pod.sh"
    echo "2. 两台宿主机之间的网络是否连通"
    echo "3. 物理交换机是否允许 macvlan (可能需要混杂模式)"
    echo ""
    echo "尝试添加混杂模式:"
    echo "  sudo ip link set <interface> promisc on"
fi
