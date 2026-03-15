#!/bin/bash
# Docker Pod 跨宿主机通信 - 使用 macvlan 网络
#
# 模拟 Kubernetes Pod:
# - 使用 pause 容器作为 Pod 基础容器
# - 其他容器共享 pause 容器的网络命名空间
#
# 拓扑:
#   宿主机 A (192.168.30.132)      宿主机 B (192.168.30.134)
#   ┌─────────────────────────┐     ┌─────────────────────────┐
#   │ Pod A (10.244.2.2)     │◄───►│ Pod B (10.244.1.2)     │
#   │  ├── pause (10.244.2.2)│     │  ├── pause (10.244.1.2)│
#   │  ├── app-a1             │     │  ├── app-b1             │
#   │  └── app-a2             │     │  └── app-b2             │
#   └─────────────────────────┘     └─────────────────────────┘
#
# 关键: 使用 macvlan 让容器直接获得独立的 IP

set -e

#=================== 配置 ===================
HOST_A_IP="192.168.30.132"
HOST_B_IP="192.168.30.134"

# Pod 网络配置
POD_A_IP="10.244.2.2"
POD_B_IP="10.244.1.2"
POD_A_NET="10.244.2.0/24"
POD_B_NET="10.244.1.0/24"
POD_A_GW="10.244.2.1"
POD_B_GW="10.244.1.1"

# Docker 网络名称
NET_NAME_A="pod-net-a"
NET_NAME_B="pod-net-b"

# Pod 名称前缀
POD_A_NAME="pod-a"
POD_B_NAME="pod-b"
#===========================================

echo "=========================================="
echo "  Docker Pod 跨宿主机通信 Demo"
echo "=========================================="

# 检测当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前宿主机: $CURRENT_IP"

# 判断是 Host A 还是 Host B
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    echo "[*] 角色: 宿主机 A (Pod A)"
    MY_POD_IP=$POD_A_IP
    PEER_POD_IP=$POD_B_IP
    MY_NET=$NET_NAME_A
    MY_SUBNET=$POD_A_NET
    MY_GW=$POD_A_GW
    POD_NAME=$POD_A_NAME
    IS_HOST_A=true
elif [ "$CURRENT_IP" = "$HOST_B_IP" ]; then
    echo "[*] 角色: 宿主机 B (Pod B)"
    MY_POD_IP=$POD_B_IP
    PEER_POD_IP=$POD_A_IP
    MY_NET=$NET_NAME_B
    MY_SUBNET=$POD_B_NET
    MY_GW=$POD_B_GW
    POD_NAME=$POD_B_NAME
    IS_HOST_A=false
else
    echo "[!] 错误: 当前IP ($CURRENT_IP) 不匹配"
    echo "    请修改脚本中的 HOST_A_IP 和 HOST_B_IP"
    exit 1
fi

echo ""
echo "[*] 本地 Pod IP: $MY_POD_IP"
echo "[*] 对端 Pod IP: $PEER_POD_IP"
echo "[*] Pod 名称: $POD_NAME"
echo ""

# 检查 Docker
if ! docker info &>/dev/null; then
    echo "[!] Docker 未运行"
    exit 1
fi

echo "=========================================="
echo "  步骤 1: 清理旧资源"
echo "=========================================="

# 删除旧容器
docker rm -f ${POD_NAME}-pause ${POD_NAME}-app1 ${POD_NAME}-app2 2>/dev/null || true

# 删除旧网络
docker network rm $MY_NET 2>/dev/null || true

echo "=========================================="
echo "  步骤 2: 创建 macvlan 网络"
echo "=========================================="

# 获取宿主机物理网卡
PARENT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "[*] 物理网卡: $PARENT_IFACE"

# 检查是否已有同名网络
if docker network inspect $MY_NET &>/dev/null; then
    echo "[*] 删除已有网络..."
    docker network rm $MY_NET
fi

# 创建 macvlan 网络
docker network create \
    -d macvlan \
    --subnet=$MY_SUBNET \
    --gateway=$MY_GW \
    -o parent=$PARENT_IFACE \
    -o macvlan_mode=bridge \
    $MY_NET

echo "[OK] 网络 $MY_NET 创建完成"

echo "=========================================="
echo "  步骤 3: 创建 Pod (pause 容器)"
echo "=========================================="

# 创建 pause 容器 (Pod 基础容器)
docker run -d \
    --name ${POD_NAME}-pause \
    --hostname ${POD_NAME} \
    --network $MY_NET \
    --ip $MY_POD_IP \
    --privileged \
    registry.k8s.io/pause:3.9

echo "[OK] Pause 容器创建完成: ${POD_NAME}-pause"

# 查看 pause 容器网络
echo ""
echo "[*] Pause 容器网络信息:"
docker exec ${POD_NAME}-pause ip addr

echo "=========================================="
echo "  步骤 4: 创建应用容器 (加入 Pod)"
echo "=========================================="

# 创建 app1 容器 - 共享 pause 容器的网络命名空间
docker run -d \
    --name ${POD_NAME}-app1 \
    --hostname ${POD_NAME}-app1 \
    --network container:${POD_NAME}-pause \
    --privileged \
    alpine:latest \
    sleep infinity

# 安装网络工具
docker exec ${POD_NAME}-app1 apk add --no-cache iputils-ping iproute2 curl 2>/dev/null || true

echo "[OK] App1 容器创建完成: ${POD_NAME}-app1"

# 创建 app2 容器 - 同样共享 pause 容器的网络
docker run -d \
    --name ${POD_NAME}-app2 \
    --hostname ${POD_NAME}-app2 \
    --network container:${POD_NAME}-pause \
    --privileged \
    alpine:latest \
    sleep infinity

docker exec ${POD_NAME}-app2 apk add --no-cache iputils-ping iproute2 2>/dev/null || true

echo "[OK] App2 容器创建完成: ${POD_NAME}-app2"

echo ""
echo "=========================================="
echo "  步骤 5: 验证 Pod 内网络共享"
echo "=========================================="

echo "[*] 在 app1 中查看 Pod IP:"
docker exec ${POD_NAME}-app1 ip addr show eth0 | grep inet

echo ""
echo "[*] 在 app2 中查看 Pod IP:"
docker exec ${POD_NAME}-app2 ip addr show eth0 | grep inet

echo ""
echo "[*] 从 app1 ping app2 (同一 Pod 内):"
docker exec ${POD_NAME}-app1 ping -c 2 127.0.0.1

echo ""
echo "=========================================="
echo "  配置完成!"
echo "=========================================="

echo ""
echo "[*] Pod 容器列表:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}" | grep $POD_NAME

echo ""
echo "[*] 网络信息:"
docker network inspect $MY_NET | grep -A 5 "Subnet"

echo ""
echo "=========================================="
echo "  测试步骤 (在两台宿主机都运行后):"
echo "=========================================="
echo ""
echo "1. 在宿主机 A 测试到宿主机 B:"
echo "   docker exec pod-a-app1 ping -c 3 $PEER_POD_IP"
echo ""
echo "2. 在宿主机 B 测试到宿主机 A:"
echo "   docker exec pod-b-app1 ping -c 3 $PEER_POD_IP"
echo ""
echo "3. 查看容器内的网络命名空间:"
echo "   docker exec ${POD_NAME}-app1 ip link"
echo "   docker exec ${POD_NAME}-pause ip link"
echo ""
echo "4. 清理:"
echo "   docker rm -f ${POD_NAME}-pause ${POD_NAME}-app1 ${POD_NAME}-app2"
echo "   docker network rm $MY_NET"
echo ""
