#!/bin/bash
# 跨宿主机 Pod 通信 Demo - IP-in-IP 隧道
#
# 拓扑结构:
#
#   宿主机 A (192.168.1.10)          宿主机 B (192.168.1.20)
#   ┌─────────────────────┐          ┌─────────────────────┐
#   │  Pod A1             │          │  Pod B1             │
#   │  10.0.1.2/24        │◄─────────►│  10.0.2.2/24        │
#   │  veth-A1            │  隧道     │  veth-B1            │
#   │        └─► br0 ────┼──────────┼───br0 ◄─┘           │
#   └─────────────────────┘  IP-in-IP  └─────────────────────┘
#
# 工作原理:
# 1. 每个宿主机创建网桥 br0，连接本地 Pod 的 veth 对
# 2. 创建 IP-in-IP 隧道接口 (tunl0)
# 3. 添加路由: 目标 Pod 网段走隧道
# 4. 隧道对端指定对方宿主机 IP

set -e

#=================== 配置 ===================
# 宿主机 A 配置
HOST_A_IP="192.168.30.132"
HOST_B_IP="192.168.30.134"

# Pod 网段
POD_NET_A="10.244.2.0/24"
POD_NET_B="10.244.1.0/24"

# 隧道设备名
TUNNEL_DEV="tunl0"
#===========================================

echo "=========================================="
echo "  跨宿主机 Pod 通信 Demo - IP-in-IP"
echo "=========================================="
echo ""

# 检测当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前主机 IP: $CURRENT_IP"

# 判断是 Host A 还是 Host B
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    echo "[*] 识别为: 宿主机 A"
    echo "[*] Pod 网段: $POD_NET_A"
    echo "[*] 对端宿主机: $HOST_B_IP"
    echo "[*] 对端 Pod 网段: $POD_NET_B"

    MY_POD_NET=$POD_NET_A
    PEER_HOST=$HOST_B_IP
    PEER_POD_NET=$POD_NET_B

elif [ "$CURRENT_IP" = "$HOST_B_IP" ]; then
    echo "[*] 识别为: 宿主机 B"
    echo "[*] Pod 网段: $POD_NET_B"
    echo "[*] 对端宿主机: $HOST_A_IP"
    echo "[*] 对端 Pod 网段: $POD_NET_A"

    MY_POD_NET=$POD_NET_B
    PEER_HOST=$HOST_A_IP
    PEER_POD_NET=$POD_NET_A
else
    echo "[!] 错误: 当前IP ($CURRENT_IP) 不匹配配置"
    echo "    请修改脚本中的 HOST_A_IP 和 HOST_B_IP"
    exit 1
fi

echo ""
echo "=========================================="
echo "  开始配置网络..."
echo "=========================================="

# 1. 创建网桥 (如果没有)
if ! ip link show br0 &>/dev/null; then
    echo "[1] 创建网桥 br0"
    ip link add br0 type bridge
    ip link set br0 up
else
    echo "[1] 网桥 br0 已存在"
    ip link set br0 up
fi

# 2. 创建本地 Pod veth 对
# 在实际场景中，这些由 kubelet 创建
echo "[2] 创建本地 Pod 网络 (模拟 Pod: 10.0.x.2)"

# 创建 veth 对
ip link add veth0 type veth peer name veth0-br
ip link set veth0 up

# 设置 Pod IP
ip addr add 10.0.1.2/24 dev veth0 2>/dev/null || true
ip link set veth0-br master br0
ip link set veth0-br up

# 根据主机设置正确的IP
if [ "$CURRENT_IP" = "$HOST_A_IP" ]; then
    ip addr add 10.0.1.2/24 dev veth0 2>/dev/null || true
else
    ip addr add 10.0.2.2/24 dev veth0 2>/dev/null || true
fi

# 3. 配置 IP-in-IP 隧道
echo "[3] 配置 IP-in-IP 隧道"

# 加载 ipip 模块
modprobe ipip 2>/dev/null || true

# 创建隧道 (使用系统隧道设备 tunl0)
ip link set $TUNNEL_DEV up

# 设置隧道本地和远程地址
ip addr add 10.0.0.$(echo $CURRENT_IP | cut -d. -f4)/30 dev $TUNNEL_DEV 2>/dev/null || true
ip tunnel del $TUNNEL_DEV 2>/dev/null || true
ip tunnel add $TUNNEL_DEV mode ipip remote $PEER_HOST local $CURRENT_IP
ip link set $TUNNEL_DEV up

# 4. 添加路由
echo "[4] 添加路由规则"

# 转发来自 Pod 网段的流量到网桥
iptables -A FORWARD -s $MY_POD_NET -d $PEER_POD_NET -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -s $PEER_POD_NET -d $MY_POD_NET -j ACCEPT 2>/dev/null || true

# 启用 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward

# 5. 显示配置结果
echo ""
echo "=========================================="
echo "  配置完成! 当前网络状态:"
echo "=========================================="
echo ""
echo "[网桥设备]"
ip addr show br0
echo ""
echo "[Pod veth设备]"
ip addr show veth0
echo ""
echo "[隧道设备]"
ip addr show tunl0
echo ""
echo "[路由表]"
ip route
echo ""
echo "[IP转发]"
cat /proc/sys/net/ipv4/ip_forward
echo ""

# 6. 等待用户启动对端
echo "=========================================="
echo "  使用说明:"
echo "=========================================="
echo ""
echo "1. 在宿主机 B ($HOST_B_IP) 上运行相同脚本"
echo "2. 等待对端配置完成后，执行测试:"
echo ""
echo "   # 测试连通性"
echo "   ping -c 3 10.0.2.2    # 从 Host A 测试 Host B 的 Pod"
echo "   ping -c 3 10.0.1.2    # 从 Host B 测试 Host A 的 Pod"
echo ""
echo "3. 查看隧道统计:"
echo "   ip -s tunnel show tunl0"
echo ""
echo "=========================================="
