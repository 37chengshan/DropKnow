#!/usr/bin/env python3
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "Sources" / "DropKnow" / "Scripts" / "rag_helper.py"
FIXTURE_DIR = ROOT / "Tests" / "fixtures" / "rag"


def run_helper(mode, store, payload):
    process = subprocess.run(
        [sys.executable, str(HELPER), mode, "--store", str(store)],
        input=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.stderr:
        sys.stderr.write(process.stderr.decode("utf-8", errors="replace"))
    try:
        return json.loads(process.stdout.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise AssertionError(f"helper returned non-json output: {process.stdout!r}") from exc


def chunk_text(text):
    paragraphs = [line.strip() for line in text.splitlines() if line.strip()]
    return ["\n".join(paragraphs)]


def fixture_file_payload(path):
    text = path.read_text(encoding="utf-8")
    file_id = hashlib.sha1(str(path).encode("utf-8")).hexdigest()
    revision_id = hashlib.sha1(text.encode("utf-8")).hexdigest()
    return {
        "fileID": file_id,
        "fileName": path.name,
        "filePath": str(path),
        "contentHash": revision_id,
        "revisionID": revision_id,
        "chunks": chunk_text(text),
    }


def assert_hit(response, expected_file, expected_phrase):
    assert response.get("ok") is True, response
    hits = response.get("hits") or []
    names = [hit.get("fileName") for hit in hits]
    assert expected_file in names, f"expected {expected_file} in hits, got {names}"
    joined = "\n".join(hit.get("snippet", "") for hit in hits if hit.get("fileName") == expected_file)
    assert expected_phrase in joined, f"expected phrase {expected_phrase!r} in evidence for {expected_file}: {joined}"


def main():
    with tempfile.TemporaryDirectory(prefix="dropknow-rag-fixtures-") as tmp:
        store = Path(tmp) / "rag_store"
        files = [fixture_file_payload(path) for path in sorted(FIXTURE_DIR.iterdir()) if path.is_file()]
        index_response = run_helper("index_batch", store, {"files": files})
        assert index_response.get("ok") is True, index_response

        cases = [
            ("高等数学考试在哪天", "exam_notice.txt", "2026 年 6 月 18 日"),
            ("报名截止是什么时候", "registration_deadline.txt", "2026 年 5 月 28 日 18:00"),
            ("计算机网络调到哪个教室", "class_schedule.md", "B203"),
        ]
        for query, expected_file, expected_phrase in cases:
            response = run_helper("search", store, {"query": query, "topK": 6})
            assert_hit(response, expected_file, expected_phrase)

        print("RAG fixture verification passed: indexed fixtures and matched expected evidence.")


if __name__ == "__main__":
    main()
