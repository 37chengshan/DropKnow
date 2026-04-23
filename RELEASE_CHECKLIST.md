# DropKnow 发布检查清单

## 环境准备

### 1. Clean Machine 安装

- [ ] 在干净 macOS 环境（无遗留构建产物）执行 `swift build`
- [ ] `xcodegen generate` 生成 Xcode 项目
- [ ] `xcodebuild -scheme DropKnow -configuration Release build` 编译成功
- [ ] 验证 `.build/`、`DerivedData/` 目录不含旧产物

## 首次启动权限

### 2. 文件访问权限

- [ ] 启动 App 后，系统提示「文件访问权限」时选择「允许」
- [ ] 验证 `/Users/cc/Desktop/DropKnow/` 目录可正常读取
- [ ] 验证文件列表显示正常

### 3. 日历访问权限（EventKit）

- [ ] 如使用真实日历功能，系统提示「日历权限」时选择「允许」
- [ ] 验证能读取现有日历事件
- [ ] 验证能创建测试事件到日历

## 核心功能验证

### 4. 真实文件导入

- [ ] 拖拽真实 PDF/DOCX/TXT 文件到应用窗口
- [ ] 验证文件解析状态（processing）正常显示
- [ ] 验证解析完成后文档进入「最近文件」列表
- [ ] 验证导入 Toast 通知正常弹出

### 5. 搜索功能

- [ ] 在 QuickPanel 输入自然语言问题（如「这周有什么截止时间？」）
- [ ] 验证搜索结果卡片显示
- [ ] 点击搜索结果卡片，正常打开 DocumentDetailSceneView
- [ ] 验证问答模式（QA）正常返回回答

### 6. 文档详情页

- [ ] 验证「最近文件」点击进入详情页
- [ ] 验证「重要提醒」点击进入详情页
- [ ] 验证详情页显示摘要、证据片段、事件候选
- [ ] 验证 partialSuccess / blocked / processing 状态 UI 正常（不降级为纯文本）

### 7. 日历能力

- [ ] 在 DocumentDetail 事件候选中点击「加入日历」
- [ ] 验证事件成功添加到系统日历
- [ ] 验证「忽略」按钮正常隐藏事件

## 异常处理

### 8. 崩溃与日志采集

- [ ] 模拟异常场景，验证 App 不崩溃
- [ ] 验证 Console.app 可看到 `os.Logger` 输出
- [ ] 验证关键操作有结构化日志（INFO 级别）
- [ ] 验证错误场景有对应错误日志（ERROR 级别）

## 发布前检查

- [ ] `.build/` 目录已加入 `.gitignore`
- [ ] 无硬编码凭证或 secrets
- [ ] 所有 UI 文本使用中文
- [ ] Build succeeds on clean machine
