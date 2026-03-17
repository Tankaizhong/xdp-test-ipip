#!/bin/bash
# Docker Pod 跨宿主机通信 - IP-in-IP 隧道
#
# 拓扑:
#   宿主机 A (192.168.30.132)          宿主机 B (192.168.30.134)
#   ┌──────────────────────────┐        ┌──────────────────────────┐
#   │ br0: 10.244.1.1/24       │        │ br0: 10.244.2.1/24       │
#   │  └─ veth-pod             │        │  └─ veth-pod             │
#   │      └─ [pod-a]          │        │      └─ [pod-b]          │
#   │         eth0:10.244.1.2  │        │         eth0:10.244.2.2  │
#   │                          │        │                          │
#   │  ipip0 ──────────────────────────── ipip0                   │
#   │  route: 10.244.2.0/24 ──► ipip0   route: 10.244.1.0/24 ──► ipip0 │
#   └──────────────────────────┘        └──────────────────────────┘
#
# 数据路径 (Pod A → Pod B):
#   容器A(10.244.1.2) → br0(gw) → 内核路由 → ipip0封装
#   → 物理网络 → ipip0解封 → 内核路由 → br0 → veth → 容器B(10.244.2.2)

set -e

# 确保以 root 运行
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

# iptables 全部放行
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F

# 关闭 rp_filter
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0

# 关闭 firewalld / ufw
systemctl stop firewalld 2>/dev/null || true
sudo ufw disable 2>/dev/null || true

echo "[OK] 防火墙/iptables 已清空"

echo "=========================================="
echo "  步骤 2: 清理旧资源"
echo "=========================================="

docker rm -f $MY_POD 2>/dev/null || true
ip link del br0 2>/dev/null || true
ip tunnel del ipip0 2>/dev/null || true

echo "=========================================="
echo "  步骤 3: 创建网桥 br0"
echo "=========================================="

ip link add br0 type bridge
ip addr add ${MY_GW}/24 dev br0
ip link set br0 up
echo "[OK] br0 up, IP: ${MY_GW}/24"

echo "=========================================="
echo "  步骤 4: 启动 Pod 容器"
echo "=========================================="

# 用 --network none，后续手动配置网络
docker run -d \
    --name $MY_POD \
    --network none \
    --privileged \
    xdp-pod:latest \
    sleep infinity

echo "[OK] $MY_POD 启动完成"

echo "=========================================="
echo "  步骤 5: 连接容器到 br0 (veth pair)"
echo "=========================================="

# 获取容器 PID
PID=$(docker inspect --format '{{.State.Pid}}' $MY_POD)
echo "[*] 容器 PID: $PID"

# 创建 veth pair: 宿主机侧 veth-pod <-> 容器侧 veth-ctr
ip link add veth-pod type veth peer name veth-ctr

# 宿主机侧加入 br0
ip link set veth-pod master br0
ip link set veth-pod up

# 容器侧移入容器的 netns
ip link set veth-ctr netns $PID

# 在容器 netns 内配置网络
nsenter -t $PID -n -- ip link set veth-ctr name eth0
nsenter -t $PID -n -- ip addr add ${MY_POD_IP}/24 dev eth0
nsenter -t $PID -n -- ip link set eth0 up
nsenter -t $PID -n -- ip link set lo up
nsenter -t $PID -n -- ip route add default via $MY_GW

echo "[OK] eth0 配置完成: ${MY_POD_IP}/24, gw ${MY_GW}"

echo "=========================================="
echo "  步骤 6: 配置 IP-in-IP 隧道"
echo "=========================================="

modprobe ipip 2>/dev/null || true

ip tunnel add ipip0 mode ipip remote $PEER_HOST_IP local $CURRENT_IP
ip link set ipip0 up

# 对端 Pod 网段走隧道
ip route add $PEER_NET dev ipip0

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# Pod 访问外部网络时 SNAT 为宿主机 IP（对端 Pod 子网不做 NAT，走隧道）
iptables -t nat -A POSTROUTING -s $MY_NET ! -d 10.244.0.0/16 -o ens33 -j MASQUERADE

echo "[OK] ipip0 up: $CURRENT_IP <-> $PEER_HOST_IP"
echo "[OK] 路由: $PEER_NET via ipip0"

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
echo "[*] 隧道:"
ip tunnel show ipip0
echo ""
echo "测试命令:"
echo "  docker exec $MY_POD ping -c 3 $([ "$MY_POD" = "pod-a" ] && echo $POD_B_IP || echo $POD_A_IP)"
echo ""
echo "清理: ./cleanup_ipip.sh"
