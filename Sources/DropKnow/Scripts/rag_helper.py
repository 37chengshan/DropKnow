#!/usr/bin/env python3
import argparse
import hashlib
import json
import math
import os
import re
import socket
import sqlite3
import sys
import urllib.error
import urllib.request

DEFAULT_DIMENSION = 768
DEFAULT_EMBEDDING_ENDPOINT = "https://dashscope.aliyuncs.com/api/v1/services/embeddings/multimodal-embedding/multimodal-embedding"
DEFAULT_CHAT_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False))


class UserVisibleError(RuntimeError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def tokenize(text):
    lower = text.lower()
    words = re.findall(r"[a-z0-9_]+|[\u4e00-\u9fff]{1,4}", lower)
    chars = [lower[i : i + 2] for i in range(max(0, len(lower) - 1)) if "\u4e00" <= lower[i] <= "\u9fff"]
    return words + chars


def extract_file_targets(query):
    pattern = r"[A-Za-z0-9_\-\u4e00-\u9fff\.]+\.(?:pdf|docx|txt|md|markdown)"
    targets = re.findall(pattern, query, flags=re.I)
    seen = set()
    ordered = []
    for item in targets:
        key = item.lower()
        if key in seen:
            continue
        seen.add(key)
        ordered.append(item)
    return ordered


def chunk_keyword_score(query, text):
    score = 0.0
    query_lower = query.lower()
    text_lower = text.lower()
    tokens = [token for token in tokenize(query) if len(token.strip()) > 1]
    for token in set(tokens):
        if token in text_lower:
            score += 1.0

    if any(flag in query_lower for flag in ("日期", "时间", "哪天", "date", "day")):
        if re.search(r"\d{4}年\d{1,2}月\d{1,2}日|\d{4}[/-]\d{1,2}[/-]\d{1,2}", text):
            score += 2.0
    if any(flag in query_lower for flag in ("地点", "位置", "哪里", "location", "where")):
        if re.search(r"[\u4e00-\u9fff]{2,20}[·•]?\s*(南京|北京|上海|广州|深圳|杭州|苏州|成都|武汉|西安)|地点|地址|教室|会场", text):
            score += 2.0

    return score


def direct_file_hits(db, query, top_k):
    targets = extract_file_targets(query)
    if not targets:
        return []

    hits = []
    seen_chunk_ids = set()
    for target in targets:
        rows = db.execute(
            """
            select c.chunk_id, c.file_id, c.file_name, c.file_path, c.text, c.chunk_index, c.revision_id
            from chunks c
            join active_revisions a
              on a.file_id = c.file_id and a.revision_id = c.revision_id
            where lower(c.file_name) = lower(?)
               or lower(c.file_name) like lower(?)
            """,
            (target, f"%{os.path.splitext(target)[0]}%"),
        ).fetchall()

        if not rows:
            continue

        ranked_rows = sorted(
            rows,
            key=lambda row: (
                chunk_keyword_score(query, row[4]),
                -row[5],
            ),
            reverse=True,
        )

        for row in ranked_rows[: min(top_k, 3)]:
            chunk_id, file_id, file_name, file_path, text, chunk_index, revision_id = row
            if chunk_id in seen_chunk_ids:
                continue
            seen_chunk_ids.add(chunk_id)
            hits.append(
                {
                    "id": chunk_id,
                    "fileID": file_id,
                    "fileName": file_name,
                    "filePath": file_path,
                    "snippet": text[:700],
                    "score": 1.25 + chunk_keyword_score(query, text),
                    "chunkIndex": int(chunk_index),
                    "revisionID": revision_id,
                    "matchReason": "命中文件名",
                }
            )

    return hits[:top_k]


def config_path(store):
    return os.path.join(os.path.dirname(store), "providers.local.json")


def load_provider_config(store):
    config = {
        "provider": "dashscope",
        "api_key": os.getenv("DASHSCOPE_API_KEY", ""),
        "embedding_model": os.getenv("DROPKNOW_EMBEDDING_MODEL", "tongyi-embedding-vision-flash-2026-03-06"),
        "embedding_dimension": int(os.getenv("DROPKNOW_EMBEDDING_DIMENSION", str(DEFAULT_DIMENSION))),
        "embedding_endpoint": os.getenv("DROPKNOW_EMBEDDING_ENDPOINT", DEFAULT_EMBEDDING_ENDPOINT),
        "chat_model": os.getenv("DROPKNOW_CHAT_MODEL", "qwen3.5-flash"),
        "chat_endpoint": os.getenv("DROPKNOW_CHAT_ENDPOINT", DEFAULT_CHAT_ENDPOINT),
    }
    path = config_path(store)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                local = json.load(handle)
        except json.JSONDecodeError as exc:
            raise UserVisibleError("CONFIG_INVALID", "providers.local.json 格式错误") from exc
        config.update({k: v for k, v in local.items() if v not in (None, "")})
    return config


def request_json(url, api_key, payload, timeout=60):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            raise UserVisibleError("INVALID_API_KEY", "DashScope API Key 无效或无权限") from exc
        if exc.code == 429:
            raise UserVisibleError("RATE_LIMIT", "DashScope 接口限流") from exc
        raise UserVisibleError("HTTP_ERROR", f"DashScope 请求失败（HTTP {exc.code}）") from exc
    except (socket.timeout, TimeoutError) as exc:
        raise UserVisibleError("TIMEOUT", "网络请求超时") from exc
    except urllib.error.URLError as exc:
        raise UserVisibleError("NETWORK", "网络请求失败") from exc


def local_hash_embed(text, dimension):
    vector = [0.0] * dimension
    for token in tokenize(text):
        digest = hashlib.blake2b(token.encode("utf-8"), digest_size=8).digest()
        bucket = int.from_bytes(digest[:4], "little") % dimension
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vector[bucket] += sign
    norm = math.sqrt(sum(value * value for value in vector))
    if norm == 0:
        return vector
    return [value / norm for value in vector]


def dashscope_embeddings(texts, config):
    api_key = config.get("api_key", "")
    if not api_key:
        raise RuntimeError("未配置 DashScope API Key")

    vectors = []
    batch_size = 8
    for start in range(0, len(texts), batch_size):
        batch = texts[start : start + batch_size]
        payload = {
            "model": config["embedding_model"],
            "input": {"contents": [{"text": text[:6000]} for text in batch]},
            "parameters": {
                "dimension": int(config["embedding_dimension"]),
                "output_type": "dense",
            },
        }
        response = request_json(config["embedding_endpoint"], api_key, payload)
        embeddings = response.get("output", {}).get("embeddings", [])
        if len(embeddings) != len(batch):
            raise RuntimeError(f"Embedding response count mismatch: expected {len(batch)}, got {len(embeddings)}")
        embeddings.sort(key=lambda item: item.get("index", 0))
        vectors.extend([item["embedding"] for item in embeddings])
    return vectors


def embed_texts(texts, config):
    api_key = config.get("api_key", "")
    dimension = int(config.get("embedding_dimension", DEFAULT_DIMENSION))
    warning = None
    if api_key:
        try:
            return dashscope_embeddings(texts, config), f"dashscope:{config['embedding_model']}", None
        except Exception as exc:
            warning = str(exc)
    vectors = [local_hash_embed(text, dimension) for text in texts]
    if not warning and not api_key:
        warning = "未配置 DashScope API Key，已使用本地降级 embedding"
    elif warning:
        warning = f"Embedding 调用失败，已使用本地降级 embedding：{warning}"
    return vectors, "local-hash", warning


def chat_answer(query, hits, config):
    api_key = config.get("api_key", "")
    if not api_key or not hits:
        return None

    context = "\n\n".join(
        f"[{idx + 1}] 文件：{hit['fileName']}\n证据：{hit['snippet']}"
        for idx, hit in enumerate(hits[:5])
    )
    payload = {
        "model": config["chat_model"],
        "messages": [
            {
                "role": "system",
                "content": "你是落知的文件问答助手。只根据给定证据回答，回答要简洁，并指出相关文件；证据不足时明确说明不足。",
            },
            {
                "role": "user",
                "content": f"问题：{query}\n\n证据：\n{context}",
            },
        ],
        "temperature": 0.2,
    }
    response = request_json(config["chat_endpoint"], api_key, payload)
    choices = response.get("choices", [])
    if not choices:
        return None
    return choices[0].get("message", {}).get("content")


def general_chat_answer(query, config):
    api_key = config.get("api_key", "")
    if not api_key:
        raise RuntimeError("未配置 DashScope API Key")

    payload = {
        "model": config["chat_model"],
        "messages": [
            {
                "role": "system",
                "content": "你是落知的通用 AI 助手。直接回答用户问题；如果用户询问本地文件、通知、日程或证据，提醒他们可以明确说“查文件”。回答保持简洁、准确。",
            },
            {"role": "user", "content": query},
        ],
        "temperature": 0.3,
    }
    response = request_json(config["chat_endpoint"], api_key, payload, timeout=30)
    choices = response.get("choices", [])
    if not choices:
        return "没有收到模型回答。"
    return choices[0].get("message", {}).get("content") or "没有收到模型回答。"


def chat_classify(payload, config):
    api_key = config.get("api_key", "")
    if not api_key:
        raise RuntimeError("未配置 DashScope API Key")

    evidence = "\n".join(f"- {item}" for item in payload.get("eventEvidence", [])[:3])
    prompt = f"""
请判断这个下载文件是否真的是需要提醒/待办的通知，并修正摘要标签。

规则：
1. 代码、配置、README、开发文档、教程、讲义、板书、外文故事/阅读材料、OCR乱码，不要标成重要通知。
2. 含考试、报名、缴费、提交截止、面试/宣讲、会议安排等明确行动项，才可标为重要。
3. 不要输出代码片段、密钥、token、乱码或长段原文；只输出简洁中文摘要。
4. 如果不是通知，把 keepEvents 设为 false，priorityLevel 设为“可忽略”或“普通”。
5. 摘要必须过滤页眉、文号、分隔线、目录、公众号水印、“安排如下/通知如下”等版式文本。
6. keyPoints 只能写真正有用的行动信息：时间节点、报名/提交/缴费/考试要求、地点、对象、材料要求。没有就返回“未识别到明确行动项”。
7. keyLocation 只有在文本里有明确地点/教室/会场/地址时填写，否则必须为 null。
8. 只返回 JSON，不要 Markdown。

文件名：{payload.get("fileName", "")}
本地初判优先级：{payload.get("heuristicPriority", "")}
本地事件证据：
{evidence}

正文节选：
{payload.get("text", "")[:5000]}

JSON schema:
{{
  "priorityLevel": "重要|普通|可忽略",
  "keepEvents": true,
  "summary": {{
    "fileTypeLabel": "考试安排|作业说明|报名通知|活动通知|课程资料|代码/配置|阅读材料|普通文件",
    "actionHint": "现在阅读|加入日历|稍后回看|可忽略",
    "keyTime": null,
    "keyLocation": null,
    "keyPoints": ["不超过 3 条，每条不超过 36 个中文字符"],
    "oneLineSummary": "不超过 60 个中文字符"
  }}
}}
"""
    response = request_json(
        config["chat_endpoint"],
        api_key,
        {
            "model": config["chat_model"],
            "messages": [
                {
                    "role": "system",
                    "content": "你是 macOS 文件理解助手的分类器。你必须输出严格 JSON，避免泄露密钥和长段原文。",
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.1,
            "response_format": {"type": "json_object"},
        },
    )
    content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", content, flags=re.S)
        if not match:
            raise RuntimeError("LLM 分类结果不是 JSON")
        return json.loads(match.group(0))


def connect_metadata(store):
    os.makedirs(store, exist_ok=True)
    db = sqlite3.connect(os.path.join(store, "chunks.sqlite3"))
    db.execute(
        """
        create table if not exists chunks (
            chunk_id text primary key,
            file_id text not null,
            revision_id text not null,
            file_name text not null,
            file_path text not null,
            chunk_index integer not null,
            text text not null
        )
        """
    )
    columns = {row[1] for row in db.execute("pragma table_info(chunks)").fetchall()}
    if "revision_id" not in columns:
        db.execute("alter table chunks add column revision_id text not null default ''")
    db.execute(
        """
        create table if not exists active_revisions (
            file_id text primary key,
            revision_id text not null,
            activated_at text not null
        )
        """
    )
    db.execute(
        """
        insert into active_revisions (file_id, revision_id, activated_at)
        select c.file_id,
               coalesce(
                   (
                       select c2.revision_id
                       from chunks c2
                       where c2.file_id = c.file_id
                       order by case when c2.revision_id = '' then 1 else 0 end,
                                c2.revision_id desc,
                                c2.chunk_index asc
                       limit 1
                   ),
                   ''
               ),
               datetime('now')
        from chunks c
        left join active_revisions a on a.file_id = c.file_id
        where a.file_id is null
        group by c.file_id
        """
    )
    db.commit()
    return db


def metadata_diagnostics(store, config=None, api=None):
    db = connect_metadata(store)
    indexed_file_count = db.execute("select count(distinct file_id) from chunks").fetchone()[0]
    chunk_count = db.execute("select count(*) from chunks").fetchone()[0]
    active_revision_count = db.execute("select count(*) from active_revisions").fetchone()[0]
    embedding_model = (config or {}).get("embedding_model")
    chat_model = (config or {}).get("chat_model")
    return {
        "embeddingEngine": None,
        "embeddingModel": embedding_model,
        "chatModel": chat_model,
        "topK": 0,
        "chatUsed": False,
        "fallbackReason": None,
        "indexedFileCount": int(indexed_file_count),
        "chunkCount": int(chunk_count),
        "activeRevisionCount": int(active_revision_count),
        "emptyIndex": int(chunk_count) == 0,
        "providerConfigured": bool((config or {}).get("api_key", "")),
        "zvecAvailable": not (api and "error" in api),
    }


def index_status(payload, store):
    db = connect_metadata(store)
    statuses = []
    for item in payload.get("files", []):
        file_id = item.get("fileID", "")
        expected_revision_id = item.get("expectedRevisionID")
        active_row = db.execute(
            "select revision_id from active_revisions where file_id = ?",
            (file_id,),
        ).fetchone()
        active_revision_id = active_row[0] if active_row else None
        chunk_row = db.execute(
            """
            select count(*)
            from chunks c
            join active_revisions a
              on a.file_id = c.file_id and a.revision_id = c.revision_id
            where c.file_id = ?
            """,
            (file_id,),
        ).fetchone()
        chunk_count = int(chunk_row[0] if chunk_row else 0)
        revision_matches = not expected_revision_id or active_revision_id == expected_revision_id
        statuses.append(
            {
                "fileID": file_id,
                "indexed": bool(active_revision_id and revision_matches and chunk_count > 0),
                "chunkCount": chunk_count,
                "activeRevisionID": active_revision_id,
                "expectedRevisionID": expected_revision_id,
            }
        )
    emit({"ok": True, "engine": "metadata", "files": statuses})
    return 0


def load_zvec():
    try:
        import zvec
        from zvec import DataType, Doc, FieldSchema, HnswIndexParam, InvertIndexParam, VectorQuery, VectorSchema

        return {
            "zvec": zvec,
            "DataType": DataType,
            "Doc": Doc,
            "FieldSchema": FieldSchema,
            "HnswIndexParam": HnswIndexParam,
            "InvertIndexParam": InvertIndexParam,
            "VectorQuery": VectorQuery,
            "VectorSchema": VectorSchema,
        }
    except Exception as exc:
        return {"error": str(exc)}


def collection_path(store, config):
    model = re.sub(r"[^A-Za-z0-9_.-]+", "_", config["embedding_model"])
    return os.path.join(store, f"zvec_collection_{model}_{int(config['embedding_dimension'])}")


def open_collection(store, api, config):
    zvec = api["zvec"]
    DataType = api["DataType"]
    FieldSchema = api["FieldSchema"]
    HnswIndexParam = api["HnswIndexParam"]
    InvertIndexParam = api["InvertIndexParam"]
    VectorSchema = api["VectorSchema"]

    path = collection_path(store, config)
    dimension = int(config["embedding_dimension"])
    try:
        try:
            zvec.init()
        except RuntimeError:
            pass

        return zvec.open(path)
    except Exception:
        schema = zvec.CollectionSchema(
            name="dropknow_chunks",
            fields=[
                FieldSchema("file_id", DataType.STRING, nullable=False, index_param=InvertIndexParam()),
                FieldSchema("file_name", DataType.STRING, nullable=False, index_param=InvertIndexParam()),
                FieldSchema("file_path", DataType.STRING, nullable=False),
                FieldSchema("chunk_index", DataType.INT32, nullable=False),
            ],
            vectors=[
                VectorSchema("embedding", DataType.VECTOR_FP32, dimension=dimension, index_param=HnswIndexParam())
            ],
        )
        return zvec.create_and_open(path, schema=schema)


def index(payload, store):
    file_id = payload["fileID"]
    revision_id = payload.get("revisionID") or hashlib.sha1(file_id.encode("utf-8")).hexdigest()
    batch_payload = {
        "files": [
            {
                "fileID": file_id,
                "fileName": payload["fileName"],
                "filePath": payload["filePath"],
                "contentHash": payload.get("contentHash", ""),
                "revisionID": revision_id,
                "chunks": payload.get("chunks", []),
            }
        ]
    }
    return index_batch(batch_payload, store)


def index_batch(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": "config", "errorCode": exc.code, "error": str(exc)})
        return 0
    api = load_zvec()
    if "error" in api:
        emit({"ok": False, "engine": "zvec", "errorCode": "MISSING_ZVEC", "error": "Python 环境缺少 zvec：" + api["error"]})
        return 0

    db = connect_metadata(store)
    collection = open_collection(store, api, config)
    Doc = api["Doc"]

    files = payload.get("files", [])
    all_chunks = []
    for item in files:
        all_chunks.extend(item.get("chunks", []))
    vectors, embedding_engine, embedding_warning = embed_texts(all_chunks, config)
    engine = f"zvec + {embedding_engine}"

    docs = []
    results = []
    vector_offset = 0
    try:
        for item in files:
            file_id = item["fileID"]
            revision_id = item["revisionID"]
            chunks = item.get("chunks", [])
            db.execute("delete from chunks where file_id = ? and revision_id = ?", (file_id, revision_id))

            for index, chunk in enumerate(chunks):
                chunk_id = "c_" + hashlib.sha1(f"{file_id}:{revision_id}:{index}".encode("utf-8")).hexdigest()
                db.execute(
                    "insert or replace into chunks values (?, ?, ?, ?, ?, ?, ?)",
                    (chunk_id, file_id, revision_id, item["fileName"], item["filePath"], index, chunk),
                )
                docs.append(
                    Doc(
                        id=chunk_id,
                        fields={
                            "file_id": file_id,
                            "file_name": item["fileName"],
                            "file_path": item["filePath"],
                            "chunk_index": index,
                        },
                        vectors={"embedding": vectors[vector_offset]},
                    )
                )
                vector_offset += 1

            db.execute(
                "insert or replace into active_revisions values (?, ?, datetime('now'))",
                (file_id, revision_id),
            )
            results.append({"fileID": file_id, "revisionID": revision_id})

        if docs:
            collection.upsert(docs)
            collection.flush()
        db.commit()
        emit({"ok": True, "engine": engine, "warning": embedding_warning, "results": results})
        return 0
    except Exception as exc:
        db.rollback()
        emit({"ok": False, "engine": "zvec", "errorCode": "INDEX_FAILED", "error": str(exc)})
        return 0


def search(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": "config", "errorCode": exc.code, "error": str(exc)})
        return 0
    api = load_zvec()
    if "error" in api:
        emit({"ok": False, "engine": "zvec", "errorCode": "MISSING_ZVEC", "error": "Python 环境缺少 zvec：" + api["error"]})
        return 0

    db = connect_metadata(store)
    collection = open_collection(store, api, config)
    VectorQuery = api["VectorQuery"]
    query = payload["query"]
    top_k = int(payload.get("topK", 6))
    vectors, embedding_engine, embedding_warning = embed_texts([query], config)
    query_vector = vectors[0]

    docs = collection.query(
        vectors=VectorQuery("embedding", vector=query_vector),
        topk=top_k,
        output_fields=["file_id", "file_name", "file_path", "chunk_index"],
    )

    hits = direct_file_hits(db, query, top_k)
    seen_chunk_ids = {hit["id"] for hit in hits}
    for doc in docs:
        if doc.id in seen_chunk_ids:
            continue
        row = db.execute(
            """
            select c.file_id, c.file_name, c.file_path, c.text, c.chunk_index, c.revision_id
            from chunks c
            join active_revisions a
              on a.file_id = c.file_id and a.revision_id = c.revision_id
            where c.chunk_id = ?
            """,
            (doc.id,),
        ).fetchone()
        if not row:
            continue
        hits.append(
            {
                "id": doc.id,
                "fileID": row[0],
                "fileName": row[1],
                "filePath": row[2],
                "snippet": row[3][:700],
                "score": float(doc.score),
                "chunkIndex": int(row[4]),
                "revisionID": row[5],
                "matchReason": "命中文件片段",
            }
        )
        seen_chunk_ids.add(doc.id)
        if len(hits) >= top_k:
            break

    chat_warning = None
    chat_used = False
    if hits:
        try:
            answer = chat_answer(query, hits, config)
            chat_used = bool(answer)
        except Exception as exc:
            chat_warning = str(exc)
            answer = None
        if not answer:
            answer = f"最相关的是《{hits[0]['fileName']}》：{hits[0]['snippet'][:180]}"
    else:
        answer = "没有找到足够相关的证据。"

    api_key = config.get("api_key", "")
    warning = embedding_warning
    if chat_warning:
        warning = chat_warning if not warning else f"{warning}；{chat_warning}"
    if not api_key or (api_key and not chat_used):
        warning = warning or "已进入本地降级模式（不调用远端问答/精修）"
    diag = metadata_diagnostics(store, config=config, api=api)
    diag["embeddingEngine"] = embedding_engine
    diag["topK"] = top_k
    diag["chatUsed"] = chat_used
    if warning:
        diag["fallbackReason"] = "LOCAL_FALLBACK" if not chat_used else "CHAT_WARNING"
    emit(
        {
            "ok": True,
            "queryMode": "fileSearch" if chat_used else "localFallback",
            "engine": f"zvec + {embedding_engine}" + (f" + {config['chat_model']}" if chat_used else " + local-answer"),
            "answer": answer,
            "hits": hits,
            "warning": warning,
            "diagnostics": diag,
        }
    )
    return 0


def diagnostics(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        config = {}
        config_error = {"code": exc.code, "message": str(exc)}
    else:
        config_error = None
    api = load_zvec()
    result = metadata_diagnostics(store, config=config, api=api)
    if "error" in api:
        result["fallbackReason"] = "MISSING_ZVEC"
        result["zvecError"] = api["error"]
    if config_error:
        result["fallbackReason"] = config_error["code"]
        result["providerError"] = config_error["message"]
    emit({"ok": True, "engine": "diagnostics", "diagnostics": result})
    return 0


def refine(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": "config", "errorCode": exc.code, "error": str(exc)})
        return 0
    if not config.get("api_key", ""):
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": "MISSING_API_KEY", "error": "未配置 DashScope API Key"})
        return 0
    try:
        refined = chat_classify(payload, config)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": exc.code, "error": str(exc)})
        return 0
    except Exception as exc:
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": "REFINE_FAILED", "error": str(exc)})
        return 0

    summary = refined.get("summary") or {}
    key_points = summary.get("keyPoints") or []
    if not isinstance(key_points, list):
        key_points = []
    normalized_summary = {
        "fileTypeLabel": str(summary.get("fileTypeLabel") or "普通文件")[:24],
        "actionHint": str(summary.get("actionHint") or "稍后回看")[:24],
        "keyTime": summary.get("keyTime"),
        "keyLocation": summary.get("keyLocation"),
        "keyPoints": [str(item)[:80] for item in key_points[:3]] or ["暂无明确行动项"],
        "oneLineSummary": str(summary.get("oneLineSummary") or "已完成文件理解。")[:120],
    }
    priority = refined.get("priorityLevel")
    if priority not in ("重要", "普通", "可忽略"):
        priority = "普通"
    keep_events = bool(refined.get("keepEvents", False))
    emit(
        {
            "ok": True,
            "engine": config["chat_model"],
            "summary": normalized_summary,
            "priorityLevel": priority,
            "keepEvents": keep_events,
            "warning": None,
        }
    )
    return 0


def chat(payload, store):
    try:
        config = load_provider_config(store)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": "config", "errorCode": exc.code, "error": str(exc)})
        return 0
    if not config.get("api_key", ""):
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": "MISSING_API_KEY", "error": "未配置 DashScope API Key"})
        return 0
    try:
        answer = general_chat_answer(payload.get("query", ""), config)
    except UserVisibleError as exc:
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": exc.code, "error": str(exc)})
        return 0
    except Exception as exc:
        emit({"ok": False, "engine": config.get("chat_model", "qwen"), "errorCode": "CHAT_FAILED", "error": str(exc)})
        return 0

    emit(
        {
            "ok": True,
            "engine": config["chat_model"],
            "answer": answer,
            "hits": [],
            "warning": None,
        }
    )
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["index", "index_batch", "index_status", "search", "refine", "chat", "diagnostics"])
    parser.add_argument("--store", required=True)
    args = parser.parse_args()

    payload = json.load(sys.stdin)
    if args.mode == "index":
        return index(payload, args.store)
    if args.mode == "index_batch":
        return index_batch(payload, args.store)
    if args.mode == "index_status":
        return index_status(payload, args.store)
    if args.mode == "refine":
        return refine(payload, args.store)
    if args.mode == "chat":
        return chat(payload, args.store)
    if args.mode == "diagnostics":
        return diagnostics(payload, args.store)
    return search(payload, args.store)


if __name__ == "__main__":
    raise SystemExit(main())
