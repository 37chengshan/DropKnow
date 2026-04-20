# GitHub 工作流与门禁说明

作者：glm5.1+37chengshan

## 目标
建立 DropKnow 的完整 GitHub 工作流闭环：
1. 开发分支提交后，通过 PR 门禁保障基础质量。
2. PR 规范门禁保证评审信息完整可追溯。
3. tag 触发发布分发，自动产出发布制品。
4. main 分支保护与 CODEOWNERS 将门禁规则落到仓库策略。

## 工作流总览

### 1) PR Gate
- 文件：`.github/workflows/pr-gate.yml`
- 触发：`pull_request` -> `main`
- 检查名：
  - `PR Gate / build-and-test`
  - `PR Gate / artifact-guard`
- 作用：
  - 在 macOS runner 执行 `swift build` 与 `swift test`。
  - 拒绝提交构建产物（如 `.build/**`、`build/DerivedData/**`）。
  - 上传日志 artifact 便于审计。

### 2) PR Hygiene
- 文件：`.github/workflows/pr-hygiene.yml`
- 触发：`pull_request`（opened/edited/synchronize/reopened）-> `main`
- 检查名：`PR Hygiene / title-and-body-check`
- 规则：
  - 标题必须符合 Conventional Commits：`type(scope): subject`。
  - 描述必须包含三段：
    - `## 变更摘要`
    - `## 验证步骤`
    - `## 风险与回滚`

### 3) Release Distribution
- 文件：`.github/workflows/release-distribution.yml`
- 触发：
  - `push` 到 `v*` tag
  - `workflow_dispatch` 手动触发
- 权限：`contents: write`
- 作用：
  - 执行 release 构建与测试。
  - 产出 `DropKnow-<tag>.tar.gz` 与日志。
  - 上传到 GitHub Release。
  - 手动触发时仅允许已存在的 `v*` tag，避免误发版。

## PR 模板
- 文件：`.github/pull_request_template.md`
- 必填段落与 PR Hygiene 门禁一致：
  - 变更摘要
  - 验证步骤
  - 风险与回滚

## CODEOWNERS
- 文件：`.github/CODEOWNERS`
- 作用：在关键目录触发 code owner 评审请求，确保责任清晰。

## 分支保护落地
- 脚本：`script/setup_branch_protection.sh`
- 模式：
  - `--dry-run`：仅输出 payload，不改仓库设置。
  - `--apply`：调用 GitHub API 真正更新保护策略。

### 推荐执行
```bash
bash script/setup_branch_protection.sh --owner 37chengshan --repo DropKnow --dry-run
bash script/setup_branch_protection.sh --owner 37chengshan --repo DropKnow --apply
```

### 脚本配置的关键规则
1. required checks：
   - `PR Gate / build-and-test`
   - `PR Gate / artifact-guard`
   - `PR Hygiene / title-and-body-check`
2. 最小评审：至少 1 个审批。
3. `require_code_owner_reviews: true`。
4. `dismiss_stale_reviews: true`。
5. 禁止 force push 和删除分支。
6. 要求对话已解决（conversation resolution）。

## 验证清单
1. `gh workflow view pr-gate.yml`
2. `gh workflow view pr-hygiene.yml`
3. `gh workflow view release-distribution.yml`
4. 创建草稿 PR 做正反例验证：
   - 非法标题/缺失模板段落时失败。
   - 修复后通过。
5. tag 发布演练：
   - 推送测试 tag（如 `v0.0.0-rc1`）。
   - 用 `gh release view <tag>` 检查产物。
6. 分支保护读取验证：
   - `gh api repos/<owner>/<repo>/branches/main/protection`

## 故障排查
1. `gh` 未登录：执行 `gh auth login`。
2. 无管理员权限：
   - 无法执行 `--apply`。
   - 可先执行 `--dry-run`，并通过只读 API 校验当前状态。
4. 手动发版失败（Tag does not exist）：
  - 先创建并推送 tag，再重新触发 workflow_dispatch。
3. required checks 名称不一致：
   - 以工作流名 + job 名为准。
   - 若改名，必须同步更新分支保护脚本。
