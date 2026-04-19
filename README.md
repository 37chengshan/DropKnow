# DropKnow Project Skeleton

本目录根据《落知_信息架构_技术架构_数据表设计_前端设计.md》初始化为第一版工程骨架，供后续 Xcode 工程和 Swift 源码直接落位。

## 目录约定

- `App/`: App 入口、Router、Scene 装配
- `Features/`: 按业务能力拆分的用例、ViewModel、协调器
- `Shared/`: 设计系统、公共组件、工具与日志
- `Domain/`: 领域实体、枚举、值对象、协议
- `Infrastructure/`: 文件监听、数据库、解析器、Provider、系统能力接入
- `Resources/`: 资源与样例数据
- `Tests/`: 单测、集成测试、UI 测试

## 推荐先后顺序

1. 先补 `Domain/Enums` 与 `Domain/Entities`
2. 再实现 `Infrastructure/Database` 的 SQLite schema
3. 再接 `Features/Watcher -> Import -> Parsing -> PrivacyGate`
4. 最后补 `Summarization / Events / Search / Calendar / Notifications`

## 配套实施文档

- [/Users/cc/luozhi/docs/数据库迁移清单.md](/Users/cc/luozhi/docs/数据库迁移清单.md)
- [/Users/cc/luozhi/docs/Swift enum DTO 对照表.md](/Users/cc/luozhi/docs/Swift%20enum%20DTO%20对照表.md)
- [/Users/cc/luozhi/docs/Provider 输入输出契约.md](/Users/cc/luozhi/docs/Provider%20输入输出契约.md)
- [/Users/cc/luozhi/docs/ViewModel 状态映射表.md](/Users/cc/luozhi/docs/ViewModel%20状态映射表.md)
