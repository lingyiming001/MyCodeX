# 开发说明

## 结构

- `Models.swift`：Project、供应商预设、三种协议、会话、调度与向后兼容迁移。
- `Services.swift`：按供应商隔离的钥匙串、原子持久化、Responses SSE 与 MCP 审批。
- `CompatibleClient.swift`：Chat Completions / Claude Messages 请求、鉴权、SSE 与地址验证。
- `Store.swift`：主线程状态、Project 操作、项目上下文继承、文件授权、并发会话与调度。
- `Theme.swift`：适应外观的颜色、按钮、导航与排版。
- `App.swift`：工作台布局、侧栏、面包屑与模型切换。
- `ChatView.swift`：输入、消息/代码块、文件面板和预览。
- `ProjectViews.swift`：项目总览、详情与编辑。
- `ProviderViews.swift`：供应商配置、连接测试和应用偏好。
- `ManagementViews.swift`：任务与 MCP。

`ViewState` 类型别名避开当前 Command Line Tools 中同名 SwiftUI State 宏的组件缺失。

## 检查

`./scripts/test.sh` 是独立 Swift 测试程序，不依赖 XCTest，使用 URLProtocol 模拟网络。覆盖三个协议的请求、鉴权和流式解析、MCP 批准/拒绝续传、断流与 HTTP 错误、本机地址规则、旧数据迁移、项目继承、编辑/归档/移动/移除、文件列举与读取，以及原有持久化和调度。

真实供应商调用、系统钥匙串真实凭据与外部 MCP 需用户配置后联调；测试不会读取或发送真实 Key。

## 后续重点

Work agent 的受限终端、取消/超时、工具日志、补丁预览与审批；MCP OAuth/stdin；后台调度与通知；模型列表与上下文压缩；语音及多模态；数据加密、签名、公证和更新机制。
