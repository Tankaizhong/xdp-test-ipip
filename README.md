# 跨宿主机 Pod 通信 Demo

本项目包含两种实现跨宿主机 Pod 通信的方式：

## 方案一: Docker Pod 版本 (推荐)

使用 Docker 容器模拟 Kubernetes Pod，通过 macvlan 网络实现跨宿主机通信。

### 特性

- 使用 `pause` 容器作为 Pod 基础容器
- 其他容器共享 pause 容器的网络命名空间 (和 Kubernetes Pod 完全一致)
- 使用 macvlan 让容器获得独立 IP

### 拓扑

```
宿主机 A (192.168.30.132)           宿主机 B (192.168.30.134)
┌─────────────────────────┐         ┌─────────────────────────┐
│ Pod A (10.244.2.2)     │◄────────►│ Pod B (10.244.1.2)    │
│  ├── pause             │  macvlan │  ├── pause             │
│  ├── app-a1            │          │  ├── app-b1            │
│  └── app-a2            │          │  └── app-b2            │
└─────────────────────────┘          └─────────────────────────┘
```

### 快速开始

```bash
# 宿主机 A
sudo ./setup_docker_pod.sh

# 宿主机 B
sudo ./setup_docker_pod.sh

# 测试
docker exec pod-a-app1 ping -c 3 10.244.1.2

# 清理
sudo ./cleanup_docker_pod.sh
```

### 文件

| 文件 | 说明 |
|------|------|
| `setup_docker_pod.sh` | 主配置脚本 |
| `test_docker_pod.sh` | 测试脚本 |
| `cleanup_docker_pod.sh` | 清理脚本 |
| `docker-compose-pod.yml` | Docker Compose 版本 |

---

## 方案二: IP-in-IP 隧道版本

使用 Linux 原生的 IP-in-IP 隧道实现跨宿主机通信。

### 拓扑

```
宿主机 A              宿主机 B
┌─────────────────────┐ ┌─────────────────────┐
│ Pod A1              │◄─── IP-in-IP ───►│ Pod B1
│ 10.0.1.2/24        │    隧道          │ 10.0.2.2/24
└─────────────────────┘ └─────────────────────┘
```

### 快速开始

```bash
# 修改配置
HOST_A_IP="192.168.1.10"  # 宿主机 A
HOST_B_IP="192.168.1.20"  # 宿主机 B

# 两台宿主机分别执行
sudo ./setup_ipip.sh

# 测试
ping -c 3 10.0.2.2
```

### 文件

| 文件 | 说明 |
|------|------|
| `setup_ipip.sh` | 主配置脚本 |
| `test_connectivity.sh` | 测试脚本 |
| `cleanup.sh` | 清理脚本 |

---

## 常见问题

### Docker Pod 版本

**Q: 跨主机通信失败**
A: 检查物理交换机是否允许 macvlan，可能需要：
```bash
sudo ip link set <interface> promisc on
```

**Q: pause 镜像拉取失败**
A: 使用国内镜像：
```bash
docker pull mirror.gcr.io/pause:3.9
# 或
docker pull registry.access.redhat.com/pause:latest
```

### IP-in-IP 版本

**Q: 找不到 tunl0 设备**
A: 加载内核模块：`sudo modprobe ipip`

**Q: 防火墙阻止**
A: 允许 IP 协议 4：`sudo iptables -A INPUT -p 4 -j ACCEPT`

## 注意

- Demo 仅用于学习测试
- 生产环境建议使用 Flannel、Calico、Cilium 等成熟方案
