#!/bin/bash
# Docker Pod 跨宿主机通信 - IP-in-IP 隧道
#
# 拓扑:
#   宿主机 A (192.168.30.132)          宿主机 B (192.168.30.134)
#   ┌──────────────────────────┐        ┌──────────────────────────┐
#   │ veth-host: 10.244.1.1/24 │        │ veth-host: 10.244.2.1/24 │
#   │    ↕ (直连 veth pair)    │        │    ↕ (直连 veth pair)    │
#   │ [pod-a] eth0:10.244.1.2  │        │ [pod-b] eth0:10.244.2.2  │
#   │                          │        │                          │
#   │  ipip0 ──────────────────────────── ipip0                   │
#   └──────────────────────────┘        └──────────────────────────┘

set -e

if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

#=================== 配置 ===================
HOST_A_IP="192.168.30.132"
HOST_B_IP="192.168.30.134"

POD_A_IP="10.244.1.2"
POD_B_IP="10.244.2.2"
POD_A_GW="10.244.1.1"
POD_B_GW="10.244.2.1"
POD_A_NET="10.244.1.0/24"
POD_B_NET="10.244.2.0/24"
#===========================================

echo "=========================================="
echo "  Docker Pod 跨宿主机通信 - IP-in-IP"
echo "=========================================="

CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前宿主机: $CURRENT_IP"

if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    MY_POD="pod-a"
    MY_POD_IP=$POD_A_IP
    MY_GW=$POD_A_GW
    MY_NET=$POD_A_NET
    PEER_HOST_IP=$HOST_B_IP
    PEER_NET=$POD_B_NET
elif [ "$CURRENT_IP" = "$HOST_B_IP" ]; then
    MY_POD="pod-b"
    MY_POD_IP=$POD_B_IP
    MY_GW=$POD_B_GW
    MY_NET=$POD_B_NET
    PEER_HOST_IP=$HOST_A_IP
    PEER_NET=$POD_A_NET
else
    echo "[!] 错误: 当前IP ($CURRENT_IP) 不在配置中"
    exit 1
fi

echo "[*] Pod: $MY_POD ($MY_POD_IP), 对端宿主机: $PEER_HOST_IP"
echo ""

if ! docker info &>/dev/null; then
    echo "[!] Docker 未运行"
    exit 1
fi

echo "=========================================="
echo "  步骤 1: 关闭所有干扰"
echo "=========================================="

iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F

sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0

systemctl stop firewalld 2>/dev/null || true
ufw disable 2>/dev/null || true

echo "[OK] 防火墙/iptables 已清空"

echo "=========================================="
echo "  步骤 2: 清理旧资源"
echo "=========================================="

docker rm -f $MY_POD 2>/dev/null || true
ip link del veth-host 2>/dev/null || true
ip link del br0 2>/dev/null || true
ip tunnel del ipip0 2>/dev/null || true

echo "=========================================="
echo "  步骤 3: 启动 Pod 容器"
echo "=========================================="

docker run -d \
    --name $MY_POD \
    --network none \
    --privileged \
    xdp-pod:latest \
    sleep infinity

echo "[OK] $MY_POD 启动完成"

echo "=========================================="
echo "  步骤 4: 连接容器 (直接 veth pair，无 bridge)"
echo "=========================================="

PID=$(docker inspect --format '{{.State.Pid}}' $MY_POD)
echo "[*] 容器 PID: $PID"

# veth-host 留在宿主机，veth-ctr 移入容器
ip link add veth-host type veth peer name veth-ctr
ip addr add ${MY_GW}/24 dev veth-host
ip link set veth-host up

ip link set veth-ctr netns $PID
nsenter -t $PID -n -- ip link set veth-ctr name eth0
nsenter -t $PID -n -- ip addr add ${MY_POD_IP}/24 dev eth0
nsenter -t $PID -n -- ip link set eth0 up
nsenter -t $PID -n -- ip link set lo up
nsenter -t $PID -n -- ip route add default via $MY_GW

echo "[OK] veth-host(${MY_GW}/24) <-> 容器 eth0(${MY_POD_IP}/24)"

echo "=========================================="
echo "  步骤 5: 配置 IP-in-IP 隧道"
echo "=========================================="

modprobe ipip 2>/dev/null || true

ip tunnel add ipip0 mode ipip remote $PEER_HOST_IP local $CURRENT_IP
ip link set ipip0 up
ip route add $PEER_NET dev ipip0

echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[OK] ipip0: $CURRENT_IP <-> $PEER_HOST_IP"
echo "[OK] 路由: $PEER_NET via ipip0"

echo ""
echo "=========================================="
echo "  步骤 6: 验证本地连通性"
echo "=========================================="

echo "[*] 宿主机 ping 容器 (${MY_POD_IP}):"
ping -c 2 -W 2 $MY_POD_IP && echo "[OK] 本地连通" || echo "[!] 本地不通，请检查"

echo ""
echo "=========================================="
echo "  配置完成!"
echo "=========================================="
echo ""
echo "[*] 容器网络:"
nsenter -t $PID -n -- ip addr show eth0
echo ""
echo "[*] 宿主机路由:"
ip route
echo ""
echo "测试命令:"
echo "  docker exec $MY_POD ping -c 3 $([ "$MY_POD" = "pod-a" ] && echo $POD_B_IP || echo $POD_A_IP)"
echo ""
echo "清理: ./cleanup_ipip.sh"
