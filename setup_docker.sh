#!/bin/bash
# Docker 版本 - 跨宿主机 Pod 通信 Demo
#
# 使用 Docker macvlan 网络实现跨宿主机容器通信
#
# 拓扑:
#   宿主机 A                宿主机 B
#   ┌──────────┐           ┌──────────┐
#   │ pod-a    │◄─────────►│ pod-b    │
#   │ 10.244.2.2│  物理网络 │10.244.1.2│
#   └──────────┘           └──────────┘

set -e

#=================== 配置 ===================
# 宿主机 A 配置
HOST_A_IP="192.168.30.132"
HOST_B_IP="192.168.30.134"

# Docker 网络名称
NETWORK_A_NAME="pod-net-a"
NETWORK_B_NAME="pod-net-b"

# Pod 网段
POD_NET_A="10.244.2.0/24"
POD_NET_B="10.244.1.0/24"
#===========================================

echo "=========================================="
echo "  跨宿主机 Pod 通信 Demo - Docker"
echo "=========================================="

# 检测当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前主机 IP: $CURRENT_IP"

# 判断是 Host A 还是 Host B
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    echo "[*] 识别为: 宿主机 A"
    MY_POD_IP="10.244.2.2"
    PEER_POD_IP="10.244.1.2"
    MY_NET=$NETWORK_A_NAME
    PEER_NET=$NETWORK_B_NAME
    MY_GW="10.244.2.1"
elif [ "$CURRENT_IP" = "$HOST_B_IP" ]; then
    echo "[*] 识别为: 宿主机 B"
    MY_POD_IP="10.244.1.2"
    PEER_POD_IP="10.244.2.2"
    MY_NET=$NETWORK_B_NAME
    PEER_NET=$NETWORK_A_NAME
    MY_GW="10.244.1.1"
else
    echo "[!] 错误: 当前IP ($CURRENT_IP) 不匹配配置"
    exit 1
fi

echo ""
echo "[*] 本地 Pod IP: $MY_POD_IP"
echo "[*] 对端 Pod IP: $PEER_POD_IP"
echo ""

# 检查 Docker 是否运行
if ! docker info &>/dev/null; then
    echo "[!] Docker 未运行"
    exit 1
fi

echo "=========================================="
echo "  创建 Docker 网络..."
echo "=========================================="

# 检查父网络接口
PARENT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "[*] 父网络接口: $PARENT_IFACE"

# 创建 macvlan 网络
echo "[*] 创建 macvlan 网络: $MY_NET"

# 检查网络是否已存在，如果存在则删除
if docker network inspect $MY_NET &>/dev/null; then
    echo "[*] 网络 $MY_NET 已存在，删除..."
    docker network rm $MY_NET
fi

# 获取宿主机IP对应的子网
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    SUBNET=$POD_NET_A
    GATEWAY=$MY_GW
else
    SUBNET=$POD_NET_B
    GATEWAY=$MY_GW
fi

# 创建 macvlan 网络
docker network create \
    -d macvlan \
    --subnet=$SUBNET \
    --gateway=$GATEWAY \
    -o parent=$PARENT_IFACE \
    $MY_NET

echo "[OK] 网络 $MY_NET 创建完成"

echo ""
echo "=========================================="
echo "  启动 Pod 容器..."
echo "=========================================="

# 停止并删除已存在的容器
if docker ps -a | grep -q "pod-a\|pod-b"; then
    echo "[*] 删除旧容器..."
    docker rm -f pod-a pod-b 2>/dev/null || true
fi

# 启动 Pod 容器
echo "[*] 启动 Pod 容器..."
docker run -d \
    --name pod-a \
    --hostname pod-a \
    --network $MY_NET \
    --ip $MY_POD_IP \
    --privileged \
    alpine:latest \
    sleep infinity

echo "[OK] 容器 pod-a 启动完成"

# 安装网络工具到容器
echo "[*] 安装网络工具到容器..."
docker exec pod-a apk add --no-cache iputils-ping iproute2

echo ""
echo "=========================================="
echo "  配置路由..."
echo "=========================================="

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 添加到对端 Pod 网段的路由
PEER_NETWORK=$(echo $PEER_POD_IP | sed 's/\.[0-9]*$/.0\/24/')
echo "[*] 添加路由: $PEER_NETWORK"

# 对于 macvlan，容器可以直接通过物理网络通信
# 如果需要通过路由器，需要添加路由

echo ""
echo "=========================================="
echo "  配置完成!"
echo "=========================================="

echo ""
echo "[*] 容器信息:"
docker exec pod-a ip addr show eth0
echo ""

echo "[*] 容器路由:"
docker exec pod-a ip route

echo ""
echo "=========================================="
echo "  使用说明:"
echo "=========================================="
echo ""
echo "1. 在宿主机 B ($HOST_B_IP) 上运行相同脚本"
echo "2. 测试连通性:"
echo ""
echo "   # 在宿主机 A 的容器中"
echo "   docker exec pod-a ping -c 3 $PEER_POD_IP"
echo ""
echo "   # 在宿主机 B 的容器中"
echo "   docker exec pod-b ping -c 3 $MY_POD_IP"
echo ""
echo "3. 查看容器网络:"
echo "   docker exec pod-a ip addr"
echo "   docker network inspect $MY_NET"
echo ""
echo "4. 清理:"
echo "   docker rm -f pod-a"
echo "   docker network rm $MY_NET"
echo ""
