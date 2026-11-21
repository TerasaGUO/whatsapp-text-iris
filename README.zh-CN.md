# IRIS 的 WhatsApp 文本收发适配器

[English](README.md) | [简体中文](README.zh-CN.md)

在 InterSystems IRIS 互操作 Production 中接收 WhatsApp Business 文本，并回复一条可配置的确认消息。项目的六个 ObjectScript 类分别实现 REST Webhook、消息类型、业务服务、业务操作、Graph HTTP 适配器和示例 Production。订阅验证、HMAC-SHA256 验签、事件筛选与投递均在 IRIS 内完成。Python 仅用于本地 HTTP 测试客户端和模拟 Graph 端点。

## 运行本地演示

安装 Docker 并获取 IRIS for Health Community 2026.2 镜像，在项目根目录执行以下命令。若使用其他兼容的镜像，可通过 `IRIS_IMAGE` 指定。

```sh
./tests/local-check.sh
```

脚本启动禁用外部网络的一次性容器，退出时移除容器。它编译 ObjectScript 类、注册测试 REST 应用、启动测试 Production，再通过 IRIS Web Gateway 发起真实的 HTTP 请求。测试使用合成凭据与虚构号码，运行时无需安装 Python 依赖包。

测试覆盖正确与错误的订阅验证、错误或缺失签名、异常 JSON、媒体与状态通知、其他业务号码和请求大小限制。测试将含两条中文文本的签名批次投递两次，再发送第三条文本。三条不同的消息均经过真实 IRIS 队列和出站 HTTP 适配器。回环 Graph 服务核对目标路径、接收号码及回复正文。最后脚本停止 Production 并验证新的回调返回 HTTP 503。

```text
PASS: ObjectScript REST, 5 signed texts, 3 distinct Graph replies, stopped production -> 503
```

## 安装到 IRIS

1. 准备已启用互操作功能的独立命名空间，配置 InterSystems Web Gateway，并确认该项目可以使用实例级 Web 应用路径 `/wa-text`。使用 InterSystems Package Manager（IPM）0.10.10 时，将仓库挂载到 `/app`，在目标命名空间的 IRIS 终端执行：

   ```objectscript
   zpm "load /app"
   ```

   IPM 将编译六个 `WaText` 类并配置 REST 应用。若所配置的 IPM 仓库已收录此包，也可在同一命名空间执行 `zpm "install whatsapp-text-iris 1.0.0"`。如需手动安装，可执行 `do $system.OBJ.LoadDir("/app/src","ck",,1)` 导入源代码类，再按照第 3 步创建 Web 应用。

2. 启动 IRIS 实例前，在实例环境中配置以下密钥和标识，确保 Webhook 与业务操作的工作进程均可读取。

   | 环境变量 | 用途 |
   |---|---|
   | `WA_VERIFY_TOKEN` | 在 Meta 订阅配置中填写的私有验证令牌 |
   | `WA_APP_SECRET` | 用于校验 Webhook 请求体签名的 Meta 应用密钥 |
   | `WA_PHONE_ID` | 用于筛选通知的数字业务号码 **ID** |
   | `WA_ACCESS_TOKEN` | 具有从此业务号码发信权限的 WhatsApp 访问令牌 |

3. 在管理门户 **System Administration → Security → Applications → Web Applications** 中检查 IPM 创建的 `/wa-text` 应用；手动安装时在此创建应用。命名空间选择 Production 所在的命名空间，分派类填写 `WaText.Webhook`，启用匿名访问（Meta 通过签名验证 POST 请求），关闭静态文件服务。IPM 将目标命名空间的全局数据库角色授予此应用的请求。手动安装时请在 **Application Roles** 中指定相应角色。如果配置了额外的数据库映射，还需确认应用能执行相关类并写入消息队列。
4. 通过 Web Gateway 路由 `/wa-text/webhook`。接入真实 Meta 回调时，用 HTTPS 发布该路径，保持请求体原始字节与 `X-Hub-Signature-256` 头原样传递。订阅验证会在查询参数中传送私有令牌，请配置访问日志省略查询字符串。若已有公网 `/webhook` 地址，可通过反向代理映射到内部的 `/wa-text/webhook`。
5. 配置 IRIS 出站客户端 TLS 配置文件，使用受信任的 CA 证书包，将服务器证书验证设为 **Required**。在管理门户打开 `WaText.Production`，选择 **WhatsApp Reply**。将适配器 **TLSConfig** 设为 TLS 配置名称，**PhoneId** 设为与 `WA_PHONE_ID` 一致的数字标识，**GraphVersion** 填写 Meta 应用支持的版本。通过操作设置 **ReplyText** 自定义确认文本，应用更改并启动 Production。
6. 在 Meta 的 WhatsApp 设置中填写公网回调 URL 和相同的订阅验证令牌。订阅 WhatsApp Business Account 的 `messages` 字段，确认应用已订阅你的业务账号，并为测试号码启用指定收件人。

## 跟踪一条消息

用获准的手机向业务测试号码发送文本。在 IRIS 消息查看器中打开 **WhatsApp Input** 到 **WhatsApp Reply** 的会话，查看传入的 Meta 消息 ID、发送方和正文。按默认配置，手机应收到 **Thanks, your text reached IRIS.** Graph 返回消息 ID 表示 Meta 已接受请求，实际送达情况请在手机上核实。本地演示使用模拟 Graph 端点验证原生 REST 和 Production 组件，真机联调需要已配置的 Meta 账号。

`WaText.Webhook` 在解析 JSON 前验证原始请求体签名，然后校验整个批次，筛选发往配置业务号码的文本。所有选中的消息均进入 IRIS 队列后才返回 HTTP 200。中途入队失败时返回 HTTP 503，供 Meta 重投批次。业务操作按入站消息 ID 加锁，调用远端前持久化回执，已完成的回执会阻止重复发送。发送失败或结果不明确时，回执保留为待核对状态，并在 Production 事件日志中记录错误。管理员确认 Graph 未接受该次发送后，可在 Production 命名空间清除对应的单条待核对回执，再重新提交消息。应在 Meta 的重新投递窗口内保留回执，并限制访问消息查看器中的发送方标识与正文。

## 参考资料

[Meta Webhooks](https://developers.facebook.com/docs/graph-api/webhooks/getting-started/) · [WhatsApp Business Platform](https://developers.facebook.com/documentation/business-messaging/whatsapp/overview) · [InterSystems %CSP.REST](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?CLASSNAME=%25CSP.REST) · [社区悬赏题目](https://ideas.intersystems.com/ideas/DPI-I-882)
