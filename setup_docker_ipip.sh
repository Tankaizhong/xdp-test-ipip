#!/bin/bash
# Docker Pod 跨宿主机通信 - IP-in-IP 隧道封装
#
# 使用 Docker 容器模拟 Kubernetes Pod，通过 IP-in-IP 隧道通信
#
# 拓扑:
#   宿主机 A (192.168.30.132)      宿主机 B (192.168.30.134)
#   ┌─────────────────────────┐      ┌─────────────────────────┐
#   │ Pod A                   │      │ Pod B                   │
#   │  ┌──────────────────┐   │      │  ┌──────────────────┐   │
#   │  │ pause (10.0.1.2)│   │◄────►│  │ pause (10.0.2.2)│   │
#   │  │ app1             │   │ IPIP │  │ app1             │   │
#   │  │ app2             │   │ 隧道 │  │ app2             │   │
#   │  └────────┬─────────┘   │      │  └────────┬─────────┘   │
#   │           │ br0         │      │           │ br0         │
#   │           └────┬────────┘      │           └────┬────────┘   │
#   └────────────────│──────────────┴────────────────│──────────────
#                    │        IP-in-IP 隧道           │
#              tunl0 │◄────────────────────────────►│ tunl0
#                    └────────────────────────────────┘
#
# Pod 内通信: 同一 Pod 内容器共享网络命名空间 (network_mode: container)
# Pod 间通信: 通过 IP-in-IP 隧道封装

set -e

#=================== 配置 ===================
HOST_A_IP="192.168.30.132"
HOST_B_IP="192.168.30.134"

# Pod 网络配置
POD_A_IP="10.0.1.2"
POD_B_IP="10.0.2.2"
POD_A_NET="10.0.1.0/24"
POD_B_NET="10.0.2.0/24"

# Docker 网络名称
BRIDGE_NET="pod-bridge"

# Pod 名称
POD_A_NAME="pod-a"
POD_B_NAME="pod-b"
#===========================================

echo "=========================================="
echo "  Docker Pod 跨宿主机通信 - IP-in-IP"
echo "=========================================="

# 检测当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前宿主机: $CURRENT_IP"

# 判断角色
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    echo "[*] 角色: 宿主机 A (Pod A)"
    MY_POD_IP=$POD_A_IP
    PEER_POD_IP=$POD_B_IP
    MY_POD_NAME=$POD_A_NAME
    PEER_POD_NAME=$POD_B_NAME
    PEER_HOST_IP=$HOST_B_IP
    PEER_NET=$POD_B_NET
elif [ "$CURRENT_IP" = "$HOST_B_IP" ]; then
    echo "[*] 角色: 宿主机 B (Pod B)"
    MY_POD_IP=$POD_B_IP
    PEER_POD_IP=$POD_A_IP
    MY_POD_NAME=$POD_B_NAME
    PEER_POD_NAME=$POD_A_NAME
    PEER_HOST_IP=$HOST_A_IP
    PEER_NET=$POD_A_NET
else
    echo "[!] 错误: 当前IP ($CURRENT_IP) 不匹配"
    exit 1
fi

echo ""
echo "[*] 本地 Pod: $MY_POD_IP ($MY_POD_NAME)"
echo "[*] 对端 Pod: $PEER_POD_IP ($PEER_POD_NAME)"
echo "[*] 对端宿主机: $PEER_HOST_IP"
echo ""

# 检查 Docker
if ! docker info &>/dev/null; then
    echo "[!] Docker 未运行"
    exit 1
fi

echo "=========================================="
echo "  步骤 1: 清理旧资源"
echo "=========================================="

docker rm -f ${MY_POD_NAME}-pause ${MY_POD_NAME}-app1 ${MY_POD_NAME}-app2 2>/dev/null || true
docker network rm $BRIDGE_NET 2>/dev/null || true

# 清理旧的网络设备
ip link del tunl0 2>/dev/null || true
ip link del br0 2>/dev/null || true
ip link del veth-pod 2>/dev/null || true

echo "=========================================="
echo "  步骤 2: 创建 Linux 网桥"
echo "=========================================="

# 创建网桥
ip link add br0 type bridge
ip addr add 10.0.0.1/30 dev br0  # 隧道对接地址
ip link set br0 up

echo "[OK] 网桥 br0 创建完成"

echo "=========================================="
echo "  步骤 3: 创建 Docker 网络 (bridge 模式)"
echo "=========================================="

# 创建 Docker bridge 网络
docker network create \
    --driver bridge \
    --subnet=10.0.0.0/30 \
    --gateway=10.0.0.1 \
    $BRIDGE_NET

echo "[OK] Docker 网络 $BRIDGE_NET 创建完成"

echo "=========================================="
echo "  步骤 4: 创建 Pod (pause 容器)"
echo "=========================================="

# 创建 pause 容器 (Pod 基础容器)
# 使用 host 网络，然后通过 veth 连接到网桥
docker run -d \
    --name ${MY_POD_NAME}-pause \
    --hostname ${MY_POD_NAME} \
    --network $BRIDGE_NET \
    --privileged \
    registry.k8s.io/pause:3.9

# 获取 pause 容器的 veth 设备名
PAUSE_VETH=$(docker exec ${MY_POD_NAME}-pause cat /sys/class/net/eth0/iflink)
echo "[*] Pause 容器网络接口: eth0"

# 设置 Pod IP
docker exec ${MY_POD_NAME}-pause ip addr add ${MY_POD_IP}/24 dev eth0
docker exec ${MY_POD_NAME}-pause ip route add default via 10.0.0.1

echo "[OK] Pause 容器创建: ${MY_POD_NAME}-pause (${MY_POD_IP})"

echo "=========================================="
echo "  步骤 5: 创建应用容器 (加入 Pod)"
echo "=========================================="

# app1 容器 - 共享 pause 的网络命名空间
docker run -d \
    --name ${MY_POD_NAME}-app1 \
    --hostname ${MY_POD_NAME}-app1 \
    --network container:${MY_POD_NAME}-pause \
    alpine:latest \
    sleep infinity

docker exec ${MY_POD_NAME}-app1 apk add --no-cache iputils-ping iproute2 2>/dev/null || true
echo "[OK] ${MY_POD_NAME}-app1 创建完成"

# app2 容器
docker run -d \
    --name ${MY_POD_NAME}-app2 \
    --hostname ${MY_POD_NAME}-app2 \
    --network container:${MY_POD_NAME}-pause \
    alpine:latest \
    sleep infinity

docker exec ${MY_POD_NAME}-app2 apk add --no-cache iputils-ping iproute2 2>/dev/null || true
echo "[OK] ${MY_POD_NAME}-app2 创建完成"

echo "=========================================="
echo "  步骤 6: 配置 IP-in-IP 隧道"
echo "=========================================="

# 加载 ipip 模块
modprobe ipip 2>/dev/null || true

# 删除旧隧道
ip tunnel del tunl0 2>/dev/null || true

# 创建 IP-in-IP 隧道
ip tunnel add tunl0 mode ipip remote $PEER_HOST_IP local $CURRENT_IP
ip link set tunl0 up

# 添加路由 - 对端 Pod 网段走隧道
ip route add $PEER_NET dev tunl0

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[OK] IP-in-IP 隧道创建完成"
echo "    本地: $CURRENT_IP -> 对端: $PEER_HOST_IP"
echo "    路由: $PEER_NET via tunl0"

echo "=========================================="
echo "  步骤 7: 验证配置"
echo "=========================================="

echo ""
echo "[*] Pod 网络信息:"
docker exec ${MY_POD_NAME}-app1 ip addr show eth0 | grep inet

echo ""
echo "[*] 路由信息:"
ip route

echo ""
echo "[*] 隧道信息:"
ip tunnel show

echo ""
echo "=========================================="
echo "  配置完成!"
echo "=========================================="

echo ""
echo "[*] Pod 容器列表:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep $MY_POD_NAME

echo ""
echo "=========================================="
echo "  测试步骤:"
echo "=========================================="
echo ""
echo "1. 在两台宿主机都运行脚本后，测试跨主机通信:"
echo ""
echo "   # 宿主机 A (容器内)"
echo "   docker exec pod-a-app1 ping -c 3 $PEER_POD_IP"
echo ""
echo "   # 宿主机 B (容器内)"
echo "   docker exec pod-b-app1 ping -c 3 $PEER_POD_IP"
echo ""
echo "2. 查看隧道统计:"
echo "   ip -s tunnel show tunl0"
echo ""
echo "3. 清理:"
echo "   ./cleanup_ipip.sh"
echo ""
