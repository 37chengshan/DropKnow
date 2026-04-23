# EP-004 Master Plan

作者：glm5.1+37chengshan
日期：2026-04-21

## 总目标
建立 DropKnow 的 GitHub PR 门禁和完整 GitHub 工作流，支撑 Phase 4 “体验打磨 + 公开分发”的工程治理基础。

## Wave 拆分

### Wave 1（门禁基础）
- 04-01：PR 门禁主流水线

### Wave 2（PR 规范）
- 04-02：PR 规范门禁

### Wave 3（分发与治理）
- 04-03：发布分发流水线
- 04-04：分支保护与治理文档

## 依赖关系
- 04-01 -> 04-03
- 04-02 -> 04-03
- 04-01 -> 04-04
- 04-02 -> 04-04

## 边界
1. 不在本轮引入 Apple 凭据与真实 notarization 密钥，只做工作流与 secrets 接口。
2. 不修改业务功能实现代码（Features/Domain）以避免跨 Phase。
3. 仅新增/修改 GitHub 工作流、治理脚本与文档。

## 验收总线
1. PR 门禁可自动阻断低质量变更。
2. 发布流程可在 tag 触发后自动产出分发制品。
3. main 分支保护可脚本化配置。
4. 团队可依据文档执行完整 GitHub 工作流。

## 必选门禁检查名
1. `PR Gate / build-and-test`
2. `PR Gate / artifact-guard`
3. `PR Hygiene / title-and-body-check`

上述检查名必须与分支保护脚本中的 required checks 一致。
