-- DropKnow V1 Initial Migration
-- This migration is idempotent and transaction-wrapped.
BEGIN IMMEDIATE;
-- DropKnow V1 SQLite Schema
-- Source of truth:
-- 1) 落知_状态机与错误码设计_v1.1.md
-- 2) 落知_Prompt与JSONSchema_FewShot规范_v1.1.md
-- 3) 落知_信息架构_技术架构_数据表设计_前端设计.md
-- 4) docs/数据库迁移清单.md

PRAGMA foreign_keys = ON;

-- 用途: 记录已经执行的迁移版本，保证数据库初始化幂等。
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 用途: 用户授权并启用的监听目录配置。
CREATE TABLE IF NOT EXISTS watch_directories (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    path_hint TEXT NOT NULL,
    bookmark_data BLOB NOT NULL,
    is_default_downloads INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (is_default_downloads IN (0, 1)),
    CHECK (is_active IN (0, 1))
);

-- 用途: 模型 provider 配置，按用途角色切分。
CREATE TABLE IF NOT EXISTS providers (
    id TEXT PRIMARY KEY,
    provider_type TEXT NOT NULL,
    usage_role TEXT NOT NULL,
    model_name TEXT NOT NULL,
    base_url TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    timeout_ms INTEGER NOT NULL,
    retry_policy_json TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (provider_type IN ('zhipu', 'qwen')),
    CHECK (usage_role IN ('summary', 'event_extract', 'qa', 'embedding')),
    CHECK (is_active IN (0, 1)),
    CHECK (timeout_ms > 0)
);

-- 用途: 当前设备用户的订阅状态与功能开关快照。
CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY,
    user_scope TEXT NOT NULL,
    plan_type TEXT NOT NULL,
    status TEXT NOT NULL,
    starts_at DATETIME,
    expires_at DATETIME,
    features_json TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (plan_type IN ('free', 'pro')),
    CHECK (status IN ('active', 'expired', 'cancelled'))
);

-- 用途: 每日额度统计，供订阅与限额判定。
CREATE TABLE IF NOT EXISTS usage_quotas (
    id TEXT PRIMARY KEY,
    quota_date DATE NOT NULL,
    parse_used INTEGER NOT NULL DEFAULT 0,
    parse_limit INTEGER NOT NULL,
    qa_used INTEGER NOT NULL DEFAULT 0,
    qa_limit INTEGER NOT NULL,
    advanced_search_used INTEGER NOT NULL DEFAULT 0,
    advanced_search_limit INTEGER NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (quota_date),
    CHECK (parse_used >= 0),
    CHECK (parse_limit >= 0),
    CHECK (qa_used >= 0),
    CHECK (qa_limit >= 0),
    CHECK (advanced_search_used >= 0),
    CHECK (advanced_search_limit >= 0)
);

-- 用途: 文件主表，仅存元信息与流程状态；正文等大字段拆分到 document_texts/chunks。
CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    watch_directory_id TEXT,
    file_name TEXT NOT NULL,
    file_extension TEXT NOT NULL,
    absolute_path TEXT NOT NULL,
    file_hash TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    created_at_fs DATETIME,
    modified_at_fs DATETIME,
    imported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source_type TEXT NOT NULL,
    lifecycle_status TEXT NOT NULL,
    current_stage TEXT NOT NULL,
    block_reason TEXT NOT NULL DEFAULT 'none',
    parse_status TEXT,
    parse_quality TEXT,
    summary_status TEXT,
    event_status TEXT NOT NULL DEFAULT 'none',
    privacy_status TEXT,
    readiness_flags_json TEXT NOT NULL DEFAULT '{}',
    importance_score REAL NOT NULL DEFAULT 0,
    last_error_code TEXT,
    last_error_message TEXT,
    FOREIGN KEY (watch_directory_id) REFERENCES watch_directories (id) ON DELETE SET NULL,
    UNIQUE (file_hash, file_size, modified_at_fs),
    CHECK (source_type IN ('realtime', 'initial_scan', 'manual')),
    CHECK (lifecycle_status IN ('detected', 'processing', 'waiting_user_confirmation', 'ready', 'blocked', 'failed')),
    CHECK (current_stage IN ('import', 'parse', 'gate', 'summary', 'event_extract', 'index', 'notify', 'done')),
    CHECK (block_reason IN ('none', 'privacy_confirmation_required', 'quota_exceeded', 'feature_locked', 'unsupported_type', 'permission_denied', 'policy_blocked')),
    CHECK (parse_status IS NULL OR parse_status IN ('success', 'partial', 'failed', 'unsupported')),
    CHECK (parse_quality IS NULL OR parse_quality IN ('good', 'medium', 'poor')),
    CHECK (summary_status IS NULL OR summary_status IN ('pending', 'success', 'failed')),
    CHECK (event_status IN ('none', 'has_candidate', 'has_accepted_event', 'has_calendar_event', 'all_dismissed')),
    CHECK (privacy_status IS NULL OR privacy_status IN ('safe', 'flagged', 'blocked', 'user_allowed'))
);

-- 用途: 文件全文与解析附属信息，避免 documents 过胖。
CREATE TABLE IF NOT EXISTS document_texts (
    document_id TEXT PRIMARY KEY,
    extracted_title TEXT,
    plain_text TEXT NOT NULL,
    page_count INTEGER,
    parser_type TEXT NOT NULL,
    language_hint TEXT,
    text_length INTEGER NOT NULL,
    extracted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    CHECK (text_length >= 0),
    CHECK (page_count IS NULL OR page_count >= 0)
);

-- 用途: 分片文本，供检索、证据展示与后续向量扩展。
CREATE TABLE IF NOT EXISTS document_chunks (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    content_preview TEXT NOT NULL,
    token_count INTEGER,
    char_count INTEGER NOT NULL,
    page_from INTEGER,
    page_to INTEGER,
    embedding_blob BLOB,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    UNIQUE (document_id, chunk_index),
    CHECK (chunk_index >= 0),
    CHECK (token_count IS NULL OR token_count >= 0),
    CHECK (char_count >= 0)
);

-- 用途: 结构化摘要结果，直接供 UI 与通知消费。
CREATE TABLE IF NOT EXISTS document_summaries (
    document_id TEXT PRIMARY KEY,
    document_type TEXT NOT NULL,
    one_line_summary TEXT NOT NULL,
    action_required TEXT NOT NULL,
    key_points_json TEXT NOT NULL,
    key_points_flattened TEXT NOT NULL DEFAULT '',
    time_signals_json TEXT NOT NULL,
    location_signals_json TEXT NOT NULL,
    supporting_snippets_json TEXT NOT NULL,
    risk_flags_json TEXT NOT NULL,
    confidence REAL NOT NULL,
    model_provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    CHECK (confidence >= 0 AND confidence <= 1),
    CHECK (model_provider IN ('zhipu', 'qwen'))
);

-- 用途: 从文档抽取出的事件候选及其决策/入历状态。
CREATE TABLE IF NOT EXISTS document_events (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    title TEXT NOT NULL,
    start_time DATETIME,
    end_time DATETIME,
    raw_time_text TEXT NOT NULL,
    timezone TEXT,
    location TEXT,
    notes TEXT,
    evidence_snippet TEXT NOT NULL,
    confidence REAL NOT NULL,
    calendar_eligible INTEGER NOT NULL DEFAULT 0,
    decision_status TEXT NOT NULL DEFAULT 'suggested',
    calendar_status TEXT NOT NULL DEFAULT 'not_added',
    calendar_event_identifier TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    CHECK (confidence >= 0 AND confidence <= 1),
    CHECK (calendar_eligible IN (0, 1)),
    CHECK (decision_status IN ('suggested', 'accepted', 'dismissed', 'expired')),
    CHECK (calendar_status IN ('not_added', 'adding', 'added', 'failed', 'feature_locked'))
);

-- 用途: 隐私门禁命中与用户决策记录。
CREATE TABLE IF NOT EXISTS privacy_decisions (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    rule_hits_json TEXT NOT NULL,
    sampled_text TEXT,
    decision TEXT NOT NULL,
    decided_at DATETIME NOT NULL,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    CHECK (risk_level IN ('low', 'medium', 'high')),
    CHECK (decision IN ('allow_once', 'deny', 'always_ask', 'trust_directory'))
);

-- 用途: 通知展示与交互追踪记录。
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    document_id TEXT,
    notification_type TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    action_payload_json TEXT,
    shown_at DATETIME,
    clicked_at DATETIME,
    dismissed_at DATETIME,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE SET NULL
);

-- 用途: 用户在不同入口对文档执行的动作审计。
CREATE TABLE IF NOT EXISTS document_actions (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    action_source TEXT NOT NULL,
    metadata_json TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
);

-- 用途: 流水线阶段执行日志，支持重试、排障与性能分析。
CREATE TABLE IF NOT EXISTS parse_jobs (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    stage TEXT NOT NULL,
    status TEXT NOT NULL,
    provider_id TEXT,
    started_at DATETIME,
    finished_at DATETIME,
    duration_ms INTEGER,
    error_code TEXT,
    error_message TEXT,
    FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
    FOREIGN KEY (provider_id) REFERENCES providers (id) ON DELETE SET NULL,
    CHECK (stage IN ('import', 'parse', 'gate', 'summary', 'event_extract', 'index', 'notify')),
    CHECK (status IN ('queued', 'running', 'success', 'failed', 'skipped', 'cancelled')),
    CHECK (duration_ms IS NULL OR duration_ms >= 0)
);

-- 用途: Quick Panel 搜索/问答会话状态，用于 UI 渲染与错误恢复。
CREATE TABLE IF NOT EXISTS search_sessions (
    id TEXT PRIMARY KEY,
    query_text TEXT NOT NULL,
    mode TEXT NOT NULL,
    status TEXT NOT NULL,
    block_reason TEXT NOT NULL DEFAULT 'none',
    result_count INTEGER NOT NULL DEFAULT 0,
    answer_text TEXT,
    last_error_code TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (mode IN ('search', 'qa')),
    CHECK (status IN ('idle', 'retrieving', 'assembling', 'answering', 'success', 'no_result', 'blocked', 'failed')),
    CHECK (block_reason IN ('none', 'quota_exceeded', 'feature_locked', 'empty_index')),
    CHECK (result_count >= 0)
);

-- 用途: 对 chunk 文本建立全文检索，支持关键词/短语召回。
CREATE VIRTUAL TABLE IF NOT EXISTS document_chunks_fts
USING fts5(
    content,
    content_preview,
    content = 'document_chunks',
    content_rowid = 'rowid',
    tokenize = 'unicode61'
);

-- 用途: 对摘要字段建立全文检索，支持 summary/action/key points 召回。
CREATE VIRTUAL TABLE IF NOT EXISTS document_summaries_fts
USING fts5(
    one_line_summary,
    action_required,
    key_points_flattened,
    content = 'document_summaries',
    content_rowid = 'rowid',
    tokenize = 'unicode61'
);

-- 高频索引: watch 目录启用状态查询。
CREATE INDEX IF NOT EXISTS idx_watch_directories_active
    ON watch_directories (is_active);

-- 高频索引: provider 选择与过滤。
CREATE INDEX IF NOT EXISTS idx_providers_active_role
    ON providers (is_active, usage_role);

-- 高频索引: 当前订阅状态。
CREATE INDEX IF NOT EXISTS idx_subscriptions_status
    ON subscriptions (status);

-- 高频索引: 按导入时间倒序拉取最近文件。
CREATE INDEX IF NOT EXISTS idx_documents_imported_at
    ON documents (imported_at DESC);

-- 高频索引: 文档状态与阶段过滤。
CREATE INDEX IF NOT EXISTS idx_documents_lifecycle_status
    ON documents (lifecycle_status);

CREATE INDEX IF NOT EXISTS idx_documents_current_stage
    ON documents (current_stage);

CREATE INDEX IF NOT EXISTS idx_documents_event_status
    ON documents (event_status);

CREATE INDEX IF NOT EXISTS idx_documents_watch_directory_id
    ON documents (watch_directory_id);

CREATE INDEX IF NOT EXISTS idx_documents_file_hash
    ON documents (file_hash);

CREATE INDEX IF NOT EXISTS idx_documents_absolute_path
    ON documents (absolute_path);

-- 高频索引: 文本表按文档关联。
CREATE INDEX IF NOT EXISTS idx_document_texts_extracted_at
    ON document_texts (extracted_at DESC);

-- 高频索引: chunk 召回前置筛选。
CREATE INDEX IF NOT EXISTS idx_document_chunks_document_id
    ON document_chunks (document_id);

CREATE INDEX IF NOT EXISTS idx_document_chunks_page_range
    ON document_chunks (document_id, page_from, page_to);

-- 高频索引: 摘要列表与风险过滤。
CREATE INDEX IF NOT EXISTS idx_document_summaries_document_type
    ON document_summaries (document_type);

CREATE INDEX IF NOT EXISTS idx_document_summaries_confidence
    ON document_summaries (confidence DESC);

-- 高频索引: 事件候选与日历状态。
CREATE INDEX IF NOT EXISTS idx_document_events_document_id
    ON document_events (document_id);

CREATE INDEX IF NOT EXISTS idx_document_events_decision_status
    ON document_events (decision_status);

CREATE INDEX IF NOT EXISTS idx_document_events_calendar_status
    ON document_events (calendar_status);

CREATE INDEX IF NOT EXISTS idx_document_events_start_time
    ON document_events (start_time);

-- 高频索引: 隐私门禁与通知查询。
CREATE INDEX IF NOT EXISTS idx_privacy_decisions_document_id
    ON privacy_decisions (document_id, decided_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_document_id
    ON notifications (document_id);

CREATE INDEX IF NOT EXISTS idx_notifications_shown_at
    ON notifications (shown_at DESC);

-- 高频索引: 用户行为审计。
CREATE INDEX IF NOT EXISTS idx_document_actions_document_id
    ON document_actions (document_id, created_at DESC);

-- 高频索引: 流水线执行与排障。
CREATE INDEX IF NOT EXISTS idx_parse_jobs_document_id
    ON parse_jobs (document_id);

CREATE INDEX IF NOT EXISTS idx_parse_jobs_stage_status
    ON parse_jobs (stage, status);

CREATE INDEX IF NOT EXISTS idx_parse_jobs_started_at
    ON parse_jobs (started_at DESC);

-- 高频索引: Quick Panel 会话渲染。
CREATE INDEX IF NOT EXISTS idx_search_sessions_status
    ON search_sessions (status);

CREATE INDEX IF NOT EXISTS idx_search_sessions_mode_created_at
    ON search_sessions (mode, created_at DESC);

-- 更新时间触发器: watch_directories
CREATE TRIGGER IF NOT EXISTS trg_watch_directories_touch_updated_at
AFTER UPDATE ON watch_directories
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE watch_directories
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- 更新时间触发器: subscriptions
CREATE TRIGGER IF NOT EXISTS trg_subscriptions_touch_updated_at
AFTER UPDATE ON subscriptions
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE subscriptions
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- 更新时间触发器: usage_quotas
CREATE TRIGGER IF NOT EXISTS trg_usage_quotas_touch_updated_at
AFTER UPDATE ON usage_quotas
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE usage_quotas
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- 更新时间触发器: document_summaries
CREATE TRIGGER IF NOT EXISTS trg_document_summaries_touch_updated_at
AFTER UPDATE ON document_summaries
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE document_summaries
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- 更新时间触发器: document_events
CREATE TRIGGER IF NOT EXISTS trg_document_events_touch_updated_at
AFTER UPDATE ON document_events
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE document_events
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- 更新时间触发器: search_sessions
CREATE TRIGGER IF NOT EXISTS trg_search_sessions_touch_updated_at
AFTER UPDATE ON search_sessions
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE search_sessions
    SET updated_at = CURRENT_TIMESTAMP
    WHERE rowid = NEW.rowid;
END;

-- FTS 同步触发器: document_chunks -> document_chunks_fts
CREATE TRIGGER IF NOT EXISTS trg_document_chunks_fts_ai
AFTER INSERT ON document_chunks
FOR EACH ROW
BEGIN
    INSERT INTO document_chunks_fts (rowid, content, content_preview)
    VALUES (NEW.rowid, NEW.content, NEW.content_preview);
END;

CREATE TRIGGER IF NOT EXISTS trg_document_chunks_fts_ad
AFTER DELETE ON document_chunks
FOR EACH ROW
BEGIN
    INSERT INTO document_chunks_fts (document_chunks_fts, rowid, content, content_preview)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.content_preview);
END;

CREATE TRIGGER IF NOT EXISTS trg_document_chunks_fts_au
AFTER UPDATE ON document_chunks
FOR EACH ROW
BEGIN
    INSERT INTO document_chunks_fts (document_chunks_fts, rowid, content, content_preview)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.content_preview);
    INSERT INTO document_chunks_fts (rowid, content, content_preview)
    VALUES (NEW.rowid, NEW.content, NEW.content_preview);
END;

-- FTS 同步触发器: document_summaries -> document_summaries_fts
CREATE TRIGGER IF NOT EXISTS trg_document_summaries_fts_ai
AFTER INSERT ON document_summaries
FOR EACH ROW
BEGIN
    INSERT INTO document_summaries_fts (rowid, one_line_summary, action_required, key_points_flattened)
    VALUES (NEW.rowid, NEW.one_line_summary, NEW.action_required, NEW.key_points_flattened);
END;

CREATE TRIGGER IF NOT EXISTS trg_document_summaries_fts_ad
AFTER DELETE ON document_summaries
FOR EACH ROW
BEGIN
    INSERT INTO document_summaries_fts (
        document_summaries_fts,
        rowid,
        one_line_summary,
        action_required,
        key_points_flattened
    )
    VALUES (
        'delete',
        OLD.rowid,
        OLD.one_line_summary,
        OLD.action_required,
        OLD.key_points_flattened
    );
END;

CREATE TRIGGER IF NOT EXISTS trg_document_summaries_fts_au
AFTER UPDATE ON document_summaries
FOR EACH ROW
BEGIN
    INSERT INTO document_summaries_fts (
        document_summaries_fts,
        rowid,
        one_line_summary,
        action_required,
        key_points_flattened
    )
    VALUES (
        'delete',
        OLD.rowid,
        OLD.one_line_summary,
        OLD.action_required,
        OLD.key_points_flattened
    );
    INSERT INTO document_summaries_fts (rowid, one_line_summary, action_required, key_points_flattened)
    VALUES (NEW.rowid, NEW.one_line_summary, NEW.action_required, NEW.key_points_flattened);
END;

INSERT OR IGNORE INTO schema_migrations (version, description)
VALUES ('v1_initial', 'Initial DropKnow SQLite schema with FTS5 and baseline indexes');

COMMIT;
