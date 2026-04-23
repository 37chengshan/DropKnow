# DropKnow Entitlements 说明

本文档说明 DropKnow 应用所使用的 macOS entitlements（权限配置）。

## Entitlements 列表

```xml
<key>com.apple.security.app-sandbox</key>
<false/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.calendar</key>
<true/>
```

## 各 Entitlement 用途说明

### com.apple.security.app-sandbox

- **用途**: 启用或禁用 App Sandbox（应用沙盒）
- **当前值**: `false`（未启用）
- **说明**: App Sandbox 是 macOS 提供的安全隔离机制，限制应用对系统资源的访问能力。禁用沙盒后，应用具有提升的权限，可以更自由地访问文件系统、网络和其他系统资源。

### com.apple.security.files.user-selected.read-write

- **用途**: 允许应用访问用户通过文件选择对话框主动选择的文件和文件夹
- **当前值**: `true`（已启用）
- **说明**: 此 entitlement 使 DropKnow 能够在用户授权后读取和写入用户选定的文件和目录。这是应用处理用户文档的核心前提。

### com.apple.security.calendar

- **用途**: 允许应用访问用户的日历数据
- **当前值**: `true`（已启用）
- **说明**: 此 entitlement 使 DropKnow 能够读取和写入日历事件，支持将文档与日历提醒关联、到期日提醒等功能。

## 为什么不启用沙盒

DropKnow 当前禁用了 App Sandbox（`com.apple.security.app-sandbox: false`），原因如下：

1. **文件系统访问的灵活性**: 作为文档管理工具，DropKnow 需要对用户选定的文件进行深度操作。启用沙盒会严格限制文件访问路径，增加实现复杂度。

2. **日历集成的完整性**: 沙盒环境对日历框架（EventKit）的访问有额外限制，禁用沙盒确保日历功能的稳定运行。

3. **开发和调试便利**: 开发阶段禁用沙盒可以减少权限相关的调试成本。

> 注意: 如果未来考虑将应用发布到 Mac App Store，则必须启用沙盒并重新设计相关功能以符合 App Store 的沙盒要求。

## 权限对用户的意义

| 权限 | 用户收益 |
|------|----------|
| 文件读写 | DropKnow 可以管理和整理用户的文档文件 |
| 日历访问 | 支持文档到期提醒、日程关联等功能 |

权限说明对用户的意义在于**透明度和信任**：

- 用户可以清楚了解应用需要哪些系统权限以及为何需要
- 权限是按需申请的，不会获取不必要的系统访问能力
- 未启用沙盒意味着应用运行时需要用户授权上述权限
