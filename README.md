# DeskGPT 0.2 — macOS AI 工作台

原生 SwiftUI 桌面应用，适用于 macOS 14+。当前应用包为 Apple Silicon 版本。此项目是独立客户端。

## 使用

双击 `dist/DeskGPT.app`，打开侧栏「供应商与设置」，选择供应商，填写 API Key 并保存。模型 ID 和基础地址均可修改。通过「测试连接」发送一条短请求验证配置，可能产生供应商 API 用量。

```sh
./scripts/build-app.sh
open dist/DeskGPT.app
```

开发运行：`swift run DeskGPT`。核心测试：`./scripts/test.sh`。需要 Swift 6 / Command Line Tools。

## 新版功能

- 紧凑工作台：深色/浅色/跟随系统、项目侧栏、中央对话、可收起的文件面板。
- Project：创建、编辑、归档/恢复、移除时保留会话；工作目录、项目指令、默认供应商；现有对话可通过右键菜单移动到项目。
- Work：文件筛选、文本预览、逐个加入上下文、Markdown 与独立代码块、代码复制和另存为文件。
- 供应商：每家独立的地址、模型、API 协议和钥匙串凭据；全局默认、项目默认、对话内切换；连接测试。
- Chat：流式回复、停止、重新生成、搜索、复制、导出、⌘N 新对话、⌘Return 发送。
- 定时任务：一次/每小时/每天/每周、关联项目和供应商、启用/停用、立即运行、结果会话与状态。
- 插件：远程 HTTPS MCP 管理、逐次批准/拒绝与续传，适用于支持这些工具的 Responses 服务。

## 供应商预设

| 供应商 | 默认协议 | 配置说明 |
| --- | --- | --- |
| OpenAI | Responses | 保留旧版地址、模型和 Key |
| Anthropic | Claude Messages | 原生 Messages 请求与文本流 |
| Google Gemini | Chat Completions | Google 官方 OpenAI 兼容入口 |
| DeepSeek | Chat Completions | 可更换模型 ID |
| 通义千问 | Chat Completions | 默认北京兼容入口，按 Key 所属区域修改地址 |
| Ollama | Chat Completions | 本机 `localhost:11434`，无需 Key，模型需预先安装 |
| 自定义服务 | 可选三种协议 | 可配置其他兼容供应商或代理 |

联网搜索、云端代码解释器、远程 MCP 只在 Responses 协议下发送，其他协议不会套用 OpenAI 工具参数。远程地址必须使用 HTTPS，HTTP 仅允许 localhost / 127.0.0.1 / IPv6 本机地址。

API 参考：[DeepSeek](https://api-docs.deepseek.com/)、[Claude Messages](https://platform.claude.com/docs/en/build-with-claude/streaming)、[Gemini 兼容接口](https://ai.google.dev/gemini-api/docs/openai)、[千问兼容接口与区域地址](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[Ollama 兼容接口](https://docs.ollama.com/api/openai-compatibility)、[OpenAI Responses](https://developers.openai.com/api/reference/responses/overview)。

## 数据与目录

旧版 `library.json` 自动迁移：保留聊天、定时任务、插件以及旧 OpenAI 配置。原来的 OpenAI Key 继续使用原钥匙串条目；其他供应商分别保存，Key 不进入 JSON。

项目和会话存放于 `~/Library/Application Support/DeskGPT/library.json`。选择目录不上传文件。只有主动加入消息的文本内容和项目指令会发送到该对话所选的供应商。单个 UTF-8 文本文件限 100 KB，消息及附件合计限 500 KB。

macOS 目录访问受系统权限限制。无法读取时会提示原因；使用「重新选择目录」或项目设置里的文件夹选择器授权目录。选择器产生的目录书签随项目/会话保存。隐藏文件、符号链接、常见依赖目录不自动列出，文件列表上限 500。

## 当前边界

没有 ChatGPT 官方账号同步、语音/视频、图片生成、PDF/图片附件、Canvas、本地终端 agent、自动修改文件或补丁审阅。保存代码由用户主动选择路径完成。供应商的真实联网能力需要用户自己的 Key 和服务权限，已通过的是本地模拟协议测试。

定时任务要求应用运行且 Mac 唤醒；恢复后每项到期任务补跑一次，跳过重复历史时点。重复间隔按固定秒数计算，关闭应用后没有云端/LaunchAgent 调度。

MCP 当前不支持 OAuth 与本地 stdio。应用包为本地 ad-hoc 签名；正式跨机器分发还需要开发者签名与公证。


### 0.3 设置中心

设置现已分为通用、模型供应商、聊天、工作区、定时任务、插件、数据与隐私、快捷键及关于，支持关键词筛选。

- 通用：外观、启动页面、默认 Chat/Work 模式、文件面板、完成提示音。
- 聊天：消息和代码字号、内容宽度、时间戳、自动滚动、语言、指令、上下文长度、请求超时与内置工具。
- 工作区：单文件与消息总大小限制、文件数量、隐藏文件及排除目录。
- 定时任务：调度开关、补跑策略、自动任务并发。应用退出期间无法执行任务。
- 插件：MCP 总开关和往返上限；每次调用仍需审批。
- 供应商：新增、复制和修改显示名称；复制不复制钥匙串凭据。
- 数据：导出 JSON 完整备份（不含 API Key）、打开数据目录、恢复默认偏好。
- 关于：版本及不含聊天内容或凭据的诊断摘要。

这些选项自动保存。请求相关设置在下一次发送时生效；启动页面在重启时生效。备份导出尚不提供界面导入。


### 0.4 图片创作

左侧「创作空间」或聊天输入框的「图片」入口可打开图片创作。输入描述，选择图片供应商与图片模型后点击生成。原有文字聊天不会自动转换为生图请求。

- 文字生成图片：品牌海报、插画、产品摄影、图标快捷模板。
- 参考图编辑：上传一张 PNG/JPEG/WebP，描述修改内容；支持把已有作品作为参考图继续创作。
- 参数：正方形、横向、纵向、自动尺寸，1–4 张。OpenAI 图片接口支持质量与透明背景选项；千问不发送这些参数。
- 图库：自动保存 PNG 与提示词、模型、供应商、创建日期及项目关联；支持预览、复制、另存为、搜索、项目筛选及删除。
- 取消与错误：停止请求、清晰展示模型权限或服务错误；提示词与参考图保留，可重试。

支持的图片协议：

1. OpenAI/GPT Image 兼容 Images API：`images/generations` 与 `images/edits`，接收 `b64_json`。默认 `gpt-image-1.5`；可选择预设或自定义模型。使用供应商基础地址和独立钥匙串凭据。
2. 通义千问原生图片 API：`/api/v1/services/aigc/multimodal-generation/generation`，默认 `qwen-image-2.0-pro`，支持生成和参考图编辑。沿用所选百炼供应商地址的区域主机和 Key，自动去掉文字兼容接口路径。参考图上限 10 MB；生成的临时图片 URL 会立即下载保存，下载时不携带 API Key。

图片模型权限及用量由供应商账户决定。Gemini、Anthropic 原生图片协议以及视频、语音创作尚未接入。通用参考图上限 20 MB；作品位于数据目录下 `artworks`。JSON 备份包含图库索引，不含图片文件，图片需要另行保存。

接口依据：[OpenAI Images](https://developers.openai.com/api/reference/resources/images/methods/generate)、[OpenAI 图片编辑](https://developers.openai.com/api/reference/python/resources/images/methods/edit)、[千问文生图](https://help.aliyun.com/zh/model-studio/qwen-image-api)、[千问图片编辑](https://help.aliyun.com/zh/model-studio/qwen-image-edit-api)。


### 0.5 聊天内自动模型路由

直接在普通聊天中请求“画一只猫”“生成海报”或“把上一张图换成水彩”，后台路由模型结合最近对话决定文字回答、图片生成或参考图编辑，自动调用对应图片模型。图片显示在同一个聊天中，支持保存与复制；消息关联与作品文件在重启后保留。

原有独立创作表单已移除，侧栏改为「作品图库」，手动图片参数移至「设置 → 自动创作」的高级配置。聊天顶部显示「自动」，不再要求用户手动选择图片模型。

- 路由使用当前文字供应商模型，每条请求增加一次短意图判断请求及相应用量/延迟。
- “写提示词”“解释生图方法”“不要生成”等请求按文字处理；该分类依赖模型判断。
- 同一消息可添加一张图片作为编辑参考，支持 PNG/JPEG/WebP。续聊编辑自动使用该聊天上一张生成图片。
- 图片供应商优先使用后台配置；没有凭据时尝试已配置的 OpenAI/千问。接口错误会在聊天中展示，不自动重复生图。
- 原有图库继续保留；图库的“继续编辑”返回普通聊天并挂入作品上下文。
- 当前图片附件用于创作/编辑，图片内容问答尚未接入。视频与语音模型路由尚未接入。

0.4 的手动创作操作说明已被上述聊天流程替代。
