# Hermes Traffic Light 🚦

为 [Hermes Agent](https://hermes-agent.nousresearch.com) 打造的物理交通灯 —— 通过 ESP32-C3 上的 RGB LED 实时显示 Agent 状态。

```
🟢 绿灯闪烁 → Agent 正在处理你的消息
🔴 红灯闪烁 → Agent 等待你批准命令
🟡 黄灯常亮 → Agent 空闲 / 已完成
```

基于 [Hermes Shell Hooks](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks) 实现 —— 灯在框架层面自动切换，零工具调用开销。

> **Fork 自 [eternityspring/agent-light](https://github.com/eternityspring/agent-light)** —— 原始的 Claude Code 物理交通灯项目。本 fork 将其适配为 Hermes Agent，使用 Python 桥接 + 原生 Shell Hook 集成。

## 硬件

需要三样东西，淘宝/拼多多均可买到，总价约 ¥30：

| # | 物品 | 搜索关键词 | 参考价 |
|---|------|-----------|--------|
| 1 | ESP32-C3 开发板 (Type-C) | [淘宝搜 "ESP32-C3 开发板 Type-C"](https://s.taobao.com/search?q=ESP32-C3+%E5%BC%80%E5%8F%91%E6%9D%BF+Type-C) | ~¥15-20 |
| 2 | LED 交通灯模块 | [淘宝搜 "LED 交通信号灯 模块"](https://s.taobao.com/search?q=LED+%E4%BA%A4%E9%80%9A%E4%BF%A1%E5%8F%B7%E7%81%AF+%E6%A8%A1%E5%9D%97) | ~¥1-3 |
| 3 | 杜邦线 母对母 | [淘宝搜 "杜邦线 母对母 10cm"](https://s.taobao.com/search?q=%E6%9D%9C%E9%82%A6%E7%BA%BF+%E6%AF%8D%E5%AF%B9%E6%AF%8D+10cm) | ~¥2 |

> 推荐 XIAO ESP32C3 或合宙 ESP32-C3 开发板，体积小巧，Type-C 接口方便。
> 如使用普通 ESP32（非 C3），修改固件中的 GPIO 引脚定义即可。

### 接线

用杜邦线将交通灯模块连接到 ESP32-C3：

| 模块引脚 | ESP32-C3 引脚 | GPIO |
|---------|-------------|------|
| R (红灯) | GPIO2 | 2 |
| Y (黄灯) | GPIO1 | 1 |
| G (绿灯) | GPIO0 | 0 |
| VCC | 5V (或 3.3V) | — |
| GND | GND | — |

> ⚠️ 交通灯模块已内置限流电阻，无需外接电阻。
> ⚠️ 模块为共阴设计 —— `HIGH` 点亮，`LOW` 熄灭。

## 两种模式

支持 **本地模式**（灯和 Hermes 在同一台机器）和 **远程模式**（灯在另一台机器，通过 Tailscale/LAN 连接）。

### 本地模式

```
Hermes (本机) → hook → 串口 → USB → ESP32-C3 → 灯
```

灯直接插在运行 Hermes 的电脑上。最简单的方案。

### 远程模式

```
Hermes (台式机) → hook → curl → Tailscale/LAN → API 服务器 (笔记本) → 串口 → USB → 灯
```

灯插在另一台机器上（比如你的笔记本），Hermes hooks 通过 Tailscale 发送 HTTP 请求到灯所在机器的 API 服务器。

**为什么用远程模式？** Hermes 跑在无头服务器上（机柜/云端），但你想让灯放在你身边（笔记本旁）。

## 快速开始 — 本地模式

```bash
# 1. 安装依赖
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=~/.local/bin sh
~/.local/bin/arduino-cli core update-index
~/.local/bin/arduino-cli core install esp32:esp32
pip3 install pyserial
sudo usermod -a -G dialout $USER

# 2. 克隆并设置
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
bash scripts/setup.sh

# 3. 重启 Hermes gateway（在另一个终端执行）
hermes gateway restart
```

## 快速开始 — 远程模式

### 灯所在机器（比如你的笔记本）：

```bash
# 1. 安装 Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. 克隆并安装依赖
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
pip3 install pyserial
sudo usermod -a -G dialout $USER

# 3. 刷固件（插入 ESP32-C3 USB-C）
bash scripts/setup.sh   # 刷固件 + 测试 LED

# 4. 启动 API 服务器
python3 scripts/traffic_light_server.py --port 9090

# 记下 Tailscale IP：
tailscale ip -4
# → 例如 100.64.0.2
```

### Hermes 所在机器（比如你的台式机）：

```bash
# 1. 安装 Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. 克隆并以远程模式设置
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
bash scripts/setup.sh --remote --light-host 100.64.0.2 --light-port 9090

# 3. 重启 Hermes gateway（在另一个终端执行）
hermes gateway restart
```

## 工作原理

```
你发送消息
  → Hermes 触发 pre_llm_call
    → hook 脚本 curl API / 发送串口命令
      → 🟢 绿灯闪烁

Agent 想执行 sudo/rm 等命令
  → Hermes 触发 pre_approval_request
    → hook 脚本 curl API / 发送串口命令
      → 🔴 红灯闪烁

Agent 完成回复
  → Hermes 触发 post_llm_call
    → hook 脚本 curl API / 发送串口命令
      → 🟡 黄灯常亮
```

### Hook 事件映射

| Hermes 事件 | 命令 | 灯光 | 含义 |
|-------------|---------|------|------|
| `pre_llm_call` | `working` | 🟢 绿灯闪烁 | Agent 处理中 |
| `pre_approval_request` | `waiting` | 🔴 红灯闪烁 | 等待用户批准 |
| `post_llm_call` | `idle` | 🟡 黄灯常亮 | Agent 空闲 |

Hook 脚本以后台子进程运行 —— 永远不会阻塞 Agent。

## 手动控制

```bash
# 本地（直接串口）
python3 scripts/traffic_light.py working  # 绿灯闪烁
python3 scripts/traffic_light.py waiting  # 红灯闪烁
python3 scripts/traffic_light.py idle     # 黄灯常亮
python3 scripts/traffic_light.py test     # 循环 R→Y→G

# 远程（通过 API）
curl http://100.64.0.2:9090/working
curl http://100.64.0.2:9090/waiting
curl http://100.64.0.2:9090/idle
curl http://100.64.0.2:9090/test
curl http://100.64.0.2:9090/ping
```

## Python API

```python
from traffic_light import TrafficLight

tl = TrafficLight()
tl.working()   # 绿灯闪烁
tl.waiting()   # 红灯闪烁
tl.idle()      # 黄灯常亮
tl.close()

# 上下文管理器（退出时自动切回 idle）：
with TrafficLight() as tl:
    tl.working()
    # ... agent 工作 ...
```

## 远程 API 服务器

在插着 USB 交通灯的机器上运行：

```bash
python3 scripts/traffic_light_server.py              # 默认端口 9090
python3 scripts/traffic_light_server.py --port 8888  # 自定义端口
TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 scripts/traffic_light_server.py  # 手动指定串口
```

### 端点

| 端点 | 效果 |
|----------|--------|
| `GET /working` | 🟢 绿灯闪烁 |
| `GET /waiting` | 🔴 红灯闪烁 |
| `GET /idle` | 🟡 黄灯常亮 |
| `GET /off` | 全部熄灭 |
| `GET /test` | 循环 R→Y→G |
| `GET /status` | 查询当前状态 |
| `GET /ping` | 健康检查 |

### Systemd 服务（开机自启）

```bash
# 复制并编辑服务文件
cp scripts/traffic-light-api.service ~/.config/systemd/user/
sed -i "s|HOME_DIR|$HOME|g" ~/.config/systemd/user/traffic-light-api.service

# 启用开机自启（登录前即启动）
loginctl enable-linger

# 启用并启动
systemctl --user daemon-reload
systemctl --user enable traffic-light-api.service
systemctl --user start traffic-light-api.service
```

## 项目结构

```
agent-light/
├── firmware/
│   ├── traffic_light/traffic_light.ino # 主固件（串口命令处理）
│   └── diagnostic/diagnostic.ino       # 引脚诊断工具
├── hermes-hooks/
│   ├── traffic-light-working.sh        # pre_llm_call → 绿灯
│   ├── traffic-light-waiting.sh        # pre_approval_request → 红灯
│   └── traffic-light-idle.sh           # post_llm_call → 黄灯
├── scripts/
│   ├── traffic_light.py                # 串口桥接（CLI + Python API + 守护进程）
│   ├── traffic_light_server.py         # 远程 API 服务器（HTTP → 串口）
│   ├── traffic-light-api.service       # API 服务器的 Systemd 单元文件
│   └── setup.sh                        # 一键安装脚本（本地 + 远程模式）
├── images/                             # 上游项目原始图片
└── README.md
```

## 故障排查

### 找不到串口

```bash
ls /dev/ttyACM* /dev/ttyUSB*
# 空？重新拔插 USB-C 线。
# 还是空？按住 BOOT 按钮，按一下 RESET，然后松开 BOOT（进入烧录模式）。
```

### 权限拒绝

```bash
groups | grep dialout
# 如果没有：
sudo usermod -a -G dialout $USER
# 然后重新登录（或临时救急：sudo chmod 666 /dev/ttyACM0）
```

### 只有一个 LED 亮

GPIO 引脚映射不对。运行诊断固件：

```bash
~/.local/bin/arduino-cli compile --fqbn esp32:esp32:XIAO_ESP32C3 firmware/diagnostic/diagnostic.ino
sg dialout -c "~/.local/bin/arduino-cli upload --fqbn esp32:esp32:XIAO_ESP32C3 --port /dev/ttyACM0 firmware/diagnostic/diagnostic.ino"
# 观察每一步哪个 LED 亮起
# 然后在 firmware/traffic_light/traffic_light.ino 中修改引脚定义
```

### 无法连接远程 API 服务器

```bash
# 检查 Tailscale 连接
tailscale status

# 检查 API 服务器是否运行
curl http://100.64.0.2:9090/ping

# 检查防火墙
sudo ufw allow 9090/tcp  # 如果 ufw 启用的话
# Fedora: sudo firewall-cmd --add-port=9090/tcp --permanent && sudo firewall-cmd --reload
```

### Hooks 没有触发

```bash
hermes hooks list       # 应该显示 3 个 hook，全部 ✓ allowed
hermes gateway restart  # 配置修改后重新加载
```

### 手动指定串口

```bash
TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 scripts/traffic_light.py test
```

## 致谢

- **原始项目**: [eternityspring/agent-light](https://github.com/eternityspring/agent-light) by [@eternityspring](https://github.com/eternityspring)
- **Hermes 适配**: [BruceBest/agent-light](https://github.com/BruceBest/agent-light) (本 fork)

## 许可证

MIT
