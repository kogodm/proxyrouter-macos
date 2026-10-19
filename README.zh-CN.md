# ProxyRouter for macOS

[English](README.md) · **简体中文** · [Русский](README.ru.md)

**Mac 上的本地按应用分流代理路由器。** 给每个应用单独选一条网络路径：一个应用走 SOCKS5/HTTP 代理，另一个走 VPN 隧道，其余直连，或者直接拦截。全部同时生效，不用来回切换。

**官网与下载：<https://proxyrouter.app>**

> 本仓库只放文档。ProxyRouter 是闭源软件，通过上面的官网以签名并公证的 DMG 分发。

![应用页：每个应用单独选择路径](docs/apps.png)

## 它解决什么问题

macOS 只有一条默认路由和一个系统代理开关。服务器 VPN、客户内网 VPN 和本地代理（Clash、sing-box、公司网关）同时开着时会互相打架，你一天都在开开关关。

ProxyRouter 在**连接建立的那一刻，按应用**决定它走哪条路。几个 VPN 和代理可以同时在线，每个应用各走各的。

典型分配：

| 应用 | 路径 |
|---|---|
| 终端（SSH、rsync、kubectl） | 服务器机房 VPN 隧道 |
| 数据库客户端、Git 客户端 | 客户内网 VPN 隧道 |
| 浏览器、AI 工具、包管理器 | 本地代理（SOCKS5/HTTP） |
| Slack、系统更新、局域网应用 | 直连 |
| 必须保持离线的应用 | 拦截（被拦下的尝试仍可见） |

分步指南：[在 Mac 上同时使用多个 VPN 和代理](https://proxyrouter.app/multiple-vpn-proxy-at-once-macos)

## 功能

- **按应用分流**，上游为 SOCKS5 或 HTTP。按图标选应用，不用手输进程名。
- **自动检测 VPN 隧道。** VPN 一连上，就会出现在任何应用的路径选项里。
- **UDP 与 QUIC。** 支持 SOCKS5 UDP ASSOCIATE；QUIC 有三种明确状态：走代理、强制回落 TCP、直连。
- **查看每个应用访问过的所有地址。** 「活动」页按应用列出它连过的全部主机，并实时更新。见[下文](#查看每个应用访问过的所有地址)。
- **拦截规则。** 直接关闭某个应用的连接，被拦下的尝试仍会列出来。
- **按网络自动切换 profile。** Wi-Fi 按 SSID，有线按网关 MAC 加网段。
- **每条连接都可解释。** 每条连接都显示命中了哪条规则、为什么；规则试算器可以不发包就回答同样的问题。
- **防泄漏。** 处理 WebRTC/UDP 和 DNS 泄漏，并提供 [DNS 检测](#dns-检测dns-和网络出口是否一致)，核对 DNS 解析器与网络出口是否一致。
- **自动化。** `proxyrouterctl` 命令行、URL scheme、App Intents，以及给 LLM 代理用的内置 MCP server。

## 查看每个应用访问过的所有地址

不确定某个应用到底在连什么？打开 **Activity（活动）** 页。**By App** 按应用分组，每个应用都能展开成它连接过的全部主机列表；**Live** 实时显示正在发生的连接；搜索框可以按应用或主机过滤。

![活动页：ChatGPT 和 Claude 连接的所有主机，每个都能一键 Add to Proxy](docs/activity.png)

- 每个应用都带有当前状态（**Direct** 直连、**Proxied** 已走代理），一眼就能看出哪些应用没经代理就连出去了。
- 每个主机后面都有 **Add to Proxy** 按钮：发现某个地址应该走代理，点一下就生效。
- 仍然直连的应用有 **Route via Proxy** 按钮：点一下，整个应用改走代理。
- 每条连接都可以展开，看到命中了哪条规则、为什么。被拦截的应用，被拦下的尝试仍会列出来，让你看到它原本要去哪。

适合在决定某个 AI 工具、更新程序或不认识的后台进程该走哪条路之前，先搞清楚它实际连了哪些地址。

## DNS 检测：DNS 和网络出口是否一致？

代理能隐藏你的 IP，却仍可能通过 DNS 暴露你的位置。比如流量从美国出口，背后的 DNS 查询却由新加坡的解析器应答，或者回到了你自己所在的国家，网站和 DNS 运营方看到的就是两个不同的位置。ProxyRouter 专门检查这件事：**应答你 DNS 查询的解析器，和你的网络出口是否在同一个地方**，并在「代理」页每个代理下面直接告诉你结果。

![代理下方的 DNS 检测结果：代理链 DNS 在新加坡，当前节点在美国](docs/dns-check.png)

它分开报告三个观测值，方便你判断问题出在哪一环：

1. **本机 DNS。** 不经过代理发起随机域名查询，作为你自己网络的基线。
2. **代理链 DNS。** 同样的查询交给你的代理去解析。如果代理入口是 `127.0.0.1`（例如 Clash、Mihomo），这里测到的是它背后整条链路的最终行为。
3. **当前节点出口。** 经同一代理链得到的公网出口。

判定结果：

- **正常。** 解析器和出口一致。
- **位置不一致。** 解析器和出口在不同国家，但并不是你的真实位置。
- **泄漏。** 解析器，或它转发的客户端网段，指回了你自己的网络，而出口在国外。

原理：ProxyRouter 生成一个从未出现过的随机子域名，把**域名本身**交给代理，本地不做解析。权威 DNS 服务器会记下是哪个解析器来查询，ProxyRouter 再把这个解析器的位置和出口的位置做对比。代理入口是 `127.0.0.1` 时，异常会归因到本机代理客户端的 DNS 设置，而不是直接怪到远端服务器头上。

打开「代理」页会自动检测（结果缓存 30 分钟）。点击那一行、右键菜单或「测试全部」可以重新检测。终端里用 `proxyrouterctl proxy dns-check [名称]`（加 `--json` 方便脚本）。LLM 代理可以调用只读的 MCP 工具 `check_proxy_dns`。

## 它不是什么

- 不是 VPN，也不是代理服务。没有服务器、带宽、IP 地址、节点列表，也没有能授予网络访问的账号。VPN 客户端和 SOCKS5/HTTP 上游都要你自己准备。
- 它不隐藏你的身份，也不用于绕过地域限制，我们也不这样宣传。

## 系统要求

macOS 13 或更高，Apple Silicon 与 Intel。详情：[系统要求](https://proxyrouter.app/system-requirements)。

## 安装

### 一条命令

```sh
curl -fsSL https://raw.githubusercontent.com/kogodm/proxyrouter-macos/main/install.sh | bash
```

脚本（[`install.sh`](install.sh)，很短，建议先读一遍）会：

1. 通过 HTTPS 从 `https://proxyrouter.app/downloads/ProxyRouter.dmg` 下载当前发布版的 DMG。
2. 只读挂载，并校验：代码签名有效、bundle id 是 `com.proxyrouter.app`、签名团队与预期一致、Gatekeeper 认可该应用（已公证）。任何一项不通过就不安装。
3. 把 `ProxyRouter.app` 拷到 `/Applications` 并打开。

使用已下载的脚本时可用的参数：

```sh
./install.sh --dir ~/Applications   # 装到别处
./install.sh --dmg ~/Downloads/ProxyRouter.dmg   # 使用你已有的 DMG
./install.sh --no-open              # 装完不启动
./install.sh --force                # ProxyRouter 正在运行时也替换
```

如果你的账号对 `/Applications` 没有写权限，请用 `--dir ~/Applications`，或加 `sudo` 运行。脚本不会替换正在运行的应用：请先退出 ProxyRouter。装好之后应用会在应用内自动更新，不需要再运行脚本。

### 手动安装

从 <https://proxyrouter.app/download> 下载 DMG，打开后把 **ProxyRouter** 拖进「应用程序」。它使用 Developer ID 证书签名，并经过 Apple 公证。

提供完整功能的免费试用，无需信用卡。

## 首次启动

1. 打开 ProxyRouter。macOS 会请你允许它的网络系统扩展，批准一次即可。
2. 如果 macOS 询问是否允许 DNS 代理配置，点 **Allow**。
3. 侧边栏底部的开关显示 **Running**，表示分流已生效。

## 使用

1. **「代理」页。** 添加你的 SOCKS5 或 HTTP 上游（本机的 Clash 端口、公司网关）。已连接的 VPN 隧道会出现在 **VPN tunnels (detected automatically)** 下。
2. **「应用」页。** 为每个应用打开路径菜单，选一个代理、一条 VPN 隧道，或者 **Block**。没有选择的应用直连。
3. **「活动」页。** 查看结果：每条连接都显示它走的路径和命中的规则。
4. **「配置」页。** 把 profile 绑定到某个网络（Wi-Fi 的 SSID，或有线网关），在那里自动生效。

钉到 VPN 上的应用只能访问该 VPN 路由到的地方。如果 VPN 只推内网路由，该应用访问公网的连接会失败而不是泄漏；VPN 断开时，该应用的连接会失败，而不是改走别的路径。

脚本与自动化：`proxyrouterctl` 命令行、URL scheme、App Intents 和内置 MCP server。详见 <https://proxyrouter.app>。

## 指南

- [macOS 按应用分流代理：工作原理](https://proxyrouter.app/per-app-proxy-macos)
- [让单个应用走代理](https://proxyrouter.app/route-app-through-proxy-macos)
- [让应用不走 VPN（分流隧道）](https://proxyrouter.app/exclude-apps-from-vpn-macos)
- [同时使用多个 VPN 和代理](https://proxyrouter.app/multiple-vpn-proxy-at-once-macos)
- [在 macOS 上代理 UDP 和 QUIC](https://proxyrouter.app/proxy-udp-quic-macos)
- [在 macOS 上使用 SOCKS5 代理](https://proxyrouter.app/socks5-proxy-macos)
- [Mac 上的 Proxifier 替代品](https://proxyrouter.app/proxifier-alternative-mac)

## 支持

问题和 bug 反馈：[support@proxyrouter.app](mailto:support@proxyrouter.app)，或在本仓库提 issue。

---

© 2026 ProxyRouter。保留所有权利。[proxyrouter.app](https://proxyrouter.app)
