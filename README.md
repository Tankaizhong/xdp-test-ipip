# 跨宿主机 Pod 通信 Demo - IP-in-IP 隧道

## 概述

本 Demo 展示如何使用 Linux 原生的 IP-in-IP 隧道实现不同宿主机上的 Pod 之间的通信。

## 网络拓扑

```
   宿主机 A (192.168.1.10)              宿主机 B (192.168.1.20)
   ┌─────────────────────┐              ┌─────────────────────┐
   │  Pod A1             │              │  Pod B1             │
   │  10.0.1.2/24        │◄────────────►│  10.0.2.2/24        │
   │  veth0              │  IP-in-IP    │  veth0              │
   │        └─► br0 ────┼──────────────┼───br0 ◄─┘           │
   └─────────────────────┘    隧道      └─────────────────────┘
```

## 工作原理

1. **网桥 (Bridge)**: 每个宿主机创建 Linux 网桥 `br0`，连接本地 Pod 的 veth 设备
2. **IP-in-IP 隧道**: 创建点对点隧道，封装 Pod 流量
3. **路由**: 通过路由表将目标 Pod 网段的流量引导到隧道

## 前置要求

- 两台 Linux 宿主机 (物理机或虚拟机)
- 需要 root 权限
- 内核支持 IP-in-IP (`modprobe ipip`)
- 两台宿主机之间网络互通

## 快速开始

### 1. 修改配置

编辑 `setup_ipip.sh`，根据你的实际环境修改：

```bash
HOST_A_IP="192.168.1.10"  # 宿主机 A 的内网 IP
HOST_B_IP="192.168.1.20"  # 宿主机 B 的内网 IP
```

### 2. 在两台宿主机上执行

**宿主机 A:**
```bash
sudo chmod +x setup_ipip.sh
sudo ./setup_ipip.sh
```

**宿主机 B:**
```bash
sudo chmod +x setup_ipip.sh
sudo ./setup_ipip.sh
```

### 3. 测试连通性

```bash
# 在宿主机 A 上
sudo ./test_connectivity.sh
ping -c 3 10.0.2.2   # 测试到宿主机 B 的 Pod

# 在宿主机 B 上
ping -c 3 10.0.1.2   # 测试到宿主机 A 的 Pod
```

### 4. 清理

```bash
sudo ./cleanup.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `setup_ipip.sh` | 主配置脚本，创建网络命名空间、网桥、隧道 |
| `test_connectivity.sh` | 测试脚本，验证连通性 |
| `cleanup.sh` | 清理脚本，移除所有创建的网络设备 |

## 常见问题

### Q: 通信失败
A: 检查以下内容：
1. 两台宿主机之间是否可以 ping 通
2. 防火墙是否允许 IP 协议 4 (IP-in-IP)
3. 确认两台宿主机都运行了配置脚本

### Q: 找不到 tunl0 设备
A: 确认 ipip 内核模块已加载：`sudo modprobe ipip`

## 注意事项

- 本 Demo 仅用于学习和测试，生产环境建议使用 Flannel、Calico、Cilium 等成熟的网络方案
- IP-in-IP 只能用于 IPv4，如需 IPv6 考虑使用 IP6IP6
