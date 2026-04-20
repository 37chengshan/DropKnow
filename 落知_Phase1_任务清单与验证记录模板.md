# 落知（DropKnow）Phase 1：任务清单与验证记录模板

> 阶段定位：MVP Alpha / Beta 实施阶段  
> 对应前置文档：PRD v1 / Roadmap / 信息架构与技术架构 / Phase 0 验证结果  
> 适用范围：目录监听、本地解析、摘要、事件候选、详情页、额度与订阅门禁、搜索 Beta

---

# 1. 文档目的

本文件用于把 **Phase 1 从“已验证可行”推进到“可执行开发”** 的任务、验收口径和记录模板一次性固化。

与 Phase 0 的区别：

- **Phase 0** 关注：能不能跑通、技术路线对不对
- **Phase 1** 关注：模块是否真的可交付、能否进入内测、能否稳定扩展

---

# 2. Phase 1 目标

在 Phase 1 内完成以下里程碑：

1. 建立稳定的 macOS 菜单栏原生应用壳
2. 打通目录监听、最近 7 天导入、文件去抖、去重
3. 支持 PDF / DOCX / TXT(MD) 的统一解析管线
4. 建立本地 SQLite 数据库与核心表落地
5. 生成通知型摘要并在应用内展示
6. 构建详情页、最近文件列表、重要提醒列表
7. 接入事件候选抽取和“已加入日历”状态流
8. 建立免费 / 订阅门禁、额度记录和基础升级入口
9. 完成高级搜索 Beta（不做复杂聊天线程）

---

# 3. Phase 1 边界

## 3.1 本阶段必须完成

- MenuBar 壳与核心窗口
- Downloads + 1 个自定义目录授权与恢复
- 首次导入最近 7 天文件
- 实时新文件监听
- PDF / DOCX / TXT(MD) 解析
- SQLite schema 落地
- documents / summaries / events / jobs / quotas 基础写入
- 通知型摘要
- 高优先级事件型卡片
- 文件详情页
- 手动重新解析
- 基础订阅/额度门禁
- 高级搜索 Beta（摘要/事件/证据返回）

## 3.2 本阶段明确不做

- PPT / Excel / OCR
- 多设备同步
- 复杂聊天线程
- 自动静默入历
- 自动更新既有日历事件
- 任意 provider 配置面板
- 全局双击 Control 入口

---

# 4. Phase 1 里程碑定义

## Milestone A：App Shell 成立
满足：
- 菜单栏常驻
- Settings 打开正常
- Quick Panel 可拉起
- Document Detail Window 可展示 mock 数据

## Milestone B：Ingestion Pipeline 成立
满足：
- 授权目录可监听
- 首次 7 天导入不重复、不炸通知
- 新文件可进入队列
- 去抖 / 去重生效

## Milestone C：Intelligence Pipeline 成立
满足：
- 解析结果写入数据库
- 摘要成功产出
- 事件候选可写入并显示
- 失败状态可见

## Milestone D：User Value 成立
满足：
- 最近文件页可用
- 重要提醒页可用
- 详情页可查看摘要、证据、事件
- 用户能用自然语言问回核心内容

---

# 5. 任务拆解总表

| 模块 | 目标 | 优先级 | 负责人 | 状态 |
|---|---|---|---|---|
| App Shell | 搭建菜单栏与窗口壳 | P0 |  | 未开始 |
| Watcher | 目录授权、监听、恢复 | P0 |  | 未开始 |
| Import | 首次导入、去抖、去重 | P0 |  | 未开始 |
| Parsing | PDF / DOCX / TXT 统一解析 | P0 |  | 未开始 |
| Database | SQLite schema 与 repository | P0 |  | 未开始 |
| Summary | 摘要结构化输出与落库 | P0 |  | 未开始 |
| Events | 事件候选抽取与展示 | P0 |  | 未开始 |
| Detail UI | 文件详情页 | P0 |  | 未开始 |
| Reminder UI | 最近文件 / 重要提醒 / 卡片 | P0 |  | 未开始 |
| Quota / Plan | 免费与订阅门禁 | P1 |  | 未开始 |
| Search Beta | 高级搜索与证据片段 | P1 |  | 未开始 |
| Observability | 日志、指标、错误码展示 | P1 |  | 未开始 |

---

# 6. 模块级任务清单

## 6.1 模块一：App Shell

### 目标
建立可扩展的 macOS 原生应用壳，承载后续业务模块。

### 任务项
- [ ] 建立 `DropKnowApp.swift`
- [ ] 搭建 `MenuBarExtra`
- [ ] 搭建 `QuickPanelScene`
- [ ] 搭建 `DocumentDetailScene`
- [ ] 搭建 `SettingsScene`
- [ ] 建立 AppRouter / Window Router
- [ ] 统一依赖注入容器
- [ ] 建立全局 DesignSystem
- [ ] 建立空态 / 错误态 / Loading 态

### 验证点
- [ ] 应用可正常启动与退出
- [ ] 菜单栏入口稳定
- [ ] Quick Panel 能打开关闭
- [ ] Detail Window 能展示 mock 数据
- [ ] Settings 能独立打开

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.2 模块二：Watcher + Directory Authorization

### 目标
稳定管理 Downloads 与 1 个自定义目录的授权、持久化和监听。

### 任务项
- [ ] Downloads 目录授权流程
- [ ] 自定义目录选择器
- [ ] security-scoped bookmark 持久化
- [ ] bookmark 恢复与过期处理
- [ ] 启停监听
- [ ] 目录激活/禁用开关
- [ ] 权限异常状态展示
- [ ] watch_directories 表落地

### 验证点
- [ ] 应用重启后权限恢复成功
- [ ] Downloads 与自定义目录都可监听
- [ ] 目录失效后用户可重新授权
- [ ] 监听状态 UI 可见

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.3 模块三：Import Coordinator

### 目标
把新文件与首次导入文件统一收敛到同一导入状态流。

### 任务项
- [ ] 首次导入最近 7 天文件
- [ ] 临时文件过滤
- [ ] 大文件稳定检测
- [ ] 重命名完成识别
- [ ] file hash 计算
- [ ] 内容/路径联合去重
- [ ] source_type 标记
- [ ] parse_jobs import 阶段记录

### 验证点
- [ ] 首次导入不会触发逐条卡片
- [ ] 同一个文件不会重复入库
- [ ] 文件写入中不会提前解析
- [ ] 目录移动进入的文件可处理

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.4 模块四：Parsing Pipeline

### 目标
建立统一的文件解析入口，输出统一的文本结构。

### 任务项
- [ ] 文件类型路由器
- [ ] PDF 解析器
- [ ] DOCX 解析器
- [ ] TXT/MD 解析器
- [ ] 解析质量评分
- [ ] 失败/不支持状态码
- [ ] document_texts 表落地
- [ ] parse_jobs parse 阶段记录

### 验证点
- [ ] 普通 PDF 能稳定抽到正文
- [ ] DOCX 至少一条实现路径可用
- [ ] TXT/MD 正常入库
- [ ] 不支持文件状态清晰可见

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.5 模块五：Privacy Gate

### 目标
高风险文件在上云前先本地规则拦截并记录用户决策。

### 任务项
- [ ] 风险类别枚举
- [ ] 规则引擎（文件名 + 前几行 + 类型）
- [ ] 风险级别 low / medium / high
- [ ] RiskGateSheet
- [ ] 决策持久化
- [ ] 目录信任策略
- [ ] privacy_decisions 表落地
- [ ] parse_jobs gate 阶段记录

### 验证点
- [ ] 高风险文件不上云前能拦截
- [ ] 普通通知误拦截率可接受
- [ ] 用户选择可复用
- [ ] 被拒绝文件保留元数据但不出摘要

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.6 模块六：Summary Pipeline

### 目标
产出通知型摘要并落库。

### 任务项
- [ ] 摘要 JSON schema
- [ ] provider 路由
- [ ] 摘要请求重试
- [ ] 非法 JSON 修复策略
- [ ] document_summaries 表落地
- [ ] key_points / risk_flags / time_signals 写入
- [ ] parse_jobs summary 阶段记录

### 验证点
- [ ] 摘要能返回“这是什么 / 要做什么 / 重点”
- [ ] 对普通通知类文件结果稳定
- [ ] provider 超时可回退
- [ ] 失败可重试

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.7 模块七：Event Candidate Pipeline

### 目标
产出结构化事件候选，并驱动高优先级提醒与加入日历按钮显示。

### 任务项
- [ ] 事件 JSON schema
- [ ] 事件类型映射
- [ ] 置信度阈值规则
- [ ] document_events 表落地
- [ ] event_status 更新
- [ ] 详情页 Inspector 接入
- [ ] 卡片显示条件
- [ ] parse_jobs event_extract 阶段记录

### 验证点
- [ ] 高置信度考试/DDL能正确提取
- [ ] 中低置信度仅提示，不直接露出强按钮
- [ ] evidence_snippet 可展示
- [ ] dismiss / accepted 状态流正常

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.8 模块八：Reminder UI + Detail UI

### 目标
让用户在不打断的前提下看到价值，并能进入完整详情。

### 任务项
- [ ] SummaryCard
- [ ] ImportantEventCard
- [ ] 最近文件页
- [ ] 重要提醒页
- [ ] 详情页 3 栏布局
- [ ] 打开原文件
- [ ] 重新解析
- [ ] 已加入日历状态展示

### 验证点
- [ ] 普通文件卡片足够轻
- [ ] 事件卡片信息完整但不拥挤
- [ ] 详情页能承载摘要/事件/证据
- [ ] 多卡片连续出现时不乱

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.9 模块九：Quota / Subscription Gate

### 目标
把免费版和订阅版的能力边界真正落到产品与状态流上。

### 任务项
- [ ] subscriptions 表落地
- [ ] usage_quotas 表落地
- [ ] 当日解析额度判断
- [ ] 当日问答额度判断
- [ ] 免费版日历功能关闭
- [ ] 免费版目录数限制
- [ ] 升级入口与 CTA
- [ ] QuotaBadge 接入

### 验证点
- [ ] 免费版额度能正确扣减
- [ ] 功能门禁能正确拦截
- [ ] 升级态不会静默失败
- [ ] 订阅版功能正常开放

### 验收标准
- 通过 / 部分通过 / 不通过

---

## 6.10 模块十：Search Beta

### 目标
先做“语义+事件+证据”的高级搜索 Beta，不做复杂多轮聊天。

### 任务项
- [ ] document_chunks 表与 FTS5
- [ ] document_summaries_fts
- [ ] 本地检索 orchestrator
- [ ] 事件优先检索
- [ ] 证据片段拼装
- [ ] Quick Panel 搜索模式
- [ ] 问答模式结果页
- [ ] advanced_search_used 统计

### 验证点
- [ ] 能回答“高数考试在哪天”
- [ ] 能返回文件与证据片段
- [ ] 没命中时不幻觉
- [ ] 查询耗时可接受

### 验收标准
- 通过 / 部分通过 / 不通过

---

# 7. 周执行建议（可滚动）

## Week 1：Foundation
- [ ] App Shell
- [ ] Watcher
- [ ] Import Coordinator
- [ ] Database 初版

## Week 2：Parse + Summary
- [ ] Parsing Pipeline
- [ ] Privacy Gate
- [ ] Summary Pipeline
- [ ] 最近文件页 + 详情页初版

## Week 3：Events + UX
- [ ] Event Pipeline
- [ ] Reminder UI
- [ ] Reparse
- [ ] 状态与错误反馈

## Week 4：Gate + Search Beta
- [ ] Quota / Subscription Gate
- [ ] Search Beta
- [ ] 重要提醒页
- [ ] 整体联调

---

# 8. 每日站会模板

## 昨天完成
- 

## 今天要做
- 

## 当前阻塞
- 

## 风险判断
- 

## 是否需要更新技术决策
- 是 / 否

---

# 9. 验证记录模板（Phase 1）

## 9.1 基础信息
- 日期：
- 模块：
- 分支 / 提交：
- 环境：
  - macOS：
  - Xcode：
  - 构建方式：

## 9.2 本次验证目标
- 
- 
- 

## 9.3 输入样本 / 场景
| 编号 | 类型 | 输入 | 预期 | 备注 |
|---|---|---|---|---|
| P1-01 |  |  |  |  |
| P1-02 |  |  |  |  |

## 9.4 操作步骤
1. 
2. 
3. 

## 9.5 实际结果
- 是否成功：
- 关键现象：
- 日志摘要：
- 用户可感知耗时：

## 9.6 指标记录
| 指标 | 数值 | 备注 |
|---|---:|---|
| 导入耗时 |  |  |
| 解析耗时 |  |  |
| 门禁耗时 |  |  |
| 摘要耗时 |  |  |
| 事件抽取耗时 |  |  |
| 卡片出现耗时 |  |  |
| 查询耗时 |  |  |

## 9.7 问题记录
| 问题编号 | 级别 | 描述 | 复现条件 | 当前判断 | 后续动作 |
|---|---|---|---|---|---|
| P1-01 |  |  |  |  |  |

## 9.8 结论
- 通过 / 部分通过 / 不通过
- 是否可并入主分支：
- 下一步建议：

---

# 10. Phase 1 结束验收总表

| 里程碑 | 验收项 | 结论 | 备注 |
|---|---|---|---|
| A | App Shell 成立 |  |  |
| B | Ingestion Pipeline 成立 |  |  |
| C | Intelligence Pipeline 成立 |  |  |
| D | User Value 成立 |  |  |

---

# 11. Phase 1 结束输出物

应至少产出：

1. 可运行的菜单栏原生应用
2. 目录授权与监听能力
3. 本地数据库初版
4. PDF / DOCX / TXT 解析能力
5. 通知型摘要
6. 事件候选初版
7. 最近文件 / 详情页 / 重要提醒页
8. 免费 / 订阅门禁初版
9. 高级搜索 Beta
10. 问题清单 + 技术债清单 + Phase 2 进入条件
