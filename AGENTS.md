# ScholarAI Agent Map

## Purpose

为 AI 协作提供仓库地图级规则，确保改动落在正确边界、同步正确文档、执行最小验证。

## Repository Map

### 产品设计文档

- `mac下载文件自动理解助手_PRD_v1.md`: 产品范围、用户价值与版本边界
- `mac下载文件自动理解助手_roadmap.md`: 阶段规划与里程碑
- `落知_信息架构_技术架构_数据表设计_前端设计.md`: 工程骨架、数据表、模块职责
- `落知_状态机与错误码设计_v1.1.md`: 状态真集、错误码、恢复策略
- `落知_Prompt与JSONSchema_FewShot规范_v1.1.md`: Provider 输入输出与 Schema 真集
- `落知_SwiftUI组件规格与页面实现指南.md`: Scene、组件 Props、ViewModel 数据来源

### 实施输出文档

- `docs/数据库迁移清单.md`: SQLite 建表/改表/索引/状态迁移清单
- `docs/Swift enum DTO 对照表.md`: Swift 枚举、DTO、Record、ViewData 对照
- `docs/Provider 输入输出契约.md`: Summary/Event/QA 三类 provider 契约
- `docs/ViewModel 状态映射表.md`: 页面级 ViewModel 与状态/UI 映射

### 工程骨架

- `DropKnow/App/`: App 入口、Router、Scene 装配
- `DropKnow/Features/`: Watcher、Import、Parsing、PrivacyGate、Summarization、Events、Search、Calendar、Notifications、Subscription
- `DropKnow/Shared/`: 设计系统、组件、工具、扩展、日志
- `DropKnow/Domain/`: Entities、ValueObjects、Enums、Protocols
- `DropKnow/Infrastructure/`: FileWatching、Parsers、Database、Providers、Calendar、System
- `DropKnow/Resources/`: 资源与样例数据
- `DropKnow/Tests/`: Unit、Integration、UI Tests

## Boundary Rules

1. 改数据库结构时，先更新 `docs/数据库迁移清单.md`，再改 `DropKnow/Infrastructure/Database/`
2. 改状态枚举时，同时更新：
   - `落知_状态机与错误码设计_v1.1.md`
   - `docs/Swift enum DTO 对照表.md`
   - `docs/ViewModel 状态映射表.md`
3. 改 provider 输出字段时，同时更新：
   - `落知_Prompt与JSONSchema_FewShot规范_v1.1.md`
   - `docs/Provider 输入输出契约.md`
   - 对应 DTO/validator
4. 改组件 Props 或页面状态时，同时更新：
   - `落知_SwiftUI组件规格与页面实现指南.md`
   - `docs/ViewModel 状态映射表.md`
5. 不要把文件监听、解析、门禁、摘要、事件抽取、搜索、通知写成单个大服务；保持 feature 边界清晰

## Source of Truth

1. 状态真集：`落知_状态机与错误码设计_v1.1.md`
2. Provider Schema 真集：`落知_Prompt与JSONSchema_FewShot规范_v1.1.md`
3. 工程分层真集：`落知_信息架构_技术架构_数据表设计_前端设计.md`
4. UI Props 与 Scene 真集：`落知_SwiftUI组件规格与页面实现指南.md`

若多个文档冲突，优先按以上顺序收敛，并同步修正文档分歧。

## Minimal Verification

### 文档改动

- 检查是否同步到对应实施文档
- 检查枚举值是否前后一致
- 检查新增字段是否有入库位置、DTO 字段和 UI 消费方

### 代码改动

- 数据库层：至少验证 schema/迁移能创建目标表与索引
- Provider 层：至少验证 JSON parse、repair、schema validate 三段链路
- ViewModel 层：至少覆盖 loading、blocked、failed、partial success
- 状态相关改动：所有 switch 保持 exhaustive，不允许吞默认分支

## Working Style

1. 先读地图，再动手
2. 优先做最小闭环，不做横跨全仓的大而全重写
3. 发现设计口径冲突时，先修正文档真集，再继续代码实现
4. 任何新增目录或模块，都要能映射回现有 `DropKnow/` 分层
