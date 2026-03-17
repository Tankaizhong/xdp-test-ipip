#!/bin/bash
# 测试 Docker Pod + IP-in-IP 通信

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

echo "=========================================="
echo "  Docker Pod + IP-in-IP 通信测试"
echo "=========================================="

CURRENT_IP=$(hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" == "192.168.30.132" ]]; then
    MY_POD="pod-a"
    MY_POD_IP="10.244.1.2"
    MY_GW="10.244.1.1"
    PEER_IP="10.244.2.2"
    PEER_HOST="192.168.30.134"
else
    MY_POD="pod-b"
    MY_POD_IP="10.244.2.2"
    MY_GW="10.244.2.1"
    PEER_IP="10.244.1.2"
    PEER_HOST="192.168.30.132"
fi

echo "[*] 宿主机: $CURRENT_IP  Pod: $MY_POD ($MY_POD_IP)"
echo ""

# 1. 检查容器
echo "=== 1. 容器状态 ==="
docker ps --format "{{.Names}}\t{{.Status}}" | grep "^$MY_POD" || echo "[!] $MY_POD 未运行"

# 2. 检查网桥
echo ""
echo "=== 2. 网桥 br0 ==="
ip addr show br0 2>/dev/null | grep "inet " || echo "[!] br0 无 IP"

# 3. 检查隧道
echo ""
echo "=== 3. IP-in-IP 隧道 ==="
ip tunnel show ipip0 2>/dev/null || echo "[!] ipip0 不存在"

# 4. 检查路由
echo ""
echo "=== 4. 路由 (10.244.*) ==="
ip route | grep "10.244\." || echo "[!] 无 Pod 路由"

# 5. 容器内网络
echo ""
echo "=== 5. 容器内网络 ==="
docker exec $MY_POD ip addr show eth0 2>/dev/null | grep "inet " || echo "[!] 容器无 eth0"
docker exec $MY_POD ip route 2>/dev/null || true

# 6. Pod 内 loopback
echo ""
echo "=== 6. 容器内 ping 127.0.0.1 ==="
docker exec $MY_POD ping -c 1 -W 1 127.0.0.1 | tail -1

# 7. 宿主机 ping 网关 (br0 自身)
echo ""
echo "=== 7. 宿主机 ping br0 网关 ($MY_GW) ==="
ping -c 1 -W 1 $MY_GW &>/dev/null && echo "[OK] $MY_GW 可达" || echo "[!] $MY_GW 不可达"

# 8. 宿主机 ping 容器 IP
echo ""
echo "=== 8. 宿主机 ping 本地容器 ($MY_POD_IP) ==="
ping -c 1 -W 1 $MY_POD_IP &>/dev/null && echo "[OK] $MY_POD_IP 可达" || echo "[!] $MY_POD_IP 不可达"

# 9. 宿主机 ping 对端宿主机
echo ""
echo "=== 9. 宿主机 ping 对端宿主机 ($PEER_HOST) ==="
ping -c 1 -W 2 $PEER_HOST &>/dev/null && echo "[OK] $PEER_HOST 可达" || echo "[!] $PEER_HOST 不可达"

# 10. 跨宿主机 Pod 通信 (关键测试)
echo ""
echo "=== 10. 跨宿主机 Pod 通信 (容器内 ping $PEER_IP) ==="
if docker exec $MY_POD ping -c 3 -W 3 $PEER_IP; then
    echo ""
    echo "=========================================="
    echo "  [OK] 跨宿主机 Pod 通信成功!"
    echo "=========================================="
    echo ""
    echo "[*] 隧道统计:"
    ip -s tunnel show ipip0
else
    echo ""
    echo "=========================================="
    echo "  [FAIL] 通信失败"
    echo "=========================================="
    echo "排查方向:"
    echo "  1. 对端是否运行了 setup_docker_ipip.sh"
    echo "  2. 防火墙是否放行 IP 协议 4 (IPIP)"
    echo "     iptables -I FORWARD -i ipip0 -j ACCEPT"
    echo "     iptables -I FORWARD -o ipip0 -j ACCEPT"
    echo "  3. tcpdump 抓包确认隧道流量:"
    echo "     tcpdump -i any proto 4 -n"
fi
