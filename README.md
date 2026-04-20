# DropKnow

本仓库是 DropKnow 的 macOS 工程主仓，按《落知_信息架构_技术架构_数据表设计_前端设计.md》分层实现。

## 目录约定

- `App/`: App 入口、Router、Scene 装配
- `Features/`: 按业务能力拆分的用例、ViewModel、协调器
- `Shared/`: 设计系统、公共组件、工具与日志
- `Domain/`: 领域实体、枚举、值对象、协议
- `Infrastructure/`: 文件监听、数据库、解析器、Provider、系统能力接入
- `Resources/`: 资源与样例数据
- `Tests/`: 单测、集成测试、UI 测试

## 当前启动入口

- 主入口：`DropKnow/DropKnowApp.swift`
- 旧占位入口（非 @main）：`DropKnow/MainApp.swift`
- 主窗口容器：`DropKnow/App/DropKnowMainWindowView.swift`
- 依赖装配容器：`DropKnow/App/DropKnowV1Container.swift`

## 推荐先后顺序

1. 先补 `Domain/Enums` 与 `Domain/Entities`
2. 再实现 `Infrastructure/Database` 的 SQLite schema
3. 再接 `Features/Watcher -> Import -> Parsing -> PrivacyGate`
4. 最后补 `Summarization / Events / Search / Calendar / Notifications`

## 配套实施文档

- `docs/数据库迁移清单.md`
- `docs/Swift enum DTO 对照表.md`
- `docs/Provider 输入输出契约.md`
- `docs/ViewModel 状态映射表.md`

## 快速验证

```bash
cd /Users/cc/Desktop/DropKnow
swift build
swift test
```
