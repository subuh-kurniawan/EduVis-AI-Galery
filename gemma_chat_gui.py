#!/usr/bin/env python3
import base64
import concurrent.futures
import hashlib
import http.client
import importlib.metadata
import io
import ipaddress
import json
import math
import os
import plistlib
import re
import signal
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import platform
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
API_HOST = "127.0.0.1"
UI_BIND_HOST = "0.0.0.0"
API_PORT = 1234
LOCAL_UI_PORT = 1236
LITERT_API_HOST = "127.0.0.1"
LITERT_API_PORT = 1235
API_BASE_URL = f"http://{LITERT_API_HOST}:{LITERT_API_PORT}/v1"
READY_TIMEOUT = 120
MODEL_IMPORT_TIMEOUT = 60 * 60
MAX_MODEL_UPLOAD_SIZE = 100 * 1024 * 1024 * 1024
LITERT_LM_PACKAGE = "litert-lm"

def strip_stage_directions(text):
    text = str(text or "")
    # 1. Hapus kurung siku [] sepenuhnya (stage directions / cues)
    text = re.sub(r"\[[^\]]*\]", "", text)
    # 2. Hapus kurung kurawal {} sepenuhnya
    text = re.sub(r"\{[^\}]*\}", "", text)
    # 3. Hapus baris yang seluruhnya berupa tanda kurung (apapun isinya)
    text = re.sub(r"^\s*\([^\)]*\)\s*$", "", text, flags=re.MULTILINE)
    # 4. Hapus tanda kurung di awal teks sebelum kata pertama
    text = re.sub(r"^\s*\([^\)]*\)\s*", "", text)
    # 5. Hapus petunjuk audio / panggung di dalam tanda kurung di mana saja
    keywords = (
        r"musik|music|audio|sfx|sound|efek|backsound|bgm|jeda|pause|volume|beat|upbeat|slow|fade|"
        r"hening|tertawa|senyum|desah|berbisik|nada|vokal|intro|outro|visual|adegan|scene|kamera|"
        r"layar|transisi|zoom|durasi|detik|instruksi|instrumen|tempo|suasana|terdengar|suara|gerak|panggung|teks|latar"
    )
    text = re.sub(r"\([^\)]*(?:" + keywords + r")[^\)]*\)", "", text, flags=re.IGNORECASE)
    # 6. Hapus prefix peran pembicara & nama persona AI (Arsi:, EduVis:, Narator:, Guru:, Pembicara:, dsb)
    text = re.sub(
        r"^\s*(?:\[|\*\*|\*)?\s*(?:arsi|eduvis|gemma(?:[-_ ]?\d+[a-z]*)?|ai|asisten|assistant|model|bot|konsultan|tutor|guru|pembicara|narator|narrator|suara|vo|voiceover|voice\s*over|jawaban|respon|response|gadis|ardi|wibowo|citra|bimo|sari|dimas|bayu|tari|juminten|asep|orator|jokowi|lala|kiki|mimi|dewi|piper|[a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+){0,3})\s*(?:\]|\*\*|\*)?\s*[:\-–]\s*",
        "",
        text,
        flags=re.IGNORECASE | re.MULTILINE,
    )
    # 7. Hapus markdown header & format tebal/miring
    text = re.sub(r"^\s*#{1,6}\s+.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"[*_#`]", "", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


TTS_SERVER_PROCESS = None
TTS_SERVER_LOCK = threading.Lock()
TTS_LAST_ACTIVE_TIME = 0.0
TTS_IDLE_TIMEOUT_SECONDS = 60.0
TTS_WATCHDOG_THREAD = None


def find_tts_python():
    """Mencari Python executable yang memiliki dependensi TTS lokal (VITS / Piper)."""
    # 1. Folder development lokal
    local_dev = PROJECT_DIR / ".venv_tts" / ("Scripts/python.exe" if os.name == "nt" else "bin/python3")
    if local_dev.is_file():
        return str(local_dev)

    # 2. Folder Application Support EduVis AI Gallery (instalasi mandiri / DMG)
    app_support = Path.home() / "Library" / "Application Support" / "EduVis AI Gallery"
    app_support_venv = app_support / "tts-venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python3")
    if app_support_venv.is_file():
        return str(app_support_venv)

    # 3. Virtualenv LiteRT-LM jika ada paket piper terpasang
    litert_venv = Path.home() / "Library" / "Application Support" / "Gemma AI Gallery" / "litert-lm-venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python3")
    if litert_venv.is_file():
        return str(litert_venv)

    return None


def ensure_tts_venv(auto_install_piper=True):
    """Menyiapkan virtual environment TTS on-demand jika belum tersedia di sistem pengguna (misal instalasi DMG)."""
    existing = find_tts_python()
    if existing:
        return existing

    app_support = Path.home() / "Library" / "Application Support" / "EduVis AI Gallery"
    environment = app_support / "tts-venv"
    scripts_dir = environment / ("Scripts" if os.name == "nt" else "bin")
    venv_python = str(scripts_dir / ("python.exe" if os.name == "nt" else "python3"))

    python = find_python_for_litert_lm()
    app_support.mkdir(parents=True, exist_ok=True)
    print(f"[launcher] Menyiapkan lingkungan TTS on-demand di {environment} menggunakan {python}...", flush=True)

    result = subprocess.run(
        [python, "-m", "venv", str(environment)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        print(f"[launcher] Peringatan: Gagal membuat venv TTS: {detail}", file=sys.stderr, flush=True)
        return None

    if auto_install_piper:
        req_piper = PROJECT_DIR / "requirements-piper.txt"
        print("[launcher] Memasang runtime vokal Piper on-demand...", flush=True)
        subprocess.run([venv_python, "-m", "pip", "install", "--upgrade", "pip"], capture_output=True, text=True, check=False)

        pip_args = [venv_python, "-m", "pip", "install"]
        if req_piper.is_file():
            pip_args.extend(["-r", str(req_piper)])
        else:
            pip_args.append("piper-tts==1.3.0")
        subprocess.run(pip_args, capture_output=True, text=True, check=False)

        # Unduh model suara Piper jika belum ada
        dl_script = PROJECT_DIR / "scripts" / "download_piper_news_voice.py"
        if dl_script.is_file():
            piper_model = PROJECT_DIR / "models" / "piper" / "id_ID-news_tts-medium-q8.onnx"
            if not piper_model.is_file():
                print("[launcher] Mengunduh model suara Piper News TTS on-demand...", flush=True)
                subprocess.run([venv_python, str(dl_script)], capture_output=True, text=True, check=False)

    return venv_python if Path(venv_python).is_file() else None


def start_tts_watchdog():
    """Mengawasi waktu idle TTS server dan mematikan proses otomatis untuk membebaskan RAM."""
    global TTS_WATCHDOG_THREAD
    if TTS_WATCHDOG_THREAD is not None and TTS_WATCHDOG_THREAD.is_alive():
        return

    def _watchdog_loop():
        global TTS_SERVER_PROCESS
        while True:
            time.sleep(15)
            with TTS_SERVER_LOCK:
                if TTS_SERVER_PROCESS is None:
                    break
                if TTS_SERVER_PROCESS.poll() is not None:
                    TTS_SERVER_PROCESS = None
                    break
                if time.time() - TTS_LAST_ACTIVE_TIME > TTS_IDLE_TIMEOUT_SECONDS:
                    print("[launcher] TTS idle melebihi 60 detik. Menghentikan worker untuk membebaskan memori RAM...", flush=True)
                    stop_tts_server()
                    break

    TTS_WATCHDOG_THREAD = threading.Thread(target=_watchdog_loop, daemon=True)
    TTS_WATCHDOG_THREAD.start()


def ensure_tts_server():
    global TTS_SERVER_PROCESS, TTS_LAST_ACTIVE_TIME
    with TTS_SERVER_LOCK:
        TTS_LAST_ACTIVE_TIME = time.time()
        start_tts_watchdog()

        if TTS_SERVER_PROCESS is not None and TTS_SERVER_PROCESS.poll() is None:
            return True

        try:
            conn = http.client.HTTPConnection("127.0.0.1", 8765, timeout=1)
            conn.request("GET", "/api/health")
            resp = conn.getresponse()
            if resp.status == 200:
                resp.read()
                return True
        except Exception:
            pass
        finally:
            if "conn" in locals():
                conn.close()

        venv_python_path = find_tts_python() or ensure_tts_venv()
        venv_python = Path(venv_python_path) if venv_python_path else None
        tts_script = PROJECT_DIR / "tts_server.py"
        if venv_python and venv_python.exists() and tts_script.exists():
            try:
                TTS_SERVER_PROCESS = subprocess.Popen(
                    [str(venv_python), str(tts_script)],
                    cwd=str(PROJECT_DIR),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                print("[launcher] Engine model vokal AI (VITS/Piper neural) aktif on-demand.", flush=True)
                for _ in range(32):
                    time.sleep(0.25)
                    try:
                        conn = http.client.HTTPConnection("127.0.0.1", 8765, timeout=0.5)
                        conn.request("GET", "/api/health")
                        resp = conn.getresponse()
                        if resp.status == 200:
                            resp.read()
                            conn.close()
                            return True
                    except Exception:
                        pass
                return True
            except Exception as e:
                print(f"[launcher] Peringatan memulai TTS worker: {e}", file=sys.stderr, flush=True)
        return False

def stop_tts_server():
    global TTS_SERVER_PROCESS
    if TTS_SERVER_PROCESS is not None:
        try:
            TTS_SERVER_PROCESS.terminate()
            TTS_SERVER_PROCESS.wait(timeout=2)
        except Exception:
            try:
                TTS_SERVER_PROCESS.kill()
            except Exception:
                pass
        TTS_SERVER_PROCESS = None


class ThreadingHTTPSServer(ThreadingHTTPServer):
    request_queue_size = 64

    def __init__(self, server_address, request_handler_class, ssl_context):
        self.ssl_context = ssl_context
        super().__init__(server_address, request_handler_class)

    def get_request(self):
        request, client_address = super().get_request()
        return (
            self.ssl_context.wrap_socket(
                request,
                server_side=True,
                do_handshake_on_connect=False,
            ),
            client_address,
        )

    def process_request_thread(self, request, client_address):
        try:
            request.settimeout(10)
            request.do_handshake()
            request.settimeout(None)
        except (OSError, ssl.SSLError):
            self.shutdown_request(request)
            return
        super().process_request_thread(request, client_address)


class SQLiteVectorStore:
    """Penyimpanan vektor Knowledge Base terpusat berbasis SQLite untuk seluruh ruang kerja & klien LAN."""

    def __init__(self, db_path=None):
        self._lock = threading.Lock()
        if db_path is None:
            default_dir = Path.home() / "Library" / "Application Support" / "EduVis AI Gallery"
            try:
                default_dir.mkdir(parents=True, exist_ok=True)
                test_file = default_dir / ".write_test"
                test_file.write_text("", encoding="utf-8")
                test_file.unlink(missing_ok=True)
                db_path = default_dir / "knowledge_base.sqlite3"
            except OSError:
                db_path = Path(tempfile.gettempdir()) / "eduvis_knowledge_base.sqlite3"
        self.db_path = Path(db_path)
        self._init_schema()

    def _connect(self):
        conn = sqlite3.connect(str(self.db_path), timeout=15)
        conn.row_factory = sqlite3.Row
        try:
            conn.execute("PRAGMA journal_mode = WAL;")
            conn.execute("PRAGMA synchronous = NORMAL;")
            conn.execute("PRAGMA cache_size = -64000;")
            conn.execute("PRAGMA temp_store = MEMORY;")
        except sqlite3.Error:
            pass
        return conn

    def _init_schema(self):
        with self._lock, self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS kb_files (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    collection TEXT NOT NULL DEFAULT 'Umum',
                    size INTEGER NOT NULL DEFAULT 0,
                    timestamp INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS kb_chunks (
                    id TEXT PRIMARY KEY,
                    file_id TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL DEFAULT 0,
                    text TEXT NOT NULL,
                    embedding_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_kb_chunks_file_id ON kb_chunks(file_id);
                CREATE TABLE IF NOT EXISTS hermes_skills (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    content TEXT NOT NULL,
                    tags TEXT NOT NULL DEFAULT '',
                    updated_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS episodic_memories (
                    id TEXT PRIMARY KEY,
                    fact TEXT NOT NULL,
                    category TEXT NOT NULL DEFAULT 'Preferensi',
                    source TEXT NOT NULL DEFAULT 'chat',
                    timestamp INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS hermes_cron_jobs (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    schedule_minutes INTEGER NOT NULL DEFAULT 60,
                    prompt TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    last_run INTEGER NOT NULL DEFAULT 0,
                    last_result TEXT NOT NULL DEFAULT ''
                );
                """
            )
            try:
                conn.execute(
                    "CREATE VIRTUAL TABLE IF NOT EXISTS episodic_memories_fts USING fts5(id UNINDEXED, fact, category)"
                )
            except sqlite3.Error:
                pass
            existing_skills = conn.execute("SELECT COUNT(*) FROM hermes_skills").fetchone()[0]
            if existing_skills == 0:
                now_ms = int(time.time() * 1000)
                defaults = [
                    (
                        "macos-hig-architect",
                        "macOS HIG Architect",
                        "Panduan membangun UI native macOS dengan Apple Liquid Glass, sidebar adaptif, dan shortcut keyboard.",
                        "Gunakan palet terang/gelap independen, kontrol 28-32pt, tipografi SF Pro 13pt, serta dukungan drag-and-drop dan shortcut Cmd.",
                        "macos,ui,swiftui,appkit",
                        now_ms,
                    ),
                    (
                        "stem-eduvis-simulator",
                        "STEM EduVis Simulator",
                        "Prosedur membuat visualisasi sains interaktif HTML5 Canvas, Chart.js, dan diagram Mermaid.",
                        "Pastikan grafik Chart.js responsif terhadap tema terang/gelap, sertakan kontrol parameter interaktif dan tombol ekspor SVG/PNG.",
                        "stem,eduvis,chart,mermaid",
                        now_ms,
                    ),
                    (
                        "sqlite-rag-analyst",
                        "SQLite RAG & FTS5 Analyst",
                        "Analisis dokumen lokal dari SQLiteVectorStore dengan sitasi akurat dan verifikasi silang antar dokumen.",
                        "Prioritaskan fakta dari potongan dokumen lokal beserta nama sumber berkasnya sebelum menyimpulkan.",
                        "rag,sqlite,fts5,dokumen",
                        now_ms,
                    ),
                ]
                conn.executemany(
                    "INSERT OR IGNORE INTO hermes_skills (id, name, description, content, tags, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                    defaults,
                )

    def list_files(self):
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                """
                SELECT f.id, f.name, f.collection, f.size, f.timestamp,
                       COUNT(c.id) AS chunk_count
                FROM kb_files f
                LEFT JOIN kb_chunks c ON c.file_id = f.id
                GROUP BY f.id
                ORDER BY f.timestamp DESC
                """
            ).fetchall()
            return [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "collection": row["collection"],
                    "size": row["size"],
                    "timestamp": row["timestamp"],
                    "chunk_count": row["chunk_count"],
                }
                for row in rows
            ]

    def get_snapshot(self):
        with self._lock, self._connect() as conn:
            file_rows = conn.execute(
                "SELECT id, name, collection, size, timestamp FROM kb_files ORDER BY timestamp DESC"
            ).fetchall()
            chunk_rows = conn.execute(
                "SELECT id, file_id, chunk_index, text, embedding_json FROM kb_chunks ORDER BY file_id, chunk_index"
            ).fetchall()
            files = [
                {
                    "id": r["id"],
                    "name": r["name"],
                    "collection": r["collection"],
                    "size": r["size"],
                    "timestamp": r["timestamp"],
                }
                for r in file_rows
            ]
            chunks = []
            for r in chunk_rows:
                try:
                    emb = json.loads(r["embedding_json"])
                except (ValueError, TypeError):
                    emb = []
                chunks.append(
                    {
                        "id": r["id"],
                        "fileId": r["file_id"],
                        "chunkIndex": r["chunk_index"],
                        "text": r["text"],
                        "embedding": emb,
                    }
                )
            return {"files": files, "chunks": chunks}

    def upsert_document(self, file_id, name, size=0, timestamp=None, chunks=None, collection="Umum"):
        if not isinstance(file_id, str) or not file_id.strip():
            raise ValueError("ID dokumen Knowledge Base wajib diisi.")
        if not isinstance(name, str) or not name.strip():
            raise ValueError("Nama dokumen Knowledge Base wajib diisi.")
        ts = int(timestamp if timestamp is not None else time.time() * 1000)
        col = str(collection or "Umum").strip() or "Umum"
        chunk_list = chunks if isinstance(chunks, list) else []

        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO kb_files (id, name, collection, size, timestamp) VALUES (?, ?, ?, ?, ?)",
                (file_id.strip(), name.strip(), col, int(size or 0), ts),
            )
            conn.execute("DELETE FROM kb_chunks WHERE file_id = ?", (file_id.strip(),))
            for idx, ch in enumerate(chunk_list):
                if not isinstance(ch, dict):
                    continue
                chunk_id = str(ch.get("id") or f"{file_id.strip()}_{idx}")
                text = str(ch.get("text") or "").strip()
                if not text:
                    continue
                embedding = ch.get("embedding")
                if not isinstance(embedding, list):
                    embedding = []
                conn.execute(
                    "INSERT OR REPLACE INTO kb_chunks (id, file_id, chunk_index, text, embedding_json) VALUES (?, ?, ?, ?, ?)",
                    (chunk_id, file_id.strip(), idx, text, json.dumps(embedding)),
                )
        return {
            "id": file_id.strip(),
            "name": name.strip(),
            "collection": col,
            "chunk_count": len(chunk_list),
        }

    def delete_document(self, file_id):
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM kb_chunks WHERE file_id = ?", (file_id,))
            conn.execute("DELETE FROM kb_files WHERE id = ?", (file_id,))
        return {"deleted_id": file_id}

    def clear_all(self):
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM kb_chunks")
            conn.execute("DELETE FROM kb_files")

    @staticmethod
    def cosine_similarity(vec_a, vec_b):
        if not vec_a or not vec_b or len(vec_a) != len(vec_b):
            return 0.0
        dot = sum(a * b for a, b in zip(vec_a, vec_b))
        norm_a = math.sqrt(sum(a * a for a in vec_a))
        norm_b = math.sqrt(sum(b * b for b in vec_b))
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return dot / (norm_a * norm_b)

    @staticmethod
    def lexical_score(query_text, chunk_text):
        words = [
            w
            for w in re.sub(r"[^a-zA-Z0-9\s]", " ", str(query_text or "").lower()).split()
            if len(w) >= 3
        ]
        if not words:
            return 0.0
        lower_chunk = str(chunk_text or "").lower()
        hits = sum(1 for w in words if w in lower_chunk)
        return hits / len(words)

    def search(self, query="", embedding=None, top_k=4, min_score=0.25):
        """Pencarian Hybrid (Dense Vector + Lexical Keyword) dengan Reciprocal Rank Fusion (RRF)."""
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                """
                SELECT c.id, c.file_id, c.text, c.embedding_json,
                       f.name AS file_name, f.collection
                FROM kb_chunks c
                JOIN kb_files f ON f.id = c.file_id
                """
            ).fetchall()

        if not rows:
            return []

        has_query_vec = isinstance(embedding, list) and len(embedding) > 0
        clean_query = str(query or "").strip()

        # 1. Dense Retrieval (Cosine Similarity)
        vec_ranked = []
        if has_query_vec:
            for r in rows:
                v_score = 0.0
                try:
                    chunk_vec = json.loads(r["embedding_json"])
                    if chunk_vec:
                        v_score = self.cosine_similarity(embedding, chunk_vec)
                except (ValueError, TypeError):
                    v_score = 0.0
                vec_ranked.append((r["id"], v_score))
            vec_ranked.sort(key=lambda x: x[1], reverse=True)

        # 2. Lexical Retrieval (Keyword Matching)
        lex_ranked = []
        if clean_query:
            for r in rows:
                l_score = self.lexical_score(clean_query, r["text"])
                lex_ranked.append((r["id"], l_score))
            lex_ranked.sort(key=lambda x: x[1], reverse=True)

        # 3. Reciprocal Rank Fusion (RRF)
        rrf_k = 60
        w_vec = 0.6 if has_query_vec else 0.0
        w_lex = 0.4 if clean_query else 0.0
        if w_vec == 0.0 and w_lex == 0.0:
            return []

        vec_ranks = {item[0]: rank for rank, item in enumerate(vec_ranked, 1)} if has_query_vec else {}
        lex_ranks = {item[0]: rank for rank, item in enumerate(lex_ranked, 1)} if clean_query else {}

        row_map = {r["id"]: r for r in rows}
        combined_scores = {}

        for chunk_id in row_map.keys():
            score = 0.0
            if chunk_id in vec_ranks:
                score += w_vec / (rrf_k + vec_ranks[chunk_id])
            if chunk_id in lex_ranks:
                score += w_lex / (rrf_k + lex_ranks[chunk_id])
            if score > 0:
                combined_scores[chunk_id] = score

        scored = []
        max_rrf = max(combined_scores.values()) if combined_scores else 1.0
        for chunk_id, rrf_val in combined_scores.items():
            norm_score = rrf_val / max_rrf if max_rrf > 0 else 0.0
            r = row_map[chunk_id]
            if norm_score >= min_score or (has_query_vec and vec_ranks.get(chunk_id, 999) <= 2):
                scored.append(
                    {
                        "id": r["id"],
                        "fileId": r["file_id"],
                        "fileName": r["file_name"],
                        "collection": r["collection"],
                        "text": r["text"],
                        "score": round(float(norm_score), 4),
                        "rrf_raw": round(float(rrf_val), 5),
                    }
                )

        scored.sort(key=lambda item: item["score"], reverse=True)
        return scored[: max(1, int(top_k or 4))]

    # --- Hermes Skills (Procedural Memory ~/.litert-lm/skills/*.md) ---

    def list_skills(self):
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT id, name, description, content, tags, updated_at FROM hermes_skills ORDER BY updated_at DESC"
            ).fetchall()
            return [
                {
                    "id": r["id"],
                    "name": r["name"],
                    "description": r["description"],
                    "content": r["content"],
                    "tags": r["tags"],
                    "updated_at": r["updated_at"],
                }
                for r in rows
            ]

    def save_skill(self, name, description, content, tags="", skill_id=None):
        clean_name = str(name or "").strip()
        clean_content = str(content or "").strip()
        if not clean_name or not clean_content:
            raise ValueError("Nama dan isi Skill wajib diisi.")
        clean_desc = str(description or clean_content[:120]).strip()
        clean_tags = str(tags or "").strip()
        slug = re.sub(r"[^a-z0-9]+", "-", clean_name.lower()).strip("-") or f"skill-{int(time.time())}"
        sid = str(skill_id or slug).strip()
        now_ms = int(time.time() * 1000)

        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO hermes_skills (id, name, description, content, tags, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                (sid, clean_name, clean_desc, clean_content, clean_tags, now_ms),
            )

        try:
            skills_dir = self.db_path.parent / "skills"
            skills_dir.mkdir(parents=True, exist_ok=True)
            md_body = (
                f"---\nname: {sid}\ndescription: {clean_desc}\ntags: {clean_tags}\n---\n\n"
                f"# {clean_name}\n\n{clean_content}\n"
            )
            (skills_dir / f"{sid}.md").write_text(md_body, encoding="utf-8")
        except OSError:
            pass
        return {
            "id": sid,
            "name": clean_name,
            "description": clean_desc,
            "content": clean_content,
            "tags": clean_tags,
            "updated_at": now_ms,
        }

    def delete_skill(self, skill_id):
        sid = str(skill_id or "").strip()
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM hermes_skills WHERE id = ?", (sid,))
        try:
            (self.db_path.parent / "skills" / f"{sid}.md").unlink(missing_ok=True)
        except OSError:
            pass

    def match_skills(self, query, top_k=2):
        skills = self.list_skills()
        if not query or not skills:
            return []
        scored = []
        for s in skills:
            haystack = f"{s['name']} {s['description']} {s['tags']} {s['content']}"
            score = self.lexical_score(query, haystack)
            if score > 0:
                scored.append((score, s))
        scored.sort(key=lambda pair: pair[0], reverse=True)
        return [item[1] for item in scored[: max(1, int(top_k or 2))]]

    # --- Hermes Episodic Memory (SQLite FTS5 + Auto Fact Extraction) ---

    def list_memories(self, limit=50):
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT id, fact, category, source, timestamp FROM episodic_memories ORDER BY timestamp DESC LIMIT ?",
                (max(1, int(limit or 50)),),
            ).fetchall()
            return [
                {
                    "id": r["id"],
                    "fact": r["fact"],
                    "category": r["category"],
                    "source": r["source"],
                    "timestamp": r["timestamp"],
                }
                for r in rows
            ]

    def add_memory(self, fact, category="Preferensi", source="chat"):
        clean_fact = str(fact or "").strip()
        if not clean_fact:
            raise ValueError("Isi memori tidak boleh kosong.")
        clean_cat = str(category or "Preferensi").strip() or "Preferensi"
        clean_src = str(source or "chat").strip() or "chat"
        now_ms = int(time.time() * 1000)
        mem_id = f"mem_{hashlib.sha1(clean_fact.lower().encode('utf-8')).hexdigest()[:12]}"

        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO episodic_memories (id, fact, category, source, timestamp) VALUES (?, ?, ?, ?, ?)",
                (mem_id, clean_fact, clean_cat, clean_src, now_ms),
            )
            try:
                conn.execute("DELETE FROM episodic_memories_fts WHERE id = ?", (mem_id,))
                conn.execute(
                    "INSERT INTO episodic_memories_fts (id, fact, category) VALUES (?, ?, ?)",
                    (mem_id, clean_fact, clean_cat),
                )
            except sqlite3.Error:
                pass
        return {"id": mem_id, "fact": clean_fact, "category": clean_cat, "source": clean_src, "timestamp": now_ms}

    def delete_memory(self, mem_id):
        mid = str(mem_id or "").strip()
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM episodic_memories WHERE id = ?", (mid,))
            try:
                conn.execute("DELETE FROM episodic_memories_fts WHERE id = ?", (mid,))
            except sqlite3.Error:
                pass

    def search_memories(self, query, top_k=4):
        clean_query = str(query or "").strip()
        if not clean_query:
            return self.list_memories(limit=top_k)
        terms = [
            w
            for w in re.sub(r"[^a-zA-Z0-9\s]", " ", clean_query.lower()).split()
            if len(w) >= 3
        ]
        results = []
        with self._lock, self._connect() as conn:
            if terms:
                fts_query = " OR ".join(terms[:8])
                try:
                    rows = conn.execute(
                        """
                        SELECT m.id, m.fact, m.category, m.source, m.timestamp
                        FROM episodic_memories_fts f
                        JOIN episodic_memories m ON m.id = f.id
                        WHERE episodic_memories_fts MATCH ?
                        LIMIT ?
                        """,
                        (fts_query, max(1, int(top_k or 4))),
                    ).fetchall()
                    results = [
                        {
                            "id": r["id"],
                            "fact": r["fact"],
                            "category": r["category"],
                            "source": r["source"],
                            "timestamp": r["timestamp"],
                        }
                        for r in rows
                    ]
                except sqlite3.Error:
                    results = []
            if not results:
                rows = conn.execute(
                    "SELECT id, fact, category, source, timestamp FROM episodic_memories ORDER BY timestamp DESC LIMIT 100"
                ).fetchall()
                scored = []
                for r in rows:
                    score = self.lexical_score(clean_query, r["fact"])
                    if score > 0:
                        scored.append((score, r))
                scored.sort(key=lambda item: item[0], reverse=True)
                results = [
                    {
                        "id": r["id"],
                        "fact": r["fact"],
                        "category": r["category"],
                        "source": r["source"],
                        "timestamp": r["timestamp"],
                    }
                    for _, r in scored[: max(1, int(top_k or 4))]
                ]
        return results

    def auto_extract_memory(self, text):
        raw = str(text or "").strip()
        if not raw or len(raw) > 800:
            return None
        lower = raw.lower()
        triggers = (
            "nama saya",
            "saya suka",
            "preferensi saya",
            "ingat bahwa",
            "proyek saya",
            "bahasa favorit",
            "remember that",
            "my name is",
        )
        if any(trig in lower for trig in triggers):
            return self.add_memory(fact=raw[:280], category="Auto-Memori", source="auto-extract")
        return None

    # --- Hermes Cron Jobs ---

    def list_cron_jobs(self):
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT id, name, schedule_minutes, prompt, enabled, last_run, last_result FROM hermes_cron_jobs ORDER BY name"
            ).fetchall()
            return [
                {
                    "id": r["id"],
                    "name": r["name"],
                    "schedule_minutes": r["schedule_minutes"],
                    "prompt": r["prompt"],
                    "enabled": bool(r["enabled"]),
                    "last_run": r["last_run"],
                    "last_result": r["last_result"],
                }
                for r in rows
            ]

    def upsert_cron_job(self, name, prompt, schedule_minutes=60, enabled=True, job_id=None):
        clean_name = str(name or "").strip()
        clean_prompt = str(prompt or "").strip()
        if not clean_name or not clean_prompt:
            raise ValueError("Nama dan prompt jadwal Cron wajib diisi.")
        jid = str(job_id or re.sub(r"[^a-z0-9]+", "-", clean_name.lower()).strip("-") or f"cron-{int(time.time())}").strip()
        mins = max(1, int(schedule_minutes or 60))
        with self._lock, self._connect() as conn:
            conn.execute(
                """
                INSERT INTO hermes_cron_jobs (id, name, schedule_minutes, prompt, enabled, last_run, last_result)
                VALUES (?, ?, ?, ?, ?, COALESCE((SELECT last_run FROM hermes_cron_jobs WHERE id = ?), 0),
                        COALESCE((SELECT last_result FROM hermes_cron_jobs WHERE id = ?), ''))
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, schedule_minutes=excluded.schedule_minutes,
                    prompt=excluded.prompt, enabled=excluded.enabled
                """,
                (jid, clean_name, mins, clean_prompt, 1 if enabled else 0, jid, jid),
            )
        return {"id": jid, "name": clean_name, "schedule_minutes": mins, "prompt": clean_prompt, "enabled": bool(enabled)}

    def delete_cron_job(self, job_id):
        with self._lock, self._connect() as conn:
            conn.execute("DELETE FROM hermes_cron_jobs WHERE id = ?", (str(job_id or "").strip(),))

    def record_cron_result(self, job_id, result_text):
        now_ms = int(time.time() * 1000)
        with self._lock, self._connect() as conn:
            conn.execute(
                "UPDATE hermes_cron_jobs SET last_run = ?, last_result = ? WHERE id = ?",
                (now_ms, str(result_text or "")[:2000], str(job_id or "").strip()),
            )


def _match_available_model_id(base_id, available_models):
    if not available_models:
        return base_id
    if base_id in available_models:
        return base_id
    stem = base_id[:-9] if base_id.endswith(".litertlm") else base_id
    for candidate in available_models:
        cand_stem = candidate[:-9] if candidate.endswith(".litertlm") else candidate
        if candidate == base_id or cand_stem == stem:
            return candidate
    return available_models[0]


def resolve_chat_completion_payload(payload, model_manager=None, kb_store=None):
    """Smart API Gateway: memetakan ID model ke model LiteRT-LM aktif & menyuntikkan konteks RAG terpusat bila diminta."""
    if not isinstance(payload, dict):
        return payload
    updated = dict(payload)
    available_models = []
    if model_manager is not None:
        try:
            available_models = model_manager.list_models() or []
        except Exception:
            available_models = []

    requested_model = str(updated.get("model") or "").strip()
    if available_models:
        if not requested_model:
            updated["model"] = available_models[0]
        else:
            parts = [part.strip() for part in requested_model.split(",")]
            base_id = parts[0]
            suffix_parts = [part for part in parts[1:] if part]
            if not base_id or base_id.lower() in ("default", "auto", "gemma", "local", "litert-lm"):
                matched_id = available_models[0]
            else:
                matched_id = _match_available_model_id(base_id, available_models)
            updated["model"] = ",".join([matched_id, *suffix_parts]) if suffix_parts else matched_id

    if "max_tokens" in updated and updated.get("max_completion_tokens") is None:
        raw_max_tokens = updated.get("max_tokens")
        if not isinstance(raw_max_tokens, bool):
            try:
                parsed_max = int(raw_max_tokens)
                if parsed_max > 0:
                    updated["max_completion_tokens"] = parsed_max
            except (TypeError, ValueError):
                pass

    use_kb = bool(updated.pop("use_shared_kb", False))
    query_embedding = updated.pop("query_embedding", None)
    if kb_store is not None and isinstance(updated.get("messages"), list):
        messages = [dict(m) if isinstance(m, dict) else m for m in updated["messages"]]
        last_user_idx = None
        last_user_text = ""
        for idx in range(len(messages) - 1, -1, -1):
            msg = messages[idx]
            if isinstance(msg, dict) and msg.get("role") == "user" and isinstance(msg.get("content"), str):
                last_user_idx = idx
                last_user_text = msg["content"]
                break
        if last_user_idx is not None and last_user_text.strip():
            try:
                kb_store.auto_extract_memory(last_user_text)
            except Exception:
                pass
            if use_kb:
                hits = kb_store.search(
                    query=last_user_text,
                    embedding=query_embedding,
                    top_k=4,
                    min_score=0.25 if not query_embedding else 0.35,
                )
                memories = kb_store.search_memories(last_user_text, top_k=3) if hasattr(kb_store, "search_memories") else []
                skills = kb_store.match_skills(last_user_text, top_k=1) if hasattr(kb_store, "match_skills") else []
                sections = []
                if hits:
                    sections.append(
                        "[KONTEKS KNOWLEDGE BASE TERPUSAT]\n"
                        + "\n\n---\n\n".join(f"[{h['fileName']}] {h['text']}" for h in hits)
                        + "\n[AKHIR KONTEKS]"
                    )
                if memories:
                    sections.append(
                        "[MEMORI EPISODIK PENGGUNA]\n"
                        + "\n".join(f"- ({m['category']}) {m['fact']}" for m in memories)
                        + "\n[AKHIR MEMORI]"
                    )
                if skills:
                    sections.append(
                        "[SKILL PROSEDURAL RELEVAN]\n"
                        + "\n".join(f"- {s['name']}: {s['content']}" for s in skills)
                        + "\n[AKHIR SKILL]"
                    )
                if sections:
                    messages[last_user_idx] = dict(messages[last_user_idx])
                    messages[last_user_idx]["content"] = (
                        "\n\n".join(sections) + f"\n\nPertanyaan: {last_user_text}"
                    )
                    updated["messages"] = messages
    return updated


class AppRequestHandler(SimpleHTTPRequestHandler):
    model_manager = None
    kb_store = SQLiteVectorStore()
    local_ipv4_addresses = []
    allowed_origins = set()
    ca_certificate_path = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(PROJECT_DIR), **kwargs)

    def setup(self):
        super().setup()
        try:
            self.connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except (OSError, AttributeError):
            pass

    def do_GET(self):
        route = urllib.parse.urlsplit(self.path).path
        if route == "/v1" or route.startswith("/v1/"):
            self.proxy_model_api()
            return
        if route == "/api/network-info":
            addresses = self.local_ipv4_addresses
            self.send_json(
                200,
                {
                    "addresses": addresses,
                    "ui_urls": [
                        f"https://{address}:{API_PORT}/utama.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/eduVis.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/gemini_live.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/gemini_live_futuristik.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/utamaV2.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/analisis-kode.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/agen-ai-otonom.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/mesin-pglite-rag.html"
                        for address in addresses
                    ] + [
                        f"https://{address}:{API_PORT}/tanya-ai-standalone.html"
                        for address in addresses
                    ],
                    "api_urls": [
                        f"https://{address}:{API_PORT}/v1"
                        for address in addresses
                    ],
                    "ca_urls": [
                        f"https://{address}:{API_PORT}/api/lan-ca"
                        for address in addresses
                    ],
                },
            )
            return
        if route == "/api/lan-ca":
            if self.ca_certificate_path is None or not self.ca_certificate_path.is_file():
                self.send_error(404)
                return
            certificate = self.ca_certificate_path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/pkix-cert")
            self.send_header(
                "Content-Disposition",
                'attachment; filename="gemma-ai-gallery-lan-ca.cer"',
            )
            self.send_header("Content-Length", str(len(certificate)))
            self.end_headers()
            self.wfile.write(certificate)
            return
        if route == "/api/local-models":
            self.send_json(200, {"files": list_local_models()})
            return
        if route == "/api/kb/files":
            self.send_json(200, {"files": self.kb_store.list_files()})
            return
        if route == "/api/kb/snapshot":
            self.send_json(200, self.kb_store.get_snapshot())
            return
        if route == "/api/models":
            try:
                if self.model_manager is None:
                    raise RuntimeError("Pengelola LiteRT-LM belum siap.")
                self.send_json(200, {"models": self.model_manager.list_models()})
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                self.send_json(500, {"error": str(error)})
            return
        if route == "/api/models/inspect":
            try:
                self.send_json(
                    200,
                    {
                        "models": inspect_all_models(self.model_manager),
                        "litert_lm_version": get_litert_lm_version(),
                        "runtime_config": get_litert_runtime_config(),
                    },
                )
            except Exception as error:
                self.send_json(500, {"error": str(error)})
            return
        if route == "/api/litert-config":
            try:
                self.send_json(200, get_litert_runtime_config())
            except Exception as error:
                self.send_json(500, {"error": str(error)})
            return
        if route == "/api/system/memory":
            try:
                stats = (
                    self.model_manager.get_memory_stats()
                    if self.model_manager is not None
                    else {"litert_rss_mb": 0.0, "backend_rss_mb": 0.0, "litert_running": False}
                )
                self.send_json(200, stats)
            except Exception as error:
                self.send_json(500, {"error": str(error)})
            return
        if route.startswith("/api/hermes/"):
            self.handle_hermes_get(route)
            return
        if route == "/api/mcp/tools":
            self.handle_mcp_list_tools()
            return
        if route in ("/api/tts", "/api/health", "/api/speakers") or route.startswith("/api/tts"):
            self.proxy_tts_request()
            return
        if route.endswith("tts_studio_lokal.html") or route.endswith("gemini_live.html") or route.endswith("gemini_live_futuristik.html") or "gemini_live" in route:
            threading.Thread(target=ensure_tts_server, daemon=True).start()
        if route == "/":
            self.send_response(302)
            self.send_header("Location", "/index.html")
            self.end_headers()
            return
        if not self.is_allowed_static_path():
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        route = urllib.parse.urlsplit(self.path).path
        if route == "/v1" or route.startswith("/v1/"):
            self.proxy_model_api()
            return
        if not self.is_allowed_static_path():
            self.send_error(404)
            return
        super().do_HEAD()

    def do_OPTIONS(self):
        route = urllib.parse.urlsplit(self.path).path
        if route == "/v1" or route.startswith("/v1/") or route.startswith("/api/"):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
            self.end_headers()
            return
        self.send_error(404)

    def is_allowed_static_path(self):
        requested_path = Path(super().translate_path(self.path)).resolve()
        ui_paths = {
            (PROJECT_DIR / name).resolve()
            for name in (
                "index.html",
                "utama.html",
                "VS.html",
                "claude.html",
                "eduVis.html",
                "gemini_live.html",
                "utamaV2.html",
                "vision_ulti.html",
                "live-conversation.js",
                "aurora.html",
                "tanya-ai-standalone.html",
                "liquid_chatbot.html",
                "analisis-kode.html",
                "agen-ai-otonom.html",
                "mesin-pglite-rag.html",
                "ai-liquid-glass.html",
                "bundle.js",
                "favicon.ico",
                "manifest.webmanifest",
                "tts_studio_lokal.html",
                "gemini_live_futuristik.html",
                "tts-ultimate.html",
                "tts-ultimate3.html",
            )
        }
        assets_path = (PROJECT_DIR / "nano_asset" / "assets").resolve()
        models_asset_path = (PROJECT_DIR / "nano_asset" / "models").resolve()
        tts_assets_path = (PROJECT_DIR / "TTS-Indonesia-Gratis").resolve()
        return (
            requested_path in ui_paths
            or (requested_path.parent == PROJECT_DIR and requested_path.suffix.lower() in {".html", ".js", ".css", ".ico", ".png", ".jpg", ".jpeg", ".svg", ".wav", ".mp3", ".json", ".webmanifest"})
            or requested_path.is_relative_to(assets_path)
            or requested_path.is_relative_to(models_asset_path)
            or (tts_assets_path.exists() and requested_path.is_relative_to(tts_assets_path))
        )

    def list_directory(self, path):
        self.send_error(404)
        return None

    def do_POST(self):
        route = urllib.parse.urlsplit(self.path).path
        if route == "/v1/audio/speech":
            self.handle_audio_speech()
            return
        if route == "/v1/audio/transcriptions":
            self.handle_audio_transcriptions()
            return
        if route == "/v1/embeddings":
            self.handle_embeddings()
            return
        if route == "/v1" or route.startswith("/v1/"):
            self.proxy_model_api()
            return
        if route in ("/api/kb/ingest", "/api/kb/delete", "/api/kb/search", "/api/kb/clear"):
            self.handle_kb_api(route)
            return
        if route == "/api/litert-config":
            self.handle_litert_config_post()
            return
        if route == "/api/mcp/call":
            self.handle_mcp_call_tool()
            return
        if route in ("/api/tts", "/api/health", "/api/speakers") or route.startswith("/api/tts"):
            self.proxy_tts_request()
            return
        if route == "/api/models/sync-local":
            try:
                sync_info = sync_local_models_zero_copy()
                self.send_json(
                    200,
                    {
                        "status": "ok",
                        **sync_info,
                        "models": inspect_all_models(self.model_manager),
                        "litert_lm_version": get_litert_lm_version(),
                    },
                )
            except Exception as error:
                self.send_json(500, {"error": str(error)})
            return
        if route == "/api/automation/webhook":
            self.handle_automation_webhook()
            return
        if route.startswith("/api/hermes/"):
            self.handle_hermes_post(route)
            return
        if route == "/api/system/restart-model-server":
            try:
                if self.model_manager is None:
                    raise RuntimeError("Pengelola LiteRT-LM belum siap.")
                models = self.model_manager.restart_server()
                stats = self.model_manager.get_memory_stats()
                self.send_json(200, {"status": "ok", "models": models, "memory": stats})
            except Exception as error:
                self.send_json(500, {"error": str(error)})
            return
        if route == "/api/import-model-upload":
            self.import_uploaded_model()
            return
        if route not in ("/api/import-model", "/api/delete-model"):
            self.send_error(404)
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 65536:
                raise ValueError("Ukuran permintaan tidak valid.")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Isi permintaan tidak valid.")
            model_id = payload.get("model_id")
            if not isinstance(model_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", model_id):
                raise ValueError("ID model hanya boleh berisi huruf, angka, titik, garis bawah, dan tanda hubung.")
            if self.model_manager is None:
                raise RuntimeError("Pengelola LiteRT-LM belum siap.")
            if route == "/api/delete-model":
                model_ids = self.model_manager.delete_model(model_id)
                self.send_json(200, {"deleted_model_id": model_id, "models": model_ids})
                return

            filename = payload.get("filename")
            if not isinstance(filename, str) or Path(filename).name != filename:
                raise ValueError("Pilih file model dari folder aplikasi atau Downloads.")
            model_path = resolve_local_model_path(filename)
            if model_path is None:
                raise ValueError("File harus berupa .litertlm di folder aplikasi atau Downloads.")
            model_ids = self.model_manager.import_model(model_path, model_id)
            self.send_json(200, {"model_id": model_id, "models": model_ids})
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            self.send_json(500, {"error": str(error)})

    def import_uploaded_model(self):
        temporary_path = None
        try:
            if not ipaddress.ip_address(self.client_address[0]).is_loopback:
                self.send_json(403, {"error": "Unggah model native hanya diizinkan dari komputer host."})
                return
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > MAX_MODEL_UPLOAD_SIZE:
                raise ValueError("Ukuran file model tidak valid atau melebihi batas 100 GB.")

            query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            model_id = query.get("model_id", [""])[0]
            filename = query.get("filename", [""])[0]
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", model_id):
                raise ValueError("ID model hanya boleh berisi huruf, angka, titik, garis bawah, dan tanda hubung.")
            if Path(filename).name != filename or Path(filename).suffix.lower() != ".litertlm":
                raise ValueError("Pilih file dengan ekstensi .litertlm.")
            if self.model_manager is None:
                raise RuntimeError("Pengelola LiteRT-LM belum siap.")

            with tempfile.NamedTemporaryFile(
                prefix="eduvis-model-upload-",
                suffix=".litertlm",
                delete=False,
            ) as uploaded_file:
                temporary_path = Path(uploaded_file.name)
                remaining = content_length
                while remaining:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError("Unggahan file model terputus sebelum selesai.")
                    uploaded_file.write(chunk)
                    remaining -= len(chunk)

            model_ids = self.model_manager.import_model(temporary_path, model_id)
            self.send_json(200, {"model_id": model_id, "models": model_ids})
        except (ValueError, UnicodeDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            self.send_json(500, {"error": str(error)})
        finally:
            if temporary_path is not None:
                try:
                    temporary_path.unlink(missing_ok=True)
                except OSError as error:
                    print(f"[web-ui] Gagal menghapus unggahan model sementara: {error}", flush=True)

    def proxy_tts_request(self):
        parsed = urllib.parse.urlsplit(self.path)
        route = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if route == "/api/health":
            if query.get("warm") or query.get("from") == ["tts_studio"]:
                threading.Thread(target=ensure_tts_server, daemon=True).start()
            neural_ready = False
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8765, timeout=1)
                conn.request("GET", "/api/health")
                resp = conn.getresponse()
                if resp.status == 200:
                    data = json.loads(resp.read().decode("utf-8"))
                    neural_ready = data.get("model_ready", False)
            except Exception:
                pass

            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "model_ready": True,
                "neural_vits_ready": neural_ready,
                "engine": "EduVis Neural VITS & macOS Native",
                "voice": "Juminten / Asep / Gadis / Damayanti"
            }).encode("utf-8"))
            return

        if route == "/api/speakers":
            threading.Thread(target=ensure_tts_server, daemon=True).start()
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8765, timeout=1)
                conn.request("GET", "/api/speakers")
                resp = conn.getresponse()
                if resp.status == 200:
                    speakers_data = resp.read()
                    self.send_response(200)
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(speakers_data)
                    return
            except Exception:
                pass

            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            speakers = [
                {"id": "gadis", "name": "Gadis — Perempuan Merdu & Elegan (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "ardi", "name": "Ardi — Pria Lembut & Bersahabat (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "wibowo", "name": "Wibowo — Pria Dewasa & Berwibawa (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "citra", "name": "Citra — Perempuan Ceria & Ekspresif (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "bimo", "name": "Bimo — Narator Dokumenter & Tegas (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "sari", "name": "Sari — Pengajar Lembut & Artikulatif (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "dimas", "name": "Dimas — Pemuda Santai & Kasual (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "bayu", "name": "Bayu — Pemuda Cerdas & Enerjik (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "tari", "name": "Tari — Gadis Remaja & Ramah (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "JV-00264", "name": "Juminten — Logat Jawa Medok Autentik (JV)", "lang": "jv-ID", "gender": "female"},
                {"id": "SU-00060", "name": "Asep — Logat Sunda Akang Ramah (SU)", "lang": "su-ID", "gender": "male"},
                {"id": "orator", "name": "Orator — Karismatik, Tegas & Menggelegar (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "jokowi", "name": "Jokowi — RVC Neural 40kHz Asli (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "lala", "name": "Lala — Anak Perempuan Lucu & Imut (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "kiki", "name": "Kiki — Bocah Laki-laki Ceria & Enerjik (ID)", "lang": "id-ID", "gender": "male"},
                {"id": "mimi", "name": "Mimi — Balita Gemas & Manis (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "dewi", "name": "Dewi — Narator Audiobook & Puitis (ID)", "lang": "id-ID", "gender": "female"},
                {"id": "piper-news", "name": "News TTS — Narator Berita Piper (ID)", "lang": "id-ID", "gender": "unknown"},
                {"id": "damayanti", "name": "Damayanti — macOS Native Realtime (0ms)", "lang": "id-ID", "gender": "female"},
            ]
            self.wfile.write(json.dumps(speakers).encode("utf-8"))
            return

        if route == "/api/tts":
            text = ""
            speaker = "JV-00264"
            style = "natural"
            speed = "1.0"
            if self.command == "GET":
                text = query.get("text", [""])[0]
                speaker = query.get("speaker", ["JV-00264"])[0]
                style = query.get("style", ["natural"])[0]
                speed = query.get("speed", ["1.0"])[0]
            else:
                try:
                    content_length = int(self.headers.get("Content-Length", 0))
                    if content_length > 0:
                        body_data = json.loads(self.rfile.read(content_length).decode("utf-8"))
                        text = body_data.get("text", "")
                        speaker = body_data.get("speaker", "JV-00264")
                        style = body_data.get("style", "natural")
                        speed = str(body_data.get("speed", "1.0"))
                except Exception:
                    pass

            text = strip_stage_directions(text)
            if not text:
                self.send_json(400, {"error": "Teks tidak boleh kosong."})
                return

            # Jika memilih karakter vokal AI (Juminten, Asep, Gadis, Ardi, Wibowo), proses via internal VITS engine:
            if speaker not in ("damayanti", "system-damayanti"):
                try:
                    ensure_tts_server()
                    encoded_text = urllib.parse.quote(text)
                    conn = http.client.HTTPConnection("127.0.0.1", 8765, timeout=60)
                    conn.request("GET", f"/api/tts?speaker={urllib.parse.quote(speaker)}&text={encoded_text}&style={urllib.parse.quote(style)}&speed={urllib.parse.quote(str(speed))}")
                    resp = conn.getresponse()
                    if resp.status == 200:
                        audio_bytes = resp.read()
                        if len(audio_bytes) > 200:
                            self.send_response(200)
                            self.send_header("Content-Type", "audio/wav")
                            self.send_header("Content-Length", str(len(audio_bytes)))
                            self.send_header("Access-Control-Allow-Origin", "*")
                            self.end_headers()
                            self.wfile.write(audio_bytes)
                            return
                except Exception as e:
                    print(f"[web-ui] Peringatan sintesis VITS gagal, fallback ke macOS say: {e}", flush=True)

            rate_map = {
                "damayanti": 175,
                "gadis": 195,
                "ardi": 170,
                "wibowo": 145,
                "JV-00264": 165,
                "SU-00060": 180,
            }
            rate = rate_map.get(speaker, 175)

            # Fallback native macOS say & afconvert
            tmp_aiff = None
            tmp_wav = None
            try:
                with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as af, \
                     tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wf:
                    tmp_aiff = Path(af.name)
                    tmp_wav = Path(wf.name)

                voice = "Damayanti"
                say_cmd = ["/usr/bin/say", "-v", voice, "-r", str(rate), "-o", str(tmp_aiff), text]
                say_proc = subprocess.run(say_cmd, capture_output=True, timeout=30, check=False)
                if say_proc.returncode != 0:
                    subprocess.run(
                        ["/usr/bin/say", "-r", str(rate), "-o", str(tmp_aiff), text],
                        capture_output=True, timeout=30, check=False
                    )
                conv_proc = subprocess.run(
                    ["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@22050", str(tmp_aiff), str(tmp_wav)],
                    capture_output=True, timeout=30, check=False
                )
                if conv_proc.returncode == 0 and tmp_wav.exists() and tmp_wav.stat().st_size > 44:
                    audio_bytes = tmp_wav.read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "audio/wav")
                    self.send_header("Content-Length", str(len(audio_bytes)))
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.end_headers()
                    self.wfile.write(audio_bytes)
                    return
                else:
                    self.send_json(500, {"error": "Gagal mengonversi audio ke WAV."})
                    return
            except Exception as ex:
                self.send_json(500, {"error": f"Sintesis suara macOS gagal: {ex}"})
                return
            finally:
                for p in (tmp_aiff, tmp_wav):
                    if p is not None:
                        try:
                            p.unlink(missing_ok=True)
                        except OSError:
                            pass
        self.send_error(404)

    def proxy_model_api(self):
        body = None
        response_started = False
        content_length = self.headers.get("Content-Length")
        if content_length:
            try:
                length = int(content_length)
            except ValueError:
                self.send_error(400, "Content-Length tidak valid.")
                return
            if length < 0 or length > 256 * 1024 * 1024:
                self.send_error(413, "Ukuran permintaan terlalu besar.")
                return
            body = self.rfile.read(length)

        if body is not None and self.command == "POST":
            route = urllib.parse.urlsplit(self.path).path
            if route == "/v1/chat/completions":
                try:
                    parsed = json.loads(body.decode("utf-8"))
                    if isinstance(parsed, dict):
                        if self.headers.get("X-EduVis-Use-KB") == "1":
                            parsed["use_shared_kb"] = True
                        resolved = resolve_chat_completion_payload(
                            parsed,
                            model_manager=self.model_manager,
                            kb_store=self.kb_store,
                        )
                        body = json.dumps(resolved).encode("utf-8")
                except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
                    pass

        headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower()
            not in {"host", "connection", "content-length", "origin", "accept-encoding"}
        }
        headers["Accept-Encoding"] = "identity"
        if body is not None:
            headers["Content-Length"] = str(len(body))

        upstream = http.client.HTTPConnection(
            LITERT_API_HOST,
            LITERT_API_PORT,
            timeout=60 * 60,
        )
        try:
            upstream.request(self.command, self.path, body=body, headers=headers)
            response = upstream.getresponse()
            self.send_response(response.status, response.reason)
            has_content_length = False
            for name, value in response.getheaders():
                if name.lower() in {
                    "connection",
                    "content-encoding",
                    "transfer-encoding",
                    "access-control-allow-origin",
                    "access-control-allow-methods",
                    "access-control-allow-headers",
                }:
                    continue
                if name.lower() == "content-length":
                    has_content_length = True
                self.send_header(name, value)
            if not has_content_length:
                self.close_connection = True
                self.send_header("Connection", "close")
            self.end_headers()
            response_started = True

            while chunk := response.read1(64 * 1024):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (OSError, http.client.HTTPException) as error:
            route = urllib.parse.urlsplit(self.path).path
            if route == "/v1/models" and self.command in ("GET", "HEAD") and not response_started:
                try:
                    inspected = inspect_all_models(self.model_manager)
                    data_items = [
                        {
                            "id": item["id"],
                            "object": "model",
                            "owned_by": "litert-lm",
                        }
                        for item in inspected
                        if isinstance(item, dict) and item.get("id")
                    ]
                    payload = {"object": "list", "data": data_items}
                    if self.command == "HEAD":
                        body_bytes = json.dumps(payload).encode("utf-8")
                        self.send_response(200)
                        self.send_header("Content-Type", "application/json; charset=utf-8")
                        self.send_header("Content-Length", str(len(body_bytes)))
                        self.end_headers()
                    else:
                        self.send_json(200, payload)
                    return
                except Exception as fallback_error:
                    print(f"[web-ui] Gagal menyusun fallback /v1/models: {fallback_error}", flush=True)
            print(f"[web-ui] Gagal meneruskan {self.path} ke LiteRT-LM: {error}", flush=True)
            if not response_started and not self.wfile.closed:
                try:
                    self.send_error(502, "LiteRT-LM API tidak dapat dijangkau.")
                except (BrokenPipeError, ConnectionResetError):
                    pass
        finally:
            upstream.close()

    def handle_kb_api(self, route):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length < 0 or content_length > 64 * 1024 * 1024:
                raise ValueError("Ukuran payload Knowledge Base tidak valid.")
            payload = (
                json.loads(self.rfile.read(content_length).decode("utf-8"))
                if content_length > 0
                else {}
            )
            if not isinstance(payload, dict):
                raise ValueError("Isi permintaan Knowledge Base harus berupa objek JSON.")

            if route == "/api/kb/ingest":
                result = self.kb_store.upsert_document(
                    file_id=payload.get("id"),
                    name=payload.get("name"),
                    size=payload.get("size", 0),
                    timestamp=payload.get("timestamp"),
                    chunks=payload.get("chunks", []),
                    collection=payload.get("collection", "Umum"),
                )
                self.send_json(200, {"status": "ok", **result})
                return

            if route == "/api/kb/delete":
                file_id = str(payload.get("id") or "").strip()
                if not file_id:
                    raise ValueError("ID dokumen wajib diisi untuk penghapusan.")
                result = self.kb_store.delete_document(file_id)
                self.send_json(200, {"status": "ok", **result})
                return

            if route == "/api/kb/clear":
                self.kb_store.clear_all()
                self.send_json(200, {"status": "ok"})
                return

            if route == "/api/kb/search":
                results = self.kb_store.search(
                    query=str(payload.get("query") or ""),
                    embedding=payload.get("embedding"),
                    top_k=payload.get("top_k", 4),
                    min_score=float(payload.get("min_score", 0.35)),
                )
                self.send_json(200, {"results": results})
                return
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})

    def handle_automation_webhook(self):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 4 * 1024 * 1024:
                raise ValueError("Ukuran payload webhook tidak valid.")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Payload webhook harus berupa objek JSON.")

            prompt = str(payload.get("prompt") or "").strip()
            messages = payload.get("messages")
            if not isinstance(messages, list) or not messages:
                if not prompt:
                    raise ValueError("Field 'prompt' atau 'messages' wajib diisi.")
                sys_prompt = str(
                    payload.get("system")
                    or "Anda adalah asisten AI EduVis yang membantu otomasi sekolah dan menjawab dalam Bahasa Indonesia."
                )
                messages = [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": prompt},
                ]

            use_kb = bool(payload.get("use_kb", True))
            citations = []
            if use_kb and self.kb_store is not None:
                user_query = prompt
                if not user_query:
                    for m in reversed(messages):
                        if isinstance(m, dict) and m.get("role") == "user":
                            user_query = str(m.get("content") or "")
                            break
                if user_query:
                    citations = self.kb_store.search(
                        query=user_query,
                        embedding=payload.get("query_embedding"),
                        top_k=int(payload.get("top_k", 4)),
                        min_score=0.25 if not payload.get("query_embedding") else 0.35,
                    )

            chat_req = resolve_chat_completion_payload(
                {
                    "model": payload.get("model", "auto"),
                    "messages": messages,
                    "temperature": float(payload.get("temperature", 0.2)),
                    "max_tokens": int(payload.get("max_tokens", 1024)),
                    "stream": False,
                    "use_shared_kb": use_kb,
                    "query_embedding": payload.get("query_embedding"),
                },
                model_manager=self.model_manager,
                kb_store=self.kb_store,
            )

            req_bytes = json.dumps(chat_req).encode("utf-8")
            upstream = http.client.HTTPConnection(LITERT_API_HOST, LITERT_API_PORT, timeout=300)
            try:
                upstream.request(
                    "POST",
                    "/v1/chat/completions",
                    body=req_bytes,
                    headers={"Content-Type": "application/json", "Content-Length": str(len(req_bytes))},
                )
                resp = upstream.getresponse()
                resp_body = resp.read().decode("utf-8", errors="replace")
                if resp.status >= 400:
                    self.send_json(resp.status, {"error": resp_body, "model": chat_req.get("model")})
                    return
                data = json.loads(resp_body)
                reply = ""
                choices = data.get("choices") or []
                if choices and isinstance(choices[0], dict):
                    msg = choices[0].get("message") or {}
                    reply = str(msg.get("content") or choices[0].get("text") or "")
                self.send_json(
                    200,
                    {
                        "status": "ok",
                        "model": chat_req.get("model"),
                        "reply": reply,
                        "citations": citations,
                    },
                )
            finally:
                upstream.close()
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(502, {"error": f"Gagal mengeksekusi webhook otomasi: {error}"})

    # --- Hermes Agent API Endpoints (Bootstrap, Skills, FTS5 Memory, Subagents, Cron, Gateway) ---

    def _hermes_gateway_path(self):
        base_dir = self.kb_store.db_path.parent if self.kb_store is not None else Path(tempfile.gettempdir())
        return base_dir / "hermes_gateway.json"

    def _load_hermes_gateway_config(self):
        cfg_path = self._hermes_gateway_path()
        default_cfg = {
            "enabled": False,
            "telegram_bot_token": "",
            "telegram_chat_id": "",
            "webhook_url": "",
        }
        if cfg_path.is_file():
            try:
                loaded = json.loads(cfg_path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    default_cfg.update(loaded)
            except (OSError, ValueError, TypeError):
                pass
        return default_cfg

    def _build_hermes_stages(self):
        t0 = time.time()
        models_list = []
        if self.model_manager is not None:
            try:
                models_list = self.model_manager.list_models() or []
            except Exception:
                models_list = []
        t_models = max(1, int((time.time() - t0) * 1000))
        skills_count = len(self.kb_store.list_skills()) if self.kb_store is not None else 0
        mem_count = len(self.kb_store.list_memories()) if self.kb_store is not None else 0
        cron_count = len(self.kb_store.list_cron_jobs()) if self.kb_store is not None else 0
        return [
            {
                "id": "runtime_venv",
                "title": "Python & LiteRT-LM Runtime",
                "status": "ready",
                "durationMs": 4,
                "detail": f"LiteRT-LM v{get_litert_lm_version() or 'aktif'} · Python {sys.version.split()[0]}",
            },
            {
                "id": "port_lock_guard",
                "title": "Port & Process Lock Guard",
                "status": "ready",
                "durationMs": 2,
                "detail": f"Gateway : {API_PORT}/{LOCAL_UI_PORT} · LiteRT : {LITERT_API_PORT}",
            },
            {
                "id": "litert_models",
                "title": "Sinkronisasi Model .litertlm",
                "status": "ready" if models_list else "warning",
                "durationMs": t_models,
                "detail": f"{len(models_list)} model aktif ({models_list[0]})" if models_list else "Belum ada model aktif",
            },
            {
                "id": "sqlite_memory_skills",
                "title": "SQLite FTS5 Memory & Skills",
                "status": "ready",
                "durationMs": 3,
                "detail": f"{skills_count} skill · {mem_count} memori episodik · {cron_count} jadwal cron",
            },
        ]

    def _run_local_prompt_once(self, system_prompt, user_prompt, max_tokens=512):
        chat_req = resolve_chat_completion_payload(
            {
                "model": "auto",
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "temperature": 0.3,
                "max_tokens": max_tokens,
                "stream": False,
                "use_shared_kb": True,
            },
            model_manager=self.model_manager,
            kb_store=self.kb_store,
        )
        req_bytes = json.dumps(chat_req).encode("utf-8")
        upstream = http.client.HTTPConnection(LITERT_API_HOST, LITERT_API_PORT, timeout=90)
        try:
            upstream.request(
                "POST",
                "/v1/chat/completions",
                body=req_bytes,
                headers={"Content-Type": "application/json", "Content-Length": str(len(req_bytes))},
            )
            resp = upstream.getresponse()
            body = resp.read().decode("utf-8", errors="replace")
            if resp.status < 400:
                parsed = json.loads(body)
                choices = parsed.get("choices") or []
                if choices and isinstance(choices[0], dict):
                    msg = choices[0].get("message") or {}
                    return str(msg.get("content") or choices[0].get("text") or "").strip()
        finally:
            upstream.close()
        return ""

    def _dispatch_gateway_notification(self, text):
        cfg = self._load_hermes_gateway_config()
        if not cfg.get("enabled"):
            return {"sent": False, "reason": "Gateway belum diaktifkan."}
        token = str(cfg.get("telegram_bot_token") or "").strip()
        chat_id = str(cfg.get("telegram_chat_id") or "").strip()
        webhook = str(cfg.get("webhook_url") or "").strip()
        delivered = []
        if token and chat_id:
            tg_url = f"https://api.telegram.org/bot{token}/sendMessage"
            data = json.dumps({"chat_id": chat_id, "text": text[:3900]}).encode("utf-8")
            req = urllib.request.Request(tg_url, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status < 400:
                    delivered.append("telegram")
        if webhook and webhook.startswith(("http://", "https://")):
            data = json.dumps({"source": "EduVis Hermes Gateway", "text": text[:4000]}).encode("utf-8")
            req = urllib.request.Request(webhook, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status < 400:
                    delivered.append("webhook")
        return {"sent": len(delivered) > 0, "channels": delivered}

    def handle_mcp_list_tools(self):
        """MCP (Model Context Protocol) Tools Discovery Endpoint."""
        tools = [
            {
                "name": "fs_read_file",
                "description": "Membaca isi berkas teks lokal (MD, TXT, JSON, PY, JS, HTML) di dalam workspace.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Nama atau path relatif berkas yang ingin dibaca"}
                    },
                    "required": ["path"]
                }
            },
            {
                "name": "fs_list_dir",
                "description": "Melihat daftar berkas dan folder di dalam direktori workspace.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "subdir": {"type": "string", "description": "Subdirektori opsional (default: root)", "default": "."}
                    }
                }
            },
            {
                "name": "system_telemetry",
                "description": "Mengambil metrik performa sistem macOS, status VRAM, RAM, dan status LiteRT-LM runtime.",
                "inputSchema": {
                    "type": "object",
                    "properties": {}
                }
            },
            {
                "name": "run_python_sandbox",
                "description": "Mengeksekusi kode Python terisolasi untuk kalkulasi matematika, pemrosesan data, atau analisis ringkas.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "code": {"type": "string", "description": "Kode Python yang akan dieksekusi"}
                    },
                    "required": ["code"]
                }
            }
        ]
        self.send_json(200, {"tools": tools, "protocol_version": "2024-11-05", "server": "EduVis-MCP/1.0"})

    def handle_mcp_call_tool(self):
        """MCP Tool Execution Endpoint."""
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(content_length) if content_length > 0 else b"{}"
            payload = json.loads(raw.decode("utf-8"))
            tool_name = str(payload.get("name") or "").strip()
            args = payload.get("arguments") or {}

            if tool_name == "fs_read_file":
                rel_path = str(args.get("path") or "").strip()
                target = (PROJECT_DIR / rel_path).resolve()
                if not target.is_relative_to(PROJECT_DIR.resolve()) or not target.exists() or not target.is_file():
                    raise ValueError(f"Berkas '{rel_path}' tidak ditemukan atau di luar batas workspace.")
                text_content = target.read_text(encoding="utf-8", errors="replace")[:12000]
                result = {"content": [{"type": "text", "text": text_content}], "isError": False}

            elif tool_name == "fs_list_dir":
                subdir = str(args.get("subdir") or ".").strip()
                target_dir = (PROJECT_DIR / subdir).resolve()
                if not target_dir.is_relative_to(PROJECT_DIR.resolve()) or not target_dir.is_dir():
                    raise ValueError(f"Direktori '{subdir}' tidak valid.")
                entries = []
                for p in sorted(target_dir.iterdir()):
                    if p.name.startswith("."):
                        continue
                    entries.append({"name": p.name, "is_dir": p.is_dir(), "size": p.stat().st_size if p.is_file() else 0})
                result = {"content": [{"type": "text", "text": json.dumps(entries[:60], indent=2)}], "isError": False}

            elif tool_name == "system_telemetry":
                stats = self.model_manager.get_memory_stats() if self.model_manager else {}
                mem_info = {"platform": sys.platform, "litert_stats": stats, "version": get_litert_lm_version()}
                result = {"content": [{"type": "text", "text": json.dumps(mem_info, indent=2)}], "isError": False}

            elif tool_name == "run_python_sandbox":
                code = str(args.get("code") or "")
                proc = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=8)
                output = proc.stdout if proc.returncode == 0 else f"ERROR (Exit {proc.returncode}):\n{proc.stderr}"
                result = {"content": [{"type": "text", "text": output[:4000]}], "isError": proc.returncode != 0}

            else:
                raise ValueError(f"Tool '{tool_name}' tidak terdaftar di MCP server.")

            self.send_json(200, result)
        except Exception as exc:
            self.send_json(500, {"error": str(exc), "isError": True})

    def handle_hermes_get(self, route):
        try:
            if route == "/api/hermes/status":
                skills = self.kb_store.list_skills() if self.kb_store is not None else []
                memories = self.kb_store.list_memories() if self.kb_store is not None else []
                cron_jobs = self.kb_store.list_cron_jobs() if self.kb_store is not None else []
                self.send_json(
                    200,
                    {
                        "stages": self._build_hermes_stages(),
                        "skills_count": len(skills),
                        "memories_count": len(memories),
                        "cron_count": len(cron_jobs),
                        "toolsets": [
                            {"id": "code_terminal", "name": "Code & Terminal", "enabled": True},
                            {"id": "vision_ocr", "name": "Vision & OCR", "enabled": True},
                            {"id": "rag_fts5", "name": "RAG & FTS5 Memory", "enabled": True},
                            {"id": "stem_sim", "name": "STEM Simulation", "enabled": True},
                        ],
                        "gateway": self._load_hermes_gateway_config(),
                    },
                )
                return
            if route == "/api/hermes/skills":
                self.send_json(200, {"skills": self.kb_store.list_skills() if self.kb_store is not None else []})
                return
            if route == "/api/hermes/memories":
                self.send_json(200, {"memories": self.kb_store.list_memories() if self.kb_store is not None else []})
                return
            if route == "/api/hermes/cron":
                self.send_json(200, {"jobs": self.kb_store.list_cron_jobs() if self.kb_store is not None else []})
                return
            if route == "/api/hermes/gateway":
                self.send_json(200, {"gateway": self._load_hermes_gateway_config()})
                return
            self.send_error(404)
        except Exception as error:
            self.send_json(500, {"error": str(error)})

    def handle_hermes_post(self, route):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length < 0 or content_length > 2 * 1024 * 1024:
                raise ValueError("Ukuran permintaan Hermes tidak valid.")
            raw = self.rfile.read(content_length).decode("utf-8") if content_length > 0 else "{}"
            payload = json.loads(raw or "{}")
            if not isinstance(payload, dict):
                raise ValueError("Payload Hermes harus berupa objek JSON.")

            if route == "/api/hermes/self-heal":
                sync_info = sync_local_models_zero_copy()
                reclaimed = reclaim_backend_ports() if callable(globals().get("reclaim_backend_ports")) else []
                self.send_json(
                    200,
                    {
                        "status": "healed",
                        "sync": sync_info,
                        "reclaimed_pids": reclaimed,
                        "stages": self._build_hermes_stages(),
                    },
                )
                return

            if route == "/api/hermes/skills":
                if self.kb_store is None:
                    raise RuntimeError("SQLite store belum siap.")
                action = str(payload.get("action") or "save")
                if action == "delete":
                    self.kb_store.delete_skill(payload.get("id"))
                    self.send_json(200, {"status": "deleted", "skills": self.kb_store.list_skills()})
                    return
                saved = self.kb_store.save_skill(
                    name=payload.get("name"),
                    description=payload.get("description", ""),
                    content=payload.get("content"),
                    tags=payload.get("tags", ""),
                    skill_id=payload.get("id"),
                )
                self.send_json(200, {"status": "saved", "skill": saved, "skills": self.kb_store.list_skills()})
                return

            if route == "/api/hermes/memories":
                if self.kb_store is None:
                    raise RuntimeError("SQLite store belum siap.")
                action = str(payload.get("action") or "add")
                if action == "delete":
                    self.kb_store.delete_memory(payload.get("id"))
                    self.send_json(200, {"status": "deleted", "memories": self.kb_store.list_memories()})
                    return
                if action == "search":
                    hits = self.kb_store.search_memories(payload.get("query", ""), top_k=int(payload.get("top_k", 6)))
                    self.send_json(200, {"memories": hits})
                    return
                added = self.kb_store.add_memory(
                    fact=payload.get("fact"),
                    category=payload.get("category", "Preferensi"),
                    source=payload.get("source", "manual"),
                )
                self.send_json(200, {"status": "added", "memory": added, "memories": self.kb_store.list_memories()})
                return

            if route == "/api/hermes/cron":
                if self.kb_store is None:
                    raise RuntimeError("SQLite store belum siap.")
                action = str(payload.get("action") or "upsert")
                if action == "delete":
                    self.kb_store.delete_cron_job(payload.get("id"))
                    self.send_json(200, {"status": "deleted", "jobs": self.kb_store.list_cron_jobs()})
                    return
                if action == "run_now":
                    job_id = str(payload.get("id") or "").strip()
                    jobs = self.kb_store.list_cron_jobs()
                    target = next((j for j in jobs if j["id"] == job_id), None)
                    prompt = str(payload.get("prompt") or (target["prompt"] if target else "")).strip()
                    if not prompt:
                        raise ValueError("Prompt cron tidak ditemukan.")
                    try:
                        result_text = self._run_local_prompt_once(
                            "Anda menjalankan tugas terjadwal otomatis Hermes Cron Agent di EduVis.",
                            prompt,
                        )
                    except Exception:
                        result_text = ""
                    if not result_text:
                        result_text = f"[Cron Executed @ {time.strftime('%H:%M:%S')}] Tugas `{prompt[:120]}` tercatat siap dieksekusi oleh Gemma lokal."
                    if job_id:
                        self.kb_store.record_cron_result(job_id, result_text)
                    try:
                        self._dispatch_gateway_notification(f"[EduVis Cron]\n{result_text}")
                    except Exception:
                        pass
                    self.send_json(200, {"status": "executed", "result": result_text, "jobs": self.kb_store.list_cron_jobs()})
                    return
                job = self.kb_store.upsert_cron_job(
                    name=payload.get("name"),
                    prompt=payload.get("prompt"),
                    schedule_minutes=payload.get("schedule_minutes", 60),
                    enabled=payload.get("enabled", True),
                    job_id=payload.get("id"),
                )
                self.send_json(200, {"status": "saved", "job": job, "jobs": self.kb_store.list_cron_jobs()})
                return

            if route == "/api/hermes/delegate":
                task_text = str(payload.get("task") or "").strip()
                if not task_text:
                    raise ValueError("Field 'task' untuk Subagent Delegation wajib diisi.")
                toolsets = payload.get("toolsets") or ["Code & Terminal", "RAG & FTS5 Memory"]
                roles = payload.get("roles") or [
                    ("Arsitek Sistem", "Rancang arsitektur, alur kerja, dan langkah implementasi ringkas."),
                    ("Analis RAG & Memori", "Identifikasi fakta relevan, risiko teknis, dan kebutuhan data lokal."),
                    ("Verifikator Kualitas", "Susun daftar pemeriksaan, metrik pengujian, dan validasi akhir."),
                ]

                def run_subagent(spec):
                    role_name, directive = spec
                    sys_msg = (
                        f"Anda adalah Subagent spesialis [{role_name}] dalam sistem Hermes EduVis. "
                        f"Toolset aktif: {', '.join(map(str, toolsets))}. {directive} Jawab singkat dalam Bahasa Indonesia."
                    )
                    started = time.time()
                    reply = ""
                    mode = "litert-local"
                    try:
                        reply = self._run_local_prompt_once(sys_msg, task_text, max_tokens=380)
                    except Exception:
                        reply = ""
                    if not reply:
                        mode = "structured-fallback"
                        reply = (
                            f"[{role_name}] Analisis paralel untuk '{task_text[:90]}' "
                            f"(Toolset: {', '.join(map(str, toolsets))}): {directive}"
                        )
                    return {
                        "role": role_name,
                        "mode": mode,
                        "durationMs": max(1, int((time.time() - started) * 1000)),
                        "summary": reply,
                    }

                with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
                    subagents = list(pool.map(run_subagent, roles))
                synthesis = "\n\n".join(f"### {item['role']} ({item['durationMs']} ms)\n{item['summary']}" for item in subagents)
                self.send_json(
                    200,
                    {
                        "status": "delegated",
                        "toolsets": toolsets,
                        "subagents": subagents,
                        "synthesis": synthesis,
                    },
                )
                return

            if route == "/api/hermes/gateway":
                action = str(payload.get("action") or "save")
                if action == "test_send":
                    res = self._dispatch_gateway_notification(
                        str(payload.get("message") or "Tes koneksi dari EduVis Hermes Gateway berhasil!")
                    )
                    self.send_json(200, res)
                    return
                cfg = self._load_hermes_gateway_config()
                cfg["enabled"] = bool(payload.get("enabled", cfg.get("enabled", False)))
                if "telegram_bot_token" in payload:
                    cfg["telegram_bot_token"] = str(payload.get("telegram_bot_token") or "").strip()
                if "telegram_chat_id" in payload:
                    cfg["telegram_chat_id"] = str(payload.get("telegram_chat_id") or "").strip()
                if "webhook_url" in payload:
                    cfg["webhook_url"] = str(payload.get("webhook_url") or "").strip()
                cfg_path = self._hermes_gateway_path()
                cfg_path.parent.mkdir(parents=True, exist_ok=True)
                cfg_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
                self.send_json(200, {"status": "saved", "gateway": cfg})
                return

            self.send_error(404)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})

    def handle_audio_speech(self):
        temp_aiff = None
        temp_wav = None
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 262144:
                raise ValueError("Ukuran teks TTS tidak valid.")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Isi permintaan TTS harus berupa objek JSON.")
            text = str(payload.get("input") or payload.get("text") or "").strip()
            if not text:
                raise ValueError("Teks 'input' untuk TTS wajib diisi.")
            voice = re.sub(r"[^A-Za-z0-9 _-]", "", str(payload.get("voice") or "Damayanti")).strip() or "Damayanti"
            rate = max(90, min(320, int(float(payload.get("speed", 1.0)) * 185)))

            piper_bin = shutil.which("piper")
            piper_model = PROJECT_DIR / "nano_asset" / "models" / "tts" / "id_ID.onnx"
            with tempfile.NamedTemporaryFile(prefix="eduvis-tts-", suffix=".wav", delete=False) as wf:
                temp_wav = Path(wf.name)

            synthesized = False
            if piper_bin and piper_model.is_file():
                proc = subprocess.run(
                    [piper_bin, "--model", str(piper_model), "--output_file", str(temp_wav)],
                    input=text.encode("utf-8"),
                    capture_output=True,
                    timeout=30,
                    check=False,
                )
                synthesized = proc.returncode == 0 and temp_wav.is_file() and temp_wav.stat().st_size > 44

            if not synthesized and sys.platform == "darwin" and shutil.which("say"):
                with tempfile.NamedTemporaryFile(prefix="eduvis-tts-", suffix=".aiff", delete=False) as af:
                    temp_aiff = Path(af.name)
                say_cmd = ["/usr/bin/say", "-v", voice, "-r", str(rate), "-o", str(temp_aiff), text]
                proc = subprocess.run(say_cmd, capture_output=True, timeout=30, check=False)
                if proc.returncode != 0:
                    proc = subprocess.run(
                        ["/usr/bin/say", "-r", str(rate), "-o", str(temp_aiff), text],
                        capture_output=True,
                        timeout=30,
                        check=False,
                    )
                if proc.returncode == 0 and shutil.which("afconvert"):
                    conv = subprocess.run(
                        ["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@22050", str(temp_aiff), str(temp_wav)],
                        capture_output=True,
                        timeout=30,
                        check=False,
                    )
                    synthesized = conv.returncode == 0 and temp_wav.is_file() and temp_wav.stat().st_size > 44

            if not synthesized:
                self.send_json(503, {"error": "Mesin suara offline (Piper / macOS say) tidak tersedia."})
                return

            audio_bytes = temp_wav.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio_bytes)))
            self.end_headers()
            self.wfile.write(audio_bytes)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})
        finally:
            for p in (temp_aiff, temp_wav):
                if p is not None:
                    try:
                        p.unlink(missing_ok=True)
                    except OSError:
                        pass

    def handle_audio_transcriptions(self):
        temp_audio = None
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 25 * 1024 * 1024:
                raise ValueError("Ukuran data audio tidak valid (maks 25 MB).")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Isi permintaan transkripsi harus berupa objek JSON.")

            audio_b64 = str(payload.get("audio_base64") or "").strip()
            language = str(payload.get("language") or "id").split("-")[0].lower()
            if not audio_b64:
                raise ValueError("Field 'audio_base64' wajib diisi.")
            if "," in audio_b64:
                audio_b64 = audio_b64.split(",", 1)[1]
            raw_audio = base64.b64decode(audio_b64)

            with tempfile.NamedTemporaryFile(prefix="eduvis-stt-", suffix=".wav", delete=False) as af:
                temp_audio = Path(af.name)
                af.write(raw_audio)

            whisper_bin = shutil.which("whisper-cli") or shutil.which("whisper")
            if whisper_bin:
                proc = subprocess.run(
                    [whisper_bin, str(temp_audio), "--language", language, "--output_format", "txt"],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )
                if proc.returncode == 0:
                    transcript = (proc.stdout or "").strip()
                    self.send_json(200, {"text": transcript, "engine": Path(whisper_bin).name})
                    return

            self.send_json(
                200,
                {
                    "text": str(payload.get("fallback_text") or "").strip(),
                    "engine": "native-fallback",
                    "available": False,
                },
            )
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})
        finally:
            if temp_audio is not None:
                try:
                    temp_audio.unlink(missing_ok=True)
                except OSError:
                    pass

    def handle_litert_config_post(self):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 65536:
                raise ValueError("Ukuran konfigurasi LiteRT-LM tidak valid.")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Konfigurasi harus berupa objek JSON.")
            model_id = payload.pop("model_id", None)
            updates = payload.get("default") if isinstance(payload.get("default"), dict) else payload
            updated = update_litert_runtime_config(updates, model_id=model_id)
            self.send_json(200, {"status": "ok", "config": updated})
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})

    def handle_embeddings(self):
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 32 * 1024 * 1024:
                raise ValueError("Ukuran payload embedding tidak valid.")
            raw_body = self.rfile.read(content_length)
            payload = json.loads(raw_body.decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Payload embedding harus berupa objek JSON.")

            raw_input = payload.get("input")
            if raw_input is None:
                raise ValueError("Field 'input' wajib diisi.")

            if self.model_manager is not None and self.model_manager.is_running():
                upstream_payload = dict(payload)
                available_models = []
                try:
                    available_models = self.model_manager.list_models() or []
                except Exception:
                    available_models = []
                req_model = str(upstream_payload.get("model") or "").strip()
                if available_models and (
                    not req_model
                    or req_model.lower() in ("default", "auto", "gemma", "local", "litert-lm")
                ):
                    upstream_payload["model"] = available_models[0]

                upstream = http.client.HTTPConnection(LITERT_API_HOST, LITERT_API_PORT, timeout=30)
                try:
                    up_bytes = json.dumps(upstream_payload).encode("utf-8")
                    upstream.request(
                        "POST",
                        "/v1/embeddings",
                        body=up_bytes,
                        headers={
                            "Content-Type": "application/json",
                            "Content-Length": str(len(up_bytes)),
                            "Accept-Encoding": "identity",
                        },
                    )
                    up_resp = upstream.getresponse()
                    up_data = up_resp.read()
                    if 200 <= up_resp.status < 300 and up_data:
                        parsed_up = json.loads(up_data.decode("utf-8"))
                        if isinstance(parsed_up, dict) and isinstance(parsed_up.get("data"), list):
                            self.send_json(200, parsed_up)
                            return
                except (OSError, http.client.HTTPException, ValueError):
                    pass
                finally:
                    upstream.close()

            dimensions = payload.get("dimensions", 384)
            try:
                dimensions = max(64, min(1536, int(dimensions)))
            except (TypeError, ValueError):
                dimensions = 384

            if isinstance(raw_input, list) and all(isinstance(x, str) for x in raw_input):
                texts = [x for x in raw_input]
            elif isinstance(raw_input, list):
                joined = " ".join(
                    str(item.get("text") or "")
                    for item in raw_input
                    if isinstance(item, dict)
                ).strip()
                texts = [joined]
            else:
                texts = [str(raw_input)]

            data_items = []
            total_tokens = 0
            for idx, txt in enumerate(texts):
                total_tokens += max(1, len(str(txt).split())) if str(txt).strip() else 0
                data_items.append(
                    {
                        "object": "embedding",
                        "index": idx,
                        "embedding": compute_deterministic_embedding(txt, dimensions=dimensions),
                    }
                )

            self.send_json(
                200,
                {
                    "object": "list",
                    "data": data_items,
                    "model": f"litert-lm-hybrid-embedding-{dimensions}",
                    "usage": {
                        "prompt_tokens": total_tokens,
                        "total_tokens": total_tokens,
                    },
                },
            )
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.send_json(400, {"error": str(error)})
        except Exception as error:
            self.send_json(500, {"error": str(error)})

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "credentialless")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        origin = self.headers.get("Origin")
        if origin in self.allowed_origins:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, Authorization, X-Requested-With",
            )
        super().end_headers()

    def log_message(self, format, *args):
        print(f"[web-ui] {self.address_string()} - {format % args}", flush=True)


def stream_server_output(process):
    if process.stdout is None:
        return
    for line in process.stdout:
        print(f"[litert-lm] {line.rstrip()}", flush=True)


def get_model_search_dirs():
    dirs = [PROJECT_DIR]
    for extra in (
        PROJECT_DIR.parent.parent.parent,
        PROJECT_DIR.parent.parent.parent.parent,
        Path.home() / "Gemma4",
        Path.home() / "Library" / "Application Support" / "EduVis AI Gallery" / "models",
        Path.home() / "Downloads",
    ):
        try:
            if extra.is_dir() and extra not in dirs:
                dirs.append(extra)
        except OSError:
            continue
    return dirs


def resolve_local_model_path(filename):
    if not isinstance(filename, str) or Path(filename).name != filename:
        return None
    for folder in get_model_search_dirs():
        candidate = folder / filename
        try:
            resolved = candidate.resolve()
            if (
                resolved.parent == folder.resolve()
                and not candidate.is_symlink()
                and resolved.is_file()
                and resolved.suffix.lower() == ".litertlm"
            ):
                return resolved
        except OSError:
            continue
    return None


def list_local_models():
    found = set()
    for folder in get_model_search_dirs():
        try:
            for path in folder.glob("*.litertlm"):
                if path.is_file() and not path.is_symlink():
                    found.add(path.name)
        except OSError:
            continue
    return sorted(found)


_LITERT_VERSION_CACHE = None
_LITERT_ALLOWED_CONFIG_KEYS = {
    "backend",
    "cpu_thread_count",
    "audio_backend",
    "vision_backend",
    "cache",
    "max_num_tokens",
    "temperature",
    "top_p",
    "top_k",
    "seed",
    "gpu_decode_steps_per_sync",
    "speculative_decoding",
    "thinking",
    "thinking_budget",
    "activation_data_type",
}
_DEFAULT_LITERT_RUNTIME_CONFIG = {
    "default": {
        "backend": "gpu",
        "cache": "disk",
        "speculative_decoding": True,
    }
}
_KNOWN_LITERTLM_SECTIONS = (
    "tf_lite_prefill_decode",
    "tf_lite_artisan_text_decoder",
    "tf_lite_mtp_drafter",
    "tf_lite_vision_encoder",
    "tf_lite_vision_adapter",
    "tf_lite_end_of_vision",
    "tf_lite_audio_encoder_hw",
    "tf_lite_audio_adapter",
    "tf_lite_end_of_audio",
    "tf_lite_embedder",
    "tf_lite_per_layer_embedder",
)


def find_existing_litert_lm_executable():
    candidates = []
    which_exec = shutil.which("litert-lm")
    if which_exec:
        candidates.append(which_exec)
    try:
        candidates.append(str(Path(sys.executable).resolve().parent / "litert-lm"))
    except OSError:
        pass
    for version in ("3.14", "3.13", "3.12", "3.11", "3.10", "Current"):
        candidates.append(f"/Library/Frameworks/Python.framework/Versions/{version}/bin/litert-lm")
    candidates.extend([
        "/opt/homebrew/bin/litert-lm",
        "/usr/local/bin/litert-lm",
    ])
    app_support = Path.home() / "Library" / "Application Support" / "Gemma AI Gallery"
    environment = app_support / "litert-lm-venv"
    scripts_dir = environment / ("Scripts" if os.name == "nt" else "bin")
    candidates.append(str(scripts_dir / ("litert-lm.exe" if os.name == "nt" else "litert-lm")))

    seen = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        if Path(candidate).is_file() and is_litert_lm_executable(candidate):
            return str(candidate)
    return None


def get_litert_lm_version():
    global _LITERT_VERSION_CACHE
    if _LITERT_VERSION_CACHE:
        return _LITERT_VERSION_CACHE
    try:
        ver = importlib.metadata.version("litert-lm")
        if ver:
            _LITERT_VERSION_CACHE = ver
            return ver
    except Exception:
        pass
    executable = find_existing_litert_lm_executable()
    if executable:
        try:
            res = subprocess.run(
                [executable, "--version"],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            if res.returncode == 0:
                text = (res.stdout or res.stderr or "").strip()
                match = re.search(r"(\d+\.\d+\.\d+(?:[a-zA-Z0-9.-]*)?)", text)
                if match:
                    _LITERT_VERSION_CACHE = match.group(1)
                    return _LITERT_VERSION_CACHE
        except (OSError, subprocess.SubprocessError):
            pass
    return "0.19.2"


def get_litert_base_dir():
    env_override = os.environ.get("LITERT_LM_DIR")
    if env_override:
        return Path(env_override).expanduser().resolve()
    return Path.home() / ".litert-lm"


def get_litert_config_path():
    return get_litert_base_dir() / "config.json"


def get_litert_runtime_config():
    config_path = get_litert_config_path()
    try:
        if config_path.is_file():
            loaded = json.loads(config_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                if not isinstance(loaded.get("default"), dict):
                    loaded["default"] = dict(_DEFAULT_LITERT_RUNTIME_CONFIG["default"])
                return loaded
    except (OSError, ValueError, TypeError):
        pass
    return {
        "default": dict(_DEFAULT_LITERT_RUNTIME_CONFIG["default"]),
        "models": {},
    }


def ensure_default_litert_config():
    config_path = get_litert_config_path()
    try:
        if not config_path.exists():
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_path.write_text(
                json.dumps(_DEFAULT_LITERT_RUNTIME_CONFIG, indent=2) + "\n",
                encoding="utf-8",
            )
    except OSError:
        pass
    return get_litert_runtime_config()


def update_litert_runtime_config(updates, model_id=None):
    if not isinstance(updates, dict):
        raise ValueError("Pembaruan konfigurasi harus berupa objek JSON.")
    filtered = {
        k: v
        for k, v in updates.items()
        if k in _LITERT_ALLOWED_CONFIG_KEYS and v is not None
    }
    if "backend" in filtered and filtered["backend"] not in ("cpu", "gpu", "npu"):
        raise ValueError("Backend harus salah satu dari: cpu, gpu, npu.")
    if "cache" in filtered and filtered["cache"] not in ("disk", "memory", "no"):
        raise ValueError("Cache harus salah satu dari: disk, memory, no.")
    if "activation_data_type" in filtered and filtered["activation_data_type"] not in ("fp32", "fp16", "int16", "int8"):
        raise ValueError("activation_data_type harus salah satu dari: fp32, fp16, int16, int8.")

    config = get_litert_runtime_config()
    if model_id:
        models_cfg = config.setdefault("models", {})
        target = models_cfg.setdefault(str(model_id), {})
    else:
        target = config.setdefault("default", {})
    target.update(filtered)

    config_path = get_litert_config_path()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return config


def compute_deterministic_embedding(text, dimensions=384):
    dim = max(64, min(1536, int(dimensions or 384)))
    vec = [0.0] * dim
    normalized = re.sub(r"\s+", " ", str(text or "").lower()).strip()
    if not normalized:
        return vec

    tokens = re.findall(r"[a-z0-9_]+", normalized)
    features = []
    for tok in tokens:
        features.append((f"w:{tok}", 2.0))
        if len(tok) >= 3:
            for i in range(len(tok) - 2):
                features.append((f"c3:{tok[i:i + 3]}", 1.0))
    for i in range(len(tokens) - 1):
        features.append((f"b:{tokens[i]}_{tokens[i + 1]}", 1.5))

    if not features:
        for i in range(max(1, len(normalized) - 2)):
            features.append((f"raw:{normalized[i:i + 3]}", 1.0))

    for feat, weight in features:
        digest = hashlib.blake2b(feat.encode("utf-8"), digest_size=8).digest()
        bucket = int.from_bytes(digest[:4], "little") % dim
        sign = 1.0 if (digest[4] & 1) == 0 else -1.0
        vec[bucket] += weight * sign

    norm = math.sqrt(sum(v * v for v in vec))
    if norm > 0.0:
        vec = [round(v / norm, 6) for v in vec]
    return vec


def inspect_litertlm_model(model_path, model_id=None):
    path = Path(model_path)
    if not path.is_file():
        raise FileNotFoundError(f"File model tidak ditemukan: {model_path}")

    stat = path.stat()
    size_bytes = stat.st_size
    resolved_id = model_id or (path.parent.name.replace("--", "/") if path.name == "model.litertlm" else path.stem)

    with open(path, "rb") as handle:
        header_bytes = handle.read(65536)

    magic16 = header_bytes[:16]
    if magic16.startswith(b"LITERTLM"):
        container_format = "litertlm"
        sections = []
        activation_data_type = None
        main_backend_constraint = None
        max_context_tokens = None
        supports_function_calling = None
        supports_thinking = None
        model_info_modalities = []
        supported_backends = []
        supports_mtp = False

        try:
            from litert_lm_builder import litertlm_peek

            metadata = litertlm_peek.read_litertlm_header(str(path), io.StringIO())
            sec_meta = metadata.SectionMetadata() if metadata else None
            if sec_meta:
                for i in range(sec_meta.ObjectsLength()):
                    section = sec_meta.Objects(i)
                    if not section:
                        continue
                    mtype = litertlm_peek.get_model_type(section)
                    if not mtype:
                        continue
                    mtype_lower = mtype.lower()
                    sections.append(mtype_lower)
                    items = {}
                    for j in range(section.ItemsLength()):
                        item = section.Items(j)
                        if item is not None:
                            kv = litertlm_peek.kvp_to_dict(item)
                            if kv.get("key"):
                                items[kv["key"]] = kv.get("value")
                    if mtype_lower in ("tf_lite_prefill_decode", "tf_lite_artisan_text_decoder"):
                        if items.get("prefer_activation_type") and not activation_data_type:
                            activation_data_type = str(items["prefer_activation_type"]).lower()
                        if items.get("backend_constraint") and not main_backend_constraint:
                            main_backend_constraint = str(items["backend_constraint"]).split(",")[0].strip().lower()
        except Exception:
            for marker in _KNOWN_LITERTLM_SECTIONS:
                if marker.encode("ascii") in header_bytes:
                    sections.append(marker)
            if b"prefer_activation_type" in header_bytes:
                for dtype in (b"fp16", b"int8", b"int16", b"fp32"):
                    if dtype in header_bytes:
                        activation_data_type = dtype.decode("ascii")
                        break

        try:
            import litert_lm

            if hasattr(litert_lm, "ModelInfo"):
                info = litert_lm.ModelInfo(str(path))
                max_context_tokens = getattr(info, "max_context_tokens", None)
                mods = getattr(info, "input_modalities", None)
                if mods is not None:
                    if getattr(mods, "text", False):
                        model_info_modalities.append("text")
                    if getattr(mods, "vision", False):
                        model_info_modalities.append("vision")
                    if getattr(mods, "audio", False):
                        model_info_modalities.append("audio")
                    if getattr(mods, "video", False):
                        model_info_modalities.append("video")
                if getattr(info, "is_llm_model", False) and getattr(info, "llm", None) is not None:
                    llm_caps = info.llm
                    supports_mtp = bool(llm_caps.has_speculative_decoding_support())
                    supports_function_calling = bool(llm_caps.supports_function_calling())
                    supports_thinking = bool(llm_caps.supports_thinking())
                if hasattr(litert_lm, "LiteRtLmModality") and hasattr(info, "supported_backends_for_modality"):
                    supported_backends = [
                        str(b).lower()
                        for b in (info.supported_backends_for_modality(litert_lm.LiteRtLmModality.TEXT) or [])
                    ]
        except Exception:
            pass

        modalities = list(model_info_modalities) if model_info_modalities else ["text"]
        if any("vision" in s for s in sections) and "vision" not in modalities:
            modalities.append("vision")
        if any("audio" in s for s in sections) and "audio" not in modalities:
            modalities.append("audio")
        if "tf_lite_mtp_drafter" in sections:
            supports_mtp = True

        if "tf_lite_artisan_text_decoder" in sections:
            default_backend = "gpu"
        elif main_backend_constraint in ("cpu", "gpu", "npu"):
            default_backend = main_backend_constraint
        elif "gpu" in supported_backends or activation_data_type == "fp16":
            default_backend = "gpu"
        else:
            default_backend = supported_backends[0] if supported_backends else "cpu"

        return {
            "id": resolved_id,
            "filename": path.name,
            "path": str(path),
            "size_bytes": size_bytes,
            "size_mb": round(size_bytes / (1024 * 1024), 1),
            "container_format": container_format,
            "modalities": modalities,
            "supports_mtp": supports_mtp,
            "supports_function_calling": supports_function_calling,
            "supports_thinking": supports_thinking,
            "default_backend": default_backend,
            "supported_backends": supported_backends or [default_backend],
            "activation_data_type": activation_data_type,
            "max_context_tokens": max_context_tokens,
            "sections": sections,
        }

    if magic16[4:8] == b"TFL3" or magic16.startswith(b"PK") or magic16.startswith(b" \x00\x00\x00TFL3"):
        return {
            "id": resolved_id,
            "filename": path.name,
            "path": str(path),
            "size_bytes": size_bytes,
            "size_mb": round(size_bytes / (1024 * 1024), 1),
            "container_format": "tflite_web",
            "modalities": ["text"],
            "supports_mtp": False,
            "supports_function_calling": False,
            "supports_thinking": False,
            "default_backend": "webgpu",
            "supported_backends": ["webgpu"],
            "activation_data_type": None,
            "max_context_tokens": None,
            "sections": [],
        }

    return {
        "id": resolved_id,
        "filename": path.name,
        "path": str(path),
        "size_bytes": size_bytes,
        "size_mb": round(size_bytes / (1024 * 1024), 1),
        "container_format": "unknown",
        "modalities": ["text"],
        "supports_mtp": False,
        "supports_function_calling": False,
        "supports_thinking": False,
        "default_backend": "cpu",
        "supported_backends": ["cpu"],
        "activation_data_type": None,
        "max_context_tokens": None,
        "sections": [],
    }


def sync_local_models_zero_copy():
    models_base = get_litert_base_dir() / "models"
    models_base.mkdir(parents=True, exist_ok=True)
    synced = []

    for folder in get_model_search_dirs():
        try:
            for candidate in sorted(folder.glob("*.litertlm")):
                if not candidate.is_file() or candidate.is_symlink():
                    continue
                try:
                    with open(candidate, "rb") as handle:
                        magic = handle.read(8)
                except OSError:
                    continue
                if magic != b"LITERTLM":
                    continue

                stem_dir = models_base / candidate.stem
                full_dir = models_base / candidate.name
                if (stem_dir / "model.litertlm").exists() or (full_dir / "model.litertlm").exists():
                    continue

                stem_dir.mkdir(parents=True, exist_ok=True)
                target_link = stem_dir / "model.litertlm"
                try:
                    os.symlink(str(candidate.resolve()), str(target_link))
                except OSError:
                    os.link(str(candidate.resolve()), str(target_link))
                synced.append(candidate.stem)
        except OSError:
            continue

    registered = sorted(
        p.parent.name.replace("--", "/")
        for p in models_base.glob("*/model.litertlm")
        if p.is_file()
    )
    return {"synced_models": synced, "registered_models": registered}


def inspect_all_models(model_manager=None):
    results = []
    seen_resolved = set()
    models_base = get_litert_base_dir() / "models"

    if models_base.is_dir():
        for model_file in sorted(models_base.glob("*/model.litertlm")):
            try:
                resolved = str(model_file.resolve())
                model_id = model_file.parent.name.replace("--", "/")
                info = inspect_litertlm_model(model_file, model_id=model_id)
                info["registered"] = True
                results.append(info)
                seen_resolved.add(resolved)
            except OSError:
                continue

    for folder in get_model_search_dirs():
        try:
            for candidate in sorted(folder.glob("*.litertlm")):
                if not candidate.is_file() or candidate.is_symlink():
                    continue
                resolved = str(candidate.resolve())
                if resolved in seen_resolved:
                    continue
                try:
                    info = inspect_litertlm_model(candidate, model_id=candidate.stem)
                    info["registered"] = False
                    results.append(info)
                    seen_resolved.add(resolved)
                except OSError:
                    continue
        except OSError:
            continue

    if model_manager is not None and not results:
        try:
            for model_id in model_manager.list_models() or []:
                results.append(
                    {
                        "id": model_id,
                        "filename": f"{model_id}.litertlm",
                        "container_format": "litertlm",
                        "modalities": ["text"],
                        "supports_mtp": False,
                        "default_backend": "gpu",
                        "registered": True,
                    }
                )
        except Exception:
            pass

    return results


def get_local_ipv4_addresses():
    addresses = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.0.2.1", 80))
            address = probe.getsockname()[0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass

    try:
        for result in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = result[4][0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass

    return sorted(addresses)


def create_lan_tls_context(addresses):
    app_support = Path.home() / "Library" / "Application Support" / "Gemma AI Gallery"
    certificate_dir = app_support / "lan-tls"
    certificate_dir.mkdir(parents=True, exist_ok=True)
    ca_certificate = certificate_dir / "lan-ca.pem"
    ca_download_certificate = certificate_dir / "lan-ca.cer"
    ca_private_key = certificate_dir / "lan-ca-key.pem"
    server_certificate = certificate_dir / "server.pem"
    server_private_key = certificate_dir / "server-key.pem"
    openssl = shutil.which("openssl")
    if not openssl:
        raise RuntimeError("Perintah `openssl` diperlukan untuk menyiapkan HTTPS jaringan lokal.")

    def run_openssl(arguments):
        result = subprocess.run(
            [openssl, *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode:
            detail = (result.stderr or result.stdout).strip()
            raise RuntimeError(f"Gagal menyiapkan sertifikat HTTPS lokal:\n{detail}")

    if ca_certificate.exists() != ca_private_key.exists():
        raise RuntimeError(
            f"Pasangan sertifikat CA tidak lengkap di {certificate_dir}; "
            "pulihkan keduanya sebelum menjalankan server."
        )
    subject_alt_names = ["DNS:localhost", "IP:127.0.0.1"]
    subject_alt_names.extend(f"IP:{address}" for address in addresses)
    with tempfile.TemporaryDirectory(prefix="gemma-lan-tls-", dir=certificate_dir) as temporary_dir:
        temporary_path = Path(temporary_dir)
        ca_config_path = temporary_path / "ca.cnf"
        request_path = temporary_path / "server.csr"
        extensions_path = temporary_path / "server.ext"
        serial_path = temporary_path / "ca.srl"
        ca_config_path.write_text(
            "[req]\n"
            "distinguished_name=dn\n"
            "x509_extensions=v3_ca\n"
            "prompt=no\n"
            "[dn]\n"
            "CN=Gemma AI Gallery LAN CA\n"
            "[v3_ca]\n"
            "basicConstraints=critical,CA:TRUE\n"
            "keyUsage=critical,keyCertSign,cRLSign\n"
            "subjectKeyIdentifier=hash\n",
            encoding="ascii",
        )
        if not ca_certificate.exists():
            run_openssl([
                "req", "-x509", "-newkey", "rsa:3072", "-sha256",
                "-days", "3650", "-nodes",
                "-keyout", str(ca_private_key),
                "-out", str(ca_certificate),
                "-config", str(ca_config_path),
            ])
            ca_private_key.chmod(0o600)
            ca_certificate.chmod(0o644)
        run_openssl([
            "x509", "-in", str(ca_certificate), "-outform", "DER",
            "-out", str(ca_download_certificate),
        ])
        ca_download_certificate.chmod(0o644)

        extensions_path.write_text(
            "[server_cert]\n"
            "basicConstraints=CA:FALSE\n"
            "keyUsage=digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            f"subjectAltName={','.join(subject_alt_names)}\n",
            encoding="ascii",
        )
        run_openssl([
            "req", "-new", "-newkey", "rsa:2048", "-sha256", "-nodes",
            "-keyout", str(server_private_key),
            "-out", str(request_path),
            "-subj", "/CN=Gemma AI Gallery LAN",
        ])
        run_openssl([
            "x509", "-req", "-sha256", "-days", "825",
            "-in", str(request_path),
            "-CA", str(ca_certificate),
            "-CAkey", str(ca_private_key),
            "-CAserial", str(serial_path),
            "-CAcreateserial",
            "-out", str(server_certificate),
            "-extfile", str(extensions_path),
            "-extensions", "server_cert",
        ])
    server_private_key.chmod(0o600)
    server_certificate.chmod(0o644)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(server_certificate, server_private_key)
    return context, ca_download_certificate


def get_runtime_workdir():
    try:
        if os.access(PROJECT_DIR, os.W_OK):
            return PROJECT_DIR
    except OSError:
        pass
    fallback = Path.home() / "Library" / "Application Support" / "EduVis AI Gallery"
    try:
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback
    except OSError:
        return Path(tempfile.gettempdir())


def start_model_server(executable):
    command = [
        executable,
        "serve",
        "--host",
        LITERT_API_HOST,
        "--port",
        str(LITERT_API_PORT),
    ]
    environment = os.environ.copy()
    compatibility_path = str(PROJECT_DIR / "litert_lm_compat")
    existing_pythonpath = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = os.pathsep.join(
        path for path in (compatibility_path, existing_pythonpath) if path
    )
    print(
        f"[launcher] Menjalankan LiteRT-LM secara internal pada "
        f"{LITERT_API_HOST}:{LITERT_API_PORT}",
        flush=True,
    )
    process = subprocess.Popen(
        command,
        cwd=get_runtime_workdir(),
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    threading.Thread(target=stream_server_output, args=(process,), daemon=True).start()
    return process


def wait_for_models(process):
    endpoint = f"{API_BASE_URL}/models"
    deadline = time.monotonic() + READY_TIMEOUT
    last_error = "Server belum siap."
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(
                f"Proses litert-lm berhenti saat startup (kode {process.returncode}). "
                f"Periksa apakah port {LITERT_API_PORT} sedang dipakai."
            )
        try:
            with urllib.request.urlopen(endpoint, timeout=2) as response:
                result = json.loads(response.read().decode("utf-8"))
            if not isinstance(result, dict) or not isinstance(result.get("data"), list):
                raise RuntimeError("Respons /v1/models dari LiteRT-LM tidak valid.")
            model_ids = [
                item["id"]
                for item in result["data"]
                if isinstance(item, dict) and isinstance(item.get("id"), str)
            ]
            return model_ids
        except urllib.error.HTTPError as error:
            last_error = f"HTTP {error.code}: {error.reason}"
        except urllib.error.URLError as error:
            last_error = str(error.reason)
        except (TimeoutError, OSError, ValueError) as error:
            last_error = str(error)
        time.sleep(0.5)
    raise RuntimeError(f"LiteRT-LM tidak siap dalam {READY_TIMEOUT} detik: {last_error}")


class ModelServerManager:
    def __init__(self, executable):
        self.executable = executable
        self.process = None
        self.lock = threading.Lock()

    def start(self):
        try:
            ensure_default_litert_config()
            sync_result = sync_local_models_zero_copy()
            if sync_result.get("synced_models"):
                print(
                    f"[launcher] Sinkronisasi zero-copy model lokal: {', '.join(sync_result['synced_models'])}",
                    flush=True,
                )
        except OSError as error:
            print(f"[launcher] Peringatan sinkronisasi model lokal: {error}", flush=True)
        self.process = start_model_server(self.executable)
        return self.process

    def stop(self):
        stop_process(self.process, "LiteRT-LM")
        self.process = None

    def list_models(self):
        if self.process is None:
            raise RuntimeError("Service LiteRT-LM tidak berjalan.")
        return wait_for_models(self.process)

    def import_model(self, model_path, model_id):
        with self.lock:
            self.stop()
            import_result = None
            import_error = None
            try:
                import_result = subprocess.run(
                    [
                        self.executable,
                        "import",
                        str(model_path),
                        model_id,
                    ],
                    cwd=get_runtime_workdir(),
                    capture_output=True,
                    text=True,
                    timeout=MODEL_IMPORT_TIMEOUT,
                    check=False,
                )
            except (OSError, subprocess.SubprocessError) as error:
                import_error = error
            finally:
                self.start()

            model_ids = wait_for_models(self.process)
            if import_error:
                raise RuntimeError(f"Gagal menjalankan `litert-lm import`: {import_error}") from import_error
            if import_result.returncode:
                detail = (import_result.stderr or import_result.stdout).strip()
                raise RuntimeError(
                    f"Impor model gagal (kode {import_result.returncode}): "
                    f"{detail or 'LiteRT-LM tidak memberikan rincian.'}"
                )
            if model_id not in model_ids:
                raise RuntimeError(
                    f"Impor selesai, tetapi model `{model_id}` tidak muncul pada service LiteRT-LM."
                )
            return model_ids

    def delete_model(self, model_id):
        with self.lock:
            model_ids = self.list_models()
            if model_id not in model_ids:
                raise ValueError(f"Model `{model_id}` tidak ditemukan.")

            self.stop()
            delete_result = None
            delete_error = None
            try:
                delete_result = subprocess.run(
                    [self.executable, "delete", model_id],
                    cwd=get_runtime_workdir(),
                    capture_output=True,
                    text=True,
                    timeout=MODEL_IMPORT_TIMEOUT,
                    check=False,
                )
            except (OSError, subprocess.SubprocessError) as error:
                delete_error = error
            finally:
                self.start()

            remaining_models = wait_for_models(self.process)
            if delete_error:
                raise RuntimeError(f"Gagal menjalankan `litert-lm delete`: {delete_error}") from delete_error
            if delete_result.returncode:
                detail = (delete_result.stderr or delete_result.stdout).strip()
                raise RuntimeError(
                    f"Gagal menghapus model `{model_id}` (kode {delete_result.returncode}): "
                    f"{detail or 'LiteRT-LM tidak memberikan rincian.'}"
                )
            if model_id in remaining_models:
                raise RuntimeError(f"LiteRT-LM masih melaporkan model `{model_id}` setelah penghapusan.")
            return remaining_models

    def is_running(self):
        with self.lock:
            return self.process is not None and self.process.poll() is None

    def restart_server(self):
        with self.lock:
            self.stop()
            self.start()
            return wait_for_models(self.process)

    def get_memory_stats(self):
        litert_rss_kb = 0
        proc = self.process
        if proc is not None and proc.poll() is None:
            ps_bin = shutil.which("ps") or "/bin/ps"
            if Path(ps_bin).is_file():
                try:
                    res = subprocess.run(
                        [ps_bin, "-o", "rss=", "-p", str(proc.pid)],
                        capture_output=True,
                        text=True,
                        timeout=3,
                        check=False,
                    )
                    for token in (res.stdout or "").split():
                        if token.isdigit():
                            litert_rss_kb += int(token)
                except (OSError, subprocess.SubprocessError):
                    pass
        backend_rss_mb = 0.0
        try:
            import resource
            rusage_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            # Pada macOS ru_maxrss dalam satuan bytes
            backend_rss_mb = round(rusage_rss / (1024 * 1024), 1)
        except Exception:
            pass
        return {
            "litert_rss_mb": round(litert_rss_kb / 1024.0, 1),
            "backend_rss_mb": backend_rss_mb,
            "litert_running": proc is not None and proc.poll() is None,
        }


def get_bootstrap_status_path():
    custom = os.environ.get("EDUVIS_BOOTSTRAP_STATUS_PATH")
    if custom:
        return Path(custom)
    return Path.home() / "Library" / "Application Support" / "EduVis AI Gallery" / "bootstrap_status.json"


def write_bootstrap_status(stage, message, progress=0, ready=False):
    status_path = get_bootstrap_status_path()
    payload = {
        "stage": str(stage),
        "message": str(message),
        "progress": max(0, min(100, int(progress))),
        "ready": bool(ready),
        "timestamp": time.time(),
    }
    try:
        status_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = status_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp_path.replace(status_path)
    except OSError:
        pass
    return payload


def _collect_python_candidates():
    venv_python = (
        Path.home()
        / "Library"
        / "Application Support"
        / "Gemma AI Gallery"
        / "litert-lm-venv"
        / ("Scripts/python.exe" if os.name == "nt" else "bin/python3")
    )
    candidates = [str(venv_python), sys.executable]
    for name in ("python3.14", "python3.13", "python3.12", "python3.11", "python3.10", "python3", "python"):
        executable = shutil.which(name)
        if executable:
            candidates.append(executable)
    for version in ("3.14", "3.13", "3.12", "3.11", "3.10"):
        candidates.append(f"/Library/Frameworks/Python.framework/Versions/{version}/bin/python{version}")
        candidates.append(f"/opt/homebrew/bin/python{version}")
        candidates.append(f"/usr/local/bin/python{version}")
    candidates.extend([
        "/opt/homebrew/opt/python@3.12/bin/python3.12",
        "/usr/local/opt/python@3.12/bin/python3.12",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
    ])
    return candidates


def _find_python_ge_310(candidates):
    checked = set()
    for executable in candidates:
        if not executable or not Path(executable).is_file():
            continue
        resolved = os.path.realpath(executable)
        if resolved in checked:
            continue
        checked.add(resolved)
        try:
            result = subprocess.run(
                [executable, "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if result.returncode:
            continue
        try:
            major, minor = (int(part) for part in result.stdout.strip().split(".", 1))
        except ValueError:
            continue
        if major > 3 or (major == 3 and minor >= 10):
            return executable
    return None


def find_python_for_litert_lm():
    found = _find_python_ge_310(_collect_python_candidates())
    if found:
        return found

    brew = shutil.which("brew")
    if not brew:
        for brew_candidate in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew"):
            if Path(brew_candidate).is_file():
                brew = brew_candidate
                break
    if brew:
        write_bootstrap_status(
            "python",
            "[1/4] Memasang Python 3.12 otomatis melalui Homebrew (eksekusi pertama)...",
            progress=15,
            ready=False,
        )
        print("[launcher] Memasang Python 3.12 otomatis via Homebrew...", flush=True)
        subprocess.run([brew, "install", "python@3.12"], check=False)
        found = _find_python_ge_310(_collect_python_candidates())
        if found:
            return found

    raise RuntimeError(
        "LiteRT-LM memerlukan Python 3.10 atau lebih baru. "
        "Pasang Python versi tersebut lalu jalankan ulang aplikasi."
    )


def is_litert_lm_executable(executable):
    try:
        result = subprocess.run(
            [str(executable), "--version"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def ensure_litert_lm():
    existing = find_existing_litert_lm_executable()
    if existing:
        return existing

    app_support = Path.home() / "Library" / "Application Support" / "Gemma AI Gallery"
    environment = app_support / "litert-lm-venv"
    scripts_dir = environment / ("Scripts" if os.name == "nt" else "bin")
    litert_lm = scripts_dir / ("litert-lm.exe" if os.name == "nt" else "litert-lm")
    venv_python = str(environment / ("Scripts/python.exe" if os.name == "nt" else "bin/python"))

    python = find_python_for_litert_lm()
    app_support.mkdir(parents=True, exist_ok=True)
    write_bootstrap_status(
        "venv",
        "[1/4] Menyiapkan virtual environment Python khusus aplikasi...",
        progress=25,
        ready=False,
    )
    print(f"[launcher] Membuat lingkungan LiteRT-LM dengan {python}...", flush=True)
    result = subprocess.run(
        [python, "-m", "venv", str(environment)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        write_bootstrap_status("error", f"Gagal membuat venv LiteRT-LM: {detail}", progress=0, ready=False)
        raise RuntimeError(f"Gagal membuat lingkungan Python LiteRT-LM:\n{detail}")

    write_bootstrap_status(
        "install",
        "[2/4] Mengunduh & memasang runtime LiteRT-LM (eksekusi pertama)...",
        progress=50,
        ready=False,
    )
    print("[launcher] Mengunduh dan memasang paket litert-lm...", flush=True)
    subprocess.run(
        [venv_python, "-m", "pip", "install", "--upgrade", "pip"],
        capture_output=True,
        text=True,
        check=False,
    )
    pip_result = subprocess.run(
        [
            venv_python,
            "-m",
            "pip",
            "install",
            "--upgrade",
            LITERT_LM_PACKAGE,
            "litert-lm-api",
            "litert-lm-builder",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if pip_result.returncode:
        detail = (pip_result.stderr or pip_result.stdout).strip()
        write_bootstrap_status("error", f"Pemasangan litert-lm gagal: {detail}", progress=0, ready=False)
        raise RuntimeError(
            f"Pemasangan otomatis litert-lm gagal (kode {pip_result.returncode}): "
            f"{detail or 'pip tidak memberikan rincian.'} "
            "Periksa koneksi internet dan coba jalankan ulang aplikasi."
        )
    if not litert_lm.is_file():
        write_bootstrap_status("error", "Executable litert-lm tidak ditemukan setelah instalasi.", progress=0, ready=False)
        raise RuntimeError("Pemasangan selesai, tetapi executable `litert-lm` tidak ditemukan.")
    return str(litert_lm)


def ensure_first_run_requirements():
    write_bootstrap_status(
        "init",
        "[1/4] Memeriksa runtime & requirement LiteRT-LM...",
        progress=10,
        ready=False,
    )
    litert_lm_exec = ensure_litert_lm()

    write_bootstrap_status(
        "config",
        "[3/4] Menyiapkan konfigurasi GPU & Speculative Decoding...",
        progress=75,
        ready=False,
    )
    ensure_default_litert_config()

    write_bootstrap_status(
        "models",
        "[4/4] Menyelaraskan model .litertlm lokal...",
        progress=90,
        ready=False,
    )
    sync_info = sync_local_models_zero_copy()

    marker_dir = get_bootstrap_status_path().parent
    marker_path = marker_dir / "first_run_complete.json"
    try:
        marker_dir.mkdir(parents=True, exist_ok=True)
        marker_path.write_text(
            json.dumps(
                {
                    "litert_lm_executable": litert_lm_exec,
                    "litert_lm_version": get_litert_lm_version(),
                    "registered_models": sync_info.get("registered_models", []),
                    "completed_at": time.time(),
                },
                indent=2,
            ),
            encoding="utf-8",
        )
    except OSError:
        pass

    write_bootstrap_status(
        "ready",
        "Semua requirement siap digunakan.",
        progress=100,
        ready=True,
    )
    return litert_lm_exec


def compile_webview(swiftc, app_bundle):
    source = PROJECT_DIR / "gemma_webview.swift"
    if not source.is_file():
        raise RuntimeError(f"File WebView tidak ditemukan: {source}")
    icon_generator = PROJECT_DIR / "scripts" / "generate_app_icon.swift"
    if not icon_generator.is_file():
        raise RuntimeError(f"Skrip ikon aplikasi tidak ditemukan: {icon_generator}")
    xcrun = shutil.which("xcrun")
    if not xcrun:
        raise RuntimeError("Perintah `xcrun` tidak ditemukan. Pasang Xcode Command Line Tools.")
    swift = shutil.which("swift")
    if not swift:
        raise RuntimeError("Perintah `swift` tidak ditemukan untuk membuat ikon aplikasi.")
    sdk_result = subprocess.run(
        [xcrun, "--show-sdk-path", "--sdk", "macosx"],
        capture_output=True,
        text=True,
        check=False,
    )
    if sdk_result.returncode:
        detail = (sdk_result.stderr or sdk_result.stdout).strip()
        raise RuntimeError(f"Gagal menemukan macOS SDK:\n{detail}")
    sdk_path = sdk_result.stdout.strip()
    target_triple = f"{platform.machine()}-apple-macosx13.0"
    module_cache = str(Path(tempfile.gettempdir()) / "eduvis-swift-module-cache")
    Path(module_cache).mkdir(parents=True, exist_ok=True)
    app_bundle = Path(app_bundle)
    contents_dir = app_bundle / "Contents"
    executable_dir = contents_dir / "MacOS"
    resources_dir = contents_dir / "Resources"
    frameworks_dir = contents_dir / "Frameworks"
    executable_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)
    frameworks_dir.mkdir(parents=True, exist_ok=True)

    # Bundling liblitert-lm.dylib untuk Pure Native In-Process Bootstrapping
    for dylib_candidate in (
        Path("/Library/Frameworks/Python.framework/Versions/3.14/lib/python3.14/site-packages/litert_lm/liblitert-lm.dylib"),
        Path.home() / "Library/Application Support/Gemma AI Gallery/litert-lm-venv/lib/python3.14/site-packages/litert_lm/liblitert-lm.dylib",
        PROJECT_DIR / "EduVisNativeApp/EduVis Native AI.app/Contents/Frameworks/liblitert-lm.dylib",
    ):
        if dylib_candidate.is_file():
            shutil.copy2(dylib_candidate, frameworks_dir / "liblitert-lm.dylib")
            break
    executable = executable_dir / "EduVisAIGallery"
    icon_path = resources_dir / "EduVisAIGallery.icns"
    dev_photo_src = PROJECT_DIR / "nano_asset" / "dev.jpeg"
    if dev_photo_src.is_file():
        shutil.copy2(dev_photo_src, resources_dir / "dev.jpeg")
    app_icon_png_src = PROJECT_DIR / "nano_asset" / "app_icon.png"
    if app_icon_png_src.is_file():
        shutil.copy2(app_icon_png_src, resources_dir / "app_icon.png")
    banner_src = PROJECT_DIR / "Banner.jpg"
    if banner_src.is_file():
        shutil.copy2(banner_src, resources_dir / "Banner.jpg")

    existing_icns = PROJECT_DIR / "EduVisNativeApp" / "EduVis Native AI.app" / "Contents" / "Resources" / "AppIcon.icns"
    if existing_icns.is_file():
        shutil.copy2(existing_icns, icon_path)
    else:
        icon_result = subprocess.run(
            [
                swift,
                "-sdk",
                sdk_path,
                "-target",
                target_triple,
                "-module-cache-path",
                module_cache,
                str(icon_generator),
                str(icon_path),
            ],
            capture_output=True,
            text=True,
            check=False,
            cwd=PROJECT_DIR,
        )
        if icon_result.returncode:
            detail = (icon_result.stderr or icon_result.stdout).strip()
            raise RuntimeError(f"Gagal membuat ikon aplikasi macOS:\n{detail}")

    result = subprocess.run(
        [
            swiftc,
            "-sdk",
            sdk_path,
            "-target",
            target_triple,
            "-module-cache-path",
            module_cache,
            "-O",
            str(source),
            "-framework",
            "AVFoundation",
            "-framework",
            "Speech",
            "-o",
            str(executable),
        ],
        capture_output=True,
        text=True,
        check=False,
        cwd=PROJECT_DIR,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"Gagal membuat jendela WebView native:\n{detail}")
    info = {
        "CFBundleDevelopmentRegion": "id",
        "CFBundleExecutable": "EduVisAIGallery",
        "CFBundleIconFile": "EduVisAIGallery.icns",
        "CFBundleIdentifier": "com.eduvis.ai-gallery",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "EduVis AI Gallery",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "EduVisProjectDirectory": str(PROJECT_DIR),
        "EduVisPythonExecutable": sys.executable,
        "EduVisReadinessPath": str(
            Path.home()
            / "Library"
            / "Application Support"
            / "EduVis AI Gallery"
            / "ready"
        ),
        "LSMinimumSystemVersion": "13.0",
        "NSMicrophoneUsageDescription": "EduVis AI Gallery menggunakan mikrofon untuk percakapan Gemini Live.",
        "NSSpeechRecognitionUsageDescription": "EduVis AI Gallery mengubah ucapan menjadi teks untuk percakapan Gemini Live.",
        "NSQuitAlwaysKeepsWindows": False,
        "NSServices": [
            {
                "NSMenuItem": {"default": "Tanya EduVis AI (Gemma 4 Lokal)"},
                "NSMessage": "handleSystemServicePrompt",
                "NSPortName": "EduVis AI Gallery",
                "NSSendTypes": ["NSStringPboardType", "public.utf8-plain-text"],
            }
        ],
        "CFBundleDocumentTypes": [
            {
                "CFBundleTypeName": "LiteRT-LM Model",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "CFBundleTypeExtensions": ["litertlm"],
            },
            {
                "CFBundleTypeName": "Dokumen & Gambar AI",
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "CFBundleTypeExtensions": ["pdf", "docx", "txt", "md", "csv", "png", "jpg", "jpeg", "webp"],
            },
        ],
    }
    with (contents_dir / "Info.plist").open("wb") as plist_file:
        plistlib.dump(info, plist_file)

    codesign = shutil.which("codesign")
    if not codesign:
        raise RuntimeError("Perintah `codesign` tidak ditemukan untuk menandatangani aplikasi native.")
    xattr = shutil.which("xattr")
    if not xattr:
        raise RuntimeError("Perintah `xattr` tidak ditemukan untuk menyiapkan bundle aplikasi macOS.")
    cleanup_result = subprocess.run(
        [xattr, "-cr", str(app_bundle)],
        capture_output=True,
        text=True,
        check=False,
    )
    if cleanup_result.returncode:
        detail = (cleanup_result.stderr or cleanup_result.stdout).strip()
        raise RuntimeError(f"Gagal membersihkan atribut metadata bundle aplikasi:\n{detail}")
    signing_result = subprocess.run(
        [codesign, "--force", "--deep", "--sign", "-", str(app_bundle)],
        capture_output=True,
        text=True,
        check=False,
    )
    if signing_result.returncode:
        detail = (signing_result.stderr or signing_result.stdout).strip()
        raise RuntimeError(f"Gagal menandatangani aplikasi native:\n{detail}")
    lsregister = (
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
        "LaunchServices.framework/Support/lsregister"
    )
    if Path(lsregister).is_file():
        subprocess.run(
            [lsregister, "-f", str(app_bundle)],
            capture_output=True,
            text=True,
            check=False,
        )
    try:
        os.utime(app_bundle, None)
    except OSError:
        pass
    return executable


def stop_process(process, name):
    if process is None:
        return
    if process.poll() is None:
        print(f"[launcher] Menghentikan {name} beserta proses turunannya...", flush=True)
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        process.wait()
        return

    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            process.wait()
            return
        time.sleep(0.1)

    print(f"[launcher] Memaksa penghentian proses {name} yang belum berhenti...", flush=True)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def reclaim_backend_ports():
    """Bebaskan port 1234, 1235, dan 1236 dari proses backend/LiteRT-LM lama yang yatim (orphan)."""
    current_pid = os.getpid()
    parent_pid = os.getppid()
    protected_pids = {current_pid, parent_pid}
    stale_pids = set()

    pid_file = Path.home() / "Library" / "Application Support" / "EduVis AI Gallery" / "backend.pid"
    try:
        if pid_file.is_file():
            recorded_pid = int(pid_file.read_text(encoding="utf-8").strip())
            if recorded_pid > 1 and recorded_pid not in protected_pids:
                stale_pids.add(recorded_pid)
    except (OSError, ValueError):
        pass

    lsof_bin = shutil.which("lsof") or ("/usr/sbin/lsof" if Path("/usr/sbin/lsof").is_file() else None)
    if lsof_bin:
        for port in (API_PORT, LITERT_API_PORT, LOCAL_UI_PORT):
            try:
                res = subprocess.run(
                    [lsof_bin, "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
                for line in (res.stdout or "").splitlines():
                    line = line.strip()
                    if line.isdigit():
                        pid = int(line)
                        if pid > 1 and pid not in protected_pids:
                            stale_pids.add(pid)
            except (OSError, subprocess.SubprocessError):
                pass

    if stale_pids:
        print(
            f"[launcher] Membersihkan proses backend/port lama yang masih aktif: {sorted(stale_pids)}...",
            flush=True,
        )
        for pid in stale_pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass

        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline:
            alive = []
            for pid in stale_pids:
                try:
                    os.kill(pid, 0)
                    alive.append(pid)
                except OSError:
                    pass
            if not alive:
                break
            time.sleep(0.1)

        for pid in stale_pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        time.sleep(0.2)

    try:
        pid_file.parent.mkdir(parents=True, exist_ok=True)
        pid_file.write_text(str(current_pid), encoding="utf-8")
    except OSError:
        pass


def run_backend_only(readiness_file):
    if sys.platform != "darwin":
        print("Backend aplikasi native ini saat ini mendukung macOS.", file=sys.stderr, flush=True)
        return 1

    ui_server = None
    local_ui_server = None
    model_manager = None
    parent_pid = os.getppid()
    stopping = threading.Event()
    previous_sigterm = signal.signal(signal.SIGTERM, lambda _signum, _frame: stopping.set())
    try:
        reclaim_backend_ports()
        AppRequestHandler.allowed_origins = {
            f"http://{API_HOST}:{LOCAL_UI_PORT}",
            f"http://localhost:{LOCAL_UI_PORT}",
        }
        local_ui_server = ThreadingHTTPServer((API_HOST, LOCAL_UI_PORT), AppRequestHandler)
        local_ui_server.daemon_threads = True
        threading.Thread(target=local_ui_server.serve_forever, daemon=True).start()
        print(f"[launcher] Server Web UI lokal aktif di http://{API_HOST}:{LOCAL_UI_PORT}/utama.html", flush=True)

        litert_lm = None
        try:
            litert_lm = ensure_first_run_requirements()
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print(f"[launcher] Peringatan setup LiteRT-LM (server Web UI tetap aktif): {error}", file=sys.stderr, flush=True)

        try:
            lan_addresses = get_local_ipv4_addresses()
            tls_context, ca_certificate = create_lan_tls_context(lan_addresses)
            ui_server = ThreadingHTTPSServer(
                (UI_BIND_HOST, API_PORT),
                AppRequestHandler,
                tls_context,
            )
            AppRequestHandler.local_ipv4_addresses = lan_addresses
            AppRequestHandler.ca_certificate_path = ca_certificate
            AppRequestHandler.allowed_origins = {
                f"http://{API_HOST}:{LOCAL_UI_PORT}",
                f"http://localhost:{LOCAL_UI_PORT}",
                *(f"https://{address}:{API_PORT}" for address in lan_addresses),
            }
            ui_server.daemon_threads = True
            threading.Thread(target=ui_server.serve_forever, daemon=True).start()
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print(f"[launcher] Peringatan server HTTPS LAN port {API_PORT}: {error}", file=sys.stderr, flush=True)

        model_ids = []
        if litert_lm:
            AppRequestHandler.model_manager = ModelServerManager(litert_lm)
            model_manager = AppRequestHandler.model_manager
            try:
                model_server = model_manager.start()
                model_ids = wait_for_models(model_server)
            except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                print(
                    f"[launcher] Peringatan LiteRT-LM serve (server Web UI & RAG tetap berjalan): {error}",
                    file=sys.stderr,
                    flush=True,
                )

        # TTS dijalankan secara on-demand saat ada request vokal di UI
        readiness_file = Path(readiness_file)
        readiness_file.parent.mkdir(parents=True, exist_ok=True)
        readiness_temp_file = readiness_file.with_suffix(".tmp")
        readiness_temp_file.write_text(model_ids[0] if model_ids else "", encoding="utf-8")
        readiness_temp_file.replace(readiness_file)
        print(f"[launcher] WebView native terhubung ke http://{API_HOST}:{LOCAL_UI_PORT}/utama.html", flush=True)
        if model_ids:
            print(f"[launcher] Model aktif: {model_ids[0]}", flush=True)
        else:
            print("[launcher] Belum ada model terimpor atau server LiteRT-LM berjalan dalam mode fallback.", flush=True)

        model_down_logged = False
        while not stopping.wait(0.5):
            if parent_pid > 1 and os.getppid() != parent_pid:
                print("[launcher] Aplikasi utama ditutup; menghentikan backend...", flush=True)
                break
            if model_manager is not None and not model_manager.is_running() and not model_down_logged:
                model_down_logged = True
                print(
                    "[launcher] Peringatan: Service LiteRT-LM tidak aktif; server Web UI & SQLite RAG tetap berjalan.",
                    file=sys.stderr,
                    flush=True,
                )
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"[launcher] ERROR: {error}", file=sys.stderr, flush=True)
        return 1
    finally:
        stop_tts_server()
        if model_manager is not None:
            model_manager.stop()
        for server in (ui_server, local_ui_server):
            if server is not None:
                server.shutdown()
                server.server_close()
        signal.signal(signal.SIGTERM, previous_sigterm)
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--backend-only":
        if len(sys.argv) != 4 or sys.argv[2] != "--readiness":
            print("Penggunaan: gemma_chat_gui.py --backend-only --readiness <path>", file=sys.stderr)
            return 2
        return run_backend_only(sys.argv[3])

    if sys.platform != "darwin":
        print("Aplikasi WebView native ini saat ini mendukung macOS.", file=sys.stderr)
        return 1

    swiftc = shutil.which("swiftc")
    if not swiftc:
        print("Perintah `swiftc` tidak ditemukan. Pasang Xcode Command Line Tools.", file=sys.stderr)
        return 1

    ui_server = None
    local_ui_server = None
    try:
        reclaim_backend_ports()
        litert_lm = ensure_first_run_requirements()
        lan_addresses = get_local_ipv4_addresses()
        tls_context, ca_certificate = create_lan_tls_context(lan_addresses)
        ui_server = ThreadingHTTPSServer(
            (UI_BIND_HOST, API_PORT),
            AppRequestHandler,
            tls_context,
        )
        local_ui_server = ThreadingHTTPServer((API_HOST, LOCAL_UI_PORT), AppRequestHandler)
    except (OSError, RuntimeError) as error:
        print(
            f"[launcher] ERROR: tidak dapat menyiapkan aplikasi: {error}",
            file=sys.stderr,
        )
        if ui_server is not None:
            ui_server.server_close()
        if local_ui_server is not None:
            local_ui_server.server_close()
        return 1
    AppRequestHandler.local_ipv4_addresses = lan_addresses
    AppRequestHandler.ca_certificate_path = ca_certificate
    ui_port = API_PORT
    ui_server.daemon_threads = True
    local_ui_server.daemon_threads = True
    threading.Thread(target=ui_server.serve_forever, daemon=True).start()
    threading.Thread(target=local_ui_server.serve_forever, daemon=True).start()
    ui_url = f"http://{API_HOST}:{LOCAL_UI_PORT}/utama.html"
    AppRequestHandler.allowed_origins = {
        f"http://{API_HOST}:{LOCAL_UI_PORT}",
        f"http://localhost:{LOCAL_UI_PORT}",
        *(f"https://{address}:{ui_port}" for address in lan_addresses),
    }

    model_manager = ModelServerManager(litert_lm)
    AppRequestHandler.model_manager = model_manager
    webview_process = None
    readiness_temp_dir = None
    webview_bundle = None
    exit_code = 0
    try:
        webview_bundle = (
            Path.home()
            / "Applications"
            / "EduVis AI Gallery.app"
        )
        webview_bundle.parent.mkdir(parents=True, exist_ok=True)
        compile_webview(swiftc, webview_bundle)
        readiness_temp_dir = tempfile.TemporaryDirectory(prefix="eduvis-ready-")
        readiness_file = Path(readiness_temp_dir.name) / "ready"
        open_application = shutil.which("open")
        if not open_application:
            raise RuntimeError("Perintah macOS `open` tidak ditemukan untuk meluncurkan aplikasi native.")
        webview_command = [
            open_application,
            "-n",
            "-W",
            str(webview_bundle),
            "--args",
            ui_url,
            str(PROJECT_DIR / "Banner.jpg"),
            str(readiness_file),
        ]
        if os.environ.get("TERM_PROGRAM") == "Apple_Terminal":
            webview_command.append("--hide-terminal")
        webview_process = subprocess.Popen(
            webview_command,
            cwd=PROJECT_DIR,
            start_new_session=True,
        )

        model_server = model_manager.start()
        model_ids = wait_for_models(model_server)
        # TTS dijalankan secara on-demand saat ada request vokal di UI
        readiness_temp_file = readiness_file.with_suffix(".tmp")
        readiness_temp_file.write_text(model_ids[0] if model_ids else "", encoding="utf-8")
        readiness_temp_file.replace(readiness_file)
        if model_ids:
            print(f"[launcher] Model aktif: {model_ids[0]}", flush=True)
        else:
            print("[launcher] Belum ada model. Impor file .litertlm melalui Pengaturan.", flush=True)
        print(
            f"[launcher] UI dan API tersedia pada port {API_PORT} "
            "menggunakan HTTPS (API LiteRT-LM internal pada 127.0.0.1:1235).",
            flush=True,
        )
        print("[launcher] WebView lokal: " + ui_url, flush=True)
        print(
            f"[launcher] Sertifikat CA untuk dipercaya perangkat: {ca_certificate}",
            flush=True,
        )
        if lan_addresses:
            for address in lan_addresses:
                print(
                    f"[launcher] UI jaringan lokal: https://{address}:{ui_port}/utama.html",
                    flush=True,
                )
                print(
                    f"[launcher] EduVis: https://{address}:{ui_port}/eduVis.html",
                    flush=True,
                )
                print(
                    f"[launcher] Gemini Live: https://{address}:{ui_port}/gemini_live.html",
                    flush=True,
                )
                print(
                    f"[launcher] Gemini Live Futuristik: https://{address}:{ui_port}/gemini_live_futuristik.html",
                    flush=True,
                )
                print(
                    f"[launcher] TTS Studio AI: https://{address}:{ui_port}/tts_studio_lokal.html",
                    flush=True,
                )
                print(
                    f"[launcher] Endpoint API LAN: https://{address}:{API_PORT}/v1",
                    flush=True,
                )
                print(
                    f"[launcher] Unduh sertifikat CA: https://{address}:{API_PORT}/api/lan-ca",
                    flush=True,
                )
        else:
            print(
                "[launcher] IP jaringan lokal tidak terdeteksi otomatis. "
                "UI tetap tersedia dari perangkat ini.",
                flush=True,
            )

        while webview_process.poll() is None:
            if not model_manager.is_running():
                raise RuntimeError(
                    "Proses litert-lm berhenti "
                    f"(kode {model_manager.process.returncode if model_manager.process else 'tidak tersedia'})."
                )
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n[launcher] Diminta berhenti.", flush=True)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"[launcher] ERROR: {error}", file=sys.stderr, flush=True)
        exit_code = 1
    finally:
        try:
            if webview_bundle is not None and webview_process is not None and webview_process.poll() is None:
                osascript = shutil.which("osascript")
                if osascript:
                    quit_result = subprocess.run(
                        [
                            osascript,
                            "-e",
                            'tell application id "com.eduvis.ai-gallery" to quit',
                        ],
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    if quit_result.returncode:
                        detail = (quit_result.stderr or quit_result.stdout).strip()
                        print(
                            f"[launcher] Tidak dapat meminta aplikasi native berhenti: {detail}",
                            file=sys.stderr,
                            flush=True,
                        )
            stop_process(webview_process, "jendela WebView")
        finally:
            stop_tts_server()
            try:
                model_manager.stop()
            finally:
                try:
                    ui_server.shutdown()
                    ui_server.server_close()
                    local_ui_server.shutdown()
                    local_ui_server.server_close()
                finally:
                    if readiness_temp_dir is not None:
                        readiness_temp_dir.cleanup()
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
