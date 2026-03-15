#!/bin/bash
# 测试脚本 - 验证跨宿主机 Pod 通信

echo "=========================================="
echo "  跨宿主机 Pod 通信测试"
echo "=========================================="
echo ""

# 获取当前主机IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
echo "[*] 当前主机: $CURRENT_IP"

# 根据当前主机判断对端Pod IP
if [[ "$CURRENT_IP" == "192.168.1.10" ]]; then
    MY_POD="10.0.1.2"
    PEER_POD="10.0.2.2"
    PEER_HOST="192.168.1.20"
else
    MY_POD="10.0.2.2"
    PEER_POD="10.0.1.2"
    PEER_HOST="192.168.1.10"
fi

echo "[*] 本地 Pod: $MY_POD"
echo "[*] 对端 Pod: $PEER_POD"
echo "[*] 对端宿主机: $PEER_HOST"
echo ""

# 1. 检查本地Pod
echo "=== 1. 检查本地 Pod 网络 ==="
echo "本地 Pod IP: $MY_POD"
if ip addr show veth0 2>/dev/null | grep -q "$MY_POD"; then
    echo "[OK] 本地 Pod 网络正常"
else
    echo "[!] 本地 Pod 网络异常"
fi

# 2. 检查隧道
echo ""
echo "=== 2. 检查 IP-in-IP 隧道 ==="
if ip link show tunl0 &>/dev/null; then
    echo "[OK] 隧道设备 tunl0 存在"
    ip -s tunnel show tunl0 | head -5
else
    echo "[!] 隧道设备 tunl0 不存在"
fi

# 3. 检查路由
echo ""
echo "=== 3. 检查路由表 ==="
echo "目标网段路由:"
ip route | grep -E "(10.0.1|10.0.2)"

# 4. 测试本地通信
echo ""
echo "=== 4. 测试本地通信 (lo 和 本地 Pod) ==="
echo "ping lo:"
ping -c 2 -W 1 127.0.0.1 | tail -2

echo ""
echo "ping 本地 Pod:"
ping -c 2 -W 1 $MY_POD | tail -2

# 5. 测试对端宿主机连通性
echo ""
echo "=== 5. 测试对端宿主机连通性 ==="
echo "ping $PEER_HOST:"
if ping -c 2 -W 2 $PEER_HOST &>/dev/null; then
    echo "[OK] 宿主机可达"
else
    echo "[!] 宿主机不可达，请检查网络"
fi

# 6. 测试跨宿主机 Pod 通信
echo ""
echo "=== 6. 测试跨宿主机 Pod 通信 ==="
echo "ping 对端 Pod ($PEER_POD):"
if ping -c 3 -W 2 $PEER_POD &>/dev/null; then
    echo ""
    echo "=========================================="
    echo "  🎉 跨宿主机 Pod 通信成功!"
    echo "=========================================="

    # 显示隧道统计
    echo ""
    echo "隧道统计:"
    ip -s tunnel show tunl0
else
    echo ""
    echo "=========================================="
    echo "  ❌ 通信失败，请检查:"
    echo "=========================================="
    echo "1. 对端宿主机是否运行了 setup_ipip.sh"
    echo "2. 两台宿主机是否可以互相 ping 通"
    echo "3. 防火墙是否阻止了 IP 协议 4 (IP-in-IP)"
    echo ""
    echo "检查 IP-in-IP 协议:"
    if grep -q "^ipip" /proc/net/protocols 2>/dev/null; then
        grep "^ipip" /proc/net/protocols
    else
        echo "[!] IP-in-IP 模块可能未加载，尝试: modprobe ipip"
    fi
fi
