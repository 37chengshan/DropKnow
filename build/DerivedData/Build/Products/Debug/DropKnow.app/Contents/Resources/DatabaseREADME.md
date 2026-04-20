# DropKnow Database (SQLite + FTS5)

本目录提供 DropKnow V1 本地数据层的可运行落地版本，覆盖：

- 完整 schema: `schema.sql`
- 首版迁移: `migration_v1.sql`
- 启动初始化入口: `DatabaseInitializer.swift`

## 文件职责

- `schema.sql`
  - V1 全量结构快照（表、外键、索引、FTS5、触发器）
  - 适合新环境一次性建库
- `migration_v1.sql`
  - 事务化首版迁移脚本
  - 幂等执行，成功后写入 `schema_migrations(version='v1_initial')`
- `DatabaseInitializer.swift`
  - App 启动时初始化数据库
  - 设置 `foreign_keys/WAL/busy_timeout`
  - 检查 migration 版本并应用 `migration_v1.sql`
  - 若迁移文件缺失，回退到 `schema.sql` 路径

## 初始化方式（推荐）

```swift
let appSupport = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
).appendingPathComponent("DropKnow", isDirectory: true)

let sqlDirectory = Bundle.main.resourceURL!
    .appendingPathComponent("Infrastructure/Database", isDirectory: true)

let config = DatabaseInitializer.Configuration.default(
    databaseDirectory: appSupport,
    sqlDirectory: sqlDirectory
)

try DatabaseInitializer.initialize(config)
```

## V1 表清单

- `watch_directories`
- `documents`
- `document_texts`
- `document_chunks`
- `document_summaries`
- `document_events`
- `privacy_decisions`
- `notifications`
- `document_actions`
- `parse_jobs`
- `providers`
- `subscriptions`
- `usage_quotas`
- `search_sessions`
- `schema_migrations`

## 检索与约束

- FTS5:
  - `document_chunks_fts`（`content`, `content_preview`）
  - `document_summaries_fts`（`one_line_summary`, `action_required`, `key_points_flattened`）
- 外键策略:
  - 文档子表默认 `ON DELETE CASCADE`
  - `notifications.document_id` 与 `documents` 使用 `ON DELETE SET NULL`
- 状态字段:
  - 全部使用 `TEXT` 存储，保留与 Swift enum 对齐空间

## 维护约定

1. 新增/改动 schema 时，先更新 `docs/数据库迁移清单.md`
2. 再新增对应 migration（例如 `migration_v2.sql`）
3. `schema.sql` 始终保持为最新全量快照
4. 所有状态变更必须同步状态真集与 DTO 对照文档
