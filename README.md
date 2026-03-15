# 跨宿主机 Pod 通信 Demo - IP-in-IP 隧道

## 概述

使用 Docker 容器模拟 Kubernetes Pod，通过 **IP-in-IP 隧道** 实现跨宿主机通信。

## 网络拓扑

```
宿主机 A (192.168.30.132)           宿主机 B (192.168.30.134)
┌─────────────────────────┐         ┌─────────────────────────┐
│ Pod A                   │         │ Pod B                   │
│  ├── pause (10.0.1.2)  │         │  ├── pause (10.0.2.2)  │
│  ├── app1              │◄────────►│  ├── app1              │
│  └── app2              │  IP-in-IP │  └── app2              │
└────────────┬────────────┘   隧道   └────────────┬────────────┘
             │ br0                               │ br0
             └────────────┬──────────────────────┘
                          │ tunl0
```

## 工作原理

1. **Pod 模拟**: 使用 `pause` 容器作为 Pod 基础容器，其他容器共享其网络命名空间
2. **网桥**: Linux bridge (br0) 连接本地 Pod
3. **IP-in-IP 隧道**: 创建点对点隧道，封装跨主机流量
4. **路由**: 目标 Pod 网段通过隧道转发

## 快速开始

### 1. 在两台宿主机运行

```bash
# 宿主机 A 和 B
sudo ./setup_docker_ipip.sh
```

### 2. 测试

```bash
# 宿主机 A
docker exec pod-a-app1 ping -c 3 10.0.2.2

# 宿主机 B
docker exec pod-b-app1 ping -c 3 10.0.1.2
```

### 3. 清理

```bash
sudo ./cleanup_ipip.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `setup_docker_ipip.sh` | 主配置脚本 (Docker Pod + IP-in-IP 隧道) |
| `test_ipip.sh` | 测试脚本 |
| `cleanup_ipip.sh` | 清理脚本 |

## 注意事项

- 需要 root 权限
- 确保两台宿主机之间网络互通
- 防火墙需允许 IP 协议 4 (IP-in-IP)
