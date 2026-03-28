#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PC 端 AI 聊天桥接服务：与 Android 端使用相同协议（TCP，每行一条 JSON，对应 SocketMessage）。

用法简述：
  1. 本机安装并启动 Ollama： https://ollama.com  执行 `ollama serve`，并 `ollama pull llama3.2`（或其它模型）
  2. 可通过环境变量配置（推荐）：
     AIIM_HOST=0.0.0.0
     AIIM_PORT=8080
     AIIM_BACKEND=ollama
     AIIM_OLLAMA_URL=http://127.0.0.1:11434
     AIIM_OLLAMA_MODEL=llama3.2
     AIIM_OPENAI_BASE_URL=http://127.0.0.1:1234
     AIIM_OPENAI_MODEL=local-model
  3. 运行： python server.py
  4. 手机与电脑同一局域网，App 点「连接服务器」，IP 填电脑的局域网地址（与 WiFi 详情里 IPv4 一致），端口 8080

说明：当前 Android 端一次只维持一条 TCP 连接，因此该服务适合「手机 <---> 电脑上的 AI」单会话；
若还要两人对聊，需要再在架构上加房间/多连接（可后续扩展）。
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any


def env_or_default(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value is not None and value != "" else default


def env_or_default_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError:
        print(f"[!] 环境变量 {name}={value!r} 不是合法整数，回退到默认值 {default}")
        return default


def load_dotenv_file(path: Path) -> None:
    if not path.exists():
        return
    try:
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if not key:
                continue
            # 保留外部已存在的环境变量，.env 仅作为默认值来源
            os.environ.setdefault(key, value)
    except OSError as e:
        print(f"[!] 读取 .env 失败: {e}")


def build_socket_message(
    content: str,
    sender: str,
    message_type: str = "text",
) -> dict[str, Any]:
    return {
        "id": str(uuid.uuid4()),
        "content": content,
        "sender": sender,
        "timestamp": int(time.time() * 1000),
        "status": "sent",
        "is_sent_by_me": False,
        "message_type": message_type,
    }


def _post_json(url: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def _http_error_detail(e: urllib.error.HTTPError) -> str:
    raw = e.read().decode("utf-8", errors="replace")
    try:
        j = json.loads(raw)
        return str(j.get("error", raw))
    except json.JSONDecodeError:
        return raw or str(e)


def ollama_complete(
    base_url: str, model: str, system: str, user_text: str, timeout: int
) -> str:
    """
    调用 Ollama：优先 /api/chat（新版推荐），失败再试 /api/generate。
    404 多为「模型名不对或未 ollama pull」。
    """
    base = base_url.rstrip("/")
    errors: list[str] = []

    try:
        body = _post_json(
            f"{base}/api/chat",
            {
                "model": model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user_text},
                ],
                "stream": False,
            },
            timeout,
        )
        text = (body.get("message") or {}).get("content", "")
        if text.strip():
            return text.strip()
        errors.append("/api/chat 返回空内容")
    except urllib.error.HTTPError as e:
        errors.append(f"/api/chat HTTP {e.code}: {_http_error_detail(e)}")
    except urllib.error.URLError as e:
        errors.append(f"/api/chat 网络错误: {e}")

    full_prompt = f"{system}\n\n用户消息:\n{user_text}\n\n请用简短中文直接回复。"
    try:
        body = _post_json(
            f"{base}/api/generate",
            {"model": model, "prompt": full_prompt, "stream": False},
            timeout,
        )
        text = (body.get("response") or "").strip()
        if text:
            return text
        errors.append("/api/generate 返回空内容")
    except urllib.error.HTTPError as e:
        errors.append(f"/api/generate HTTP {e.code}: {_http_error_detail(e)}")
    except urllib.error.URLError as e:
        errors.append(f"/api/generate 网络错误: {e}")

    hint = (
        " 本机执行 ollama list 查看准确模型名，启动脚本加 --ollama-model 该名称；"
        "若没有模型：ollama pull llama3.2（或 qwen2.5 等）"
    )
    raise RuntimeError(" | ".join(errors) + hint)


def openai_compatible_chat(
    base_url: str, model: str, system: str, user_text: str, timeout: int
) -> str:
    """OpenAI 兼容接口（LM Studio、vLLM、部分本地网关等）：POST /v1/chat/completions"""
    url = base_url.rstrip("/") + "/v1/chat/completions"
    payload = json.dumps(
        {
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user_text},
            ],
            "temperature": 0.7,
            "stream": False,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.load(resp)
    choices = body.get("choices") or []
    if not choices:
        return ""
    msg = choices[0].get("message") or {}
    return (msg.get("content") or "").strip()


class ClientHandler(threading.Thread):
    def __init__(
        self,
        conn: socket.socket,
        addr: tuple,
        bot_name: str,
        system_prompt: str,
        backend: str,
        ollama_url: str,
        ollama_model: str,
        openai_base_url: str,
        openai_model: str,
        llm_timeout: int,
    ) -> None:
        super().__init__(daemon=True)
        self.conn = conn
        self.addr = addr
        self.bot_name = bot_name
        self.system_prompt = system_prompt
        self.backend = backend
        self.ollama_url = ollama_url
        self.ollama_model = ollama_model
        self.openai_base_url = openai_base_url
        self.openai_model = openai_model
        self.llm_timeout = llm_timeout
        self._send_lock = threading.Lock()

    def send_line(self, obj: dict[str, Any]) -> None:
        line = json.dumps(obj, ensure_ascii=False) + "\n"
        data = line.encode("utf-8")
        with self._send_lock:
            self.conn.sendall(data)

    def run(self) -> None:
        print(f"[+] 客户端已连接: {self.addr}")
        try:
            try:
                self.conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except OSError:
                pass
            self.conn.settimeout(300.0)
            buf = b""
            while True:
                chunk = self.conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not line.strip():
                        continue
                    self._handle_line(line.decode("utf-8", errors="replace"))
        except (ConnectionResetError, BrokenPipeError, OSError) as e:
            print(f"[!] 连接异常: {e}")
        finally:
            try:
                self.conn.close()
            except OSError:
                pass
            print(f"[-] 客户端断开: {self.addr}")

    def _handle_line(self, line: str) -> None:
        try:
            msg: dict[str, Any] = json.loads(line)
        except json.JSONDecodeError:
            print(f"[!] 非 JSON 行，已忽略: {line[:120]}...")
            return

        # 兼容 Flutter 版协议（JSON 行）：
        # {"type":"message","payload":{"id":"...","text":"..."}}
        if "type" in msg and "payload" in msg:
            wtype = str(msg.get("type", "")).strip()
            payload = msg.get("payload") or {}
            if wtype == "heartbeat":
                return
            if wtype != "message":
                return
            text = str(payload.get("text", "")).strip()
            mid = payload.get("id")
            if not text:
                return

            print(f"[<-] Flutter 消息: {text[:200]!r} | 后端={self.backend!r}", flush=True)

            try:
                if self.backend == "mock":
                    reply = f"（mock）收到：{text}"
                elif self.backend == "openai":
                    reply = openai_compatible_chat(
                        self.openai_base_url,
                        self.openai_model,
                        self.system_prompt,
                        text,
                        self.llm_timeout,
                    )
                else:
                    reply = ollama_complete(
                        self.ollama_url,
                        self.ollama_model,
                        self.system_prompt,
                        text,
                        self.llm_timeout,
                    )
            except urllib.error.URLError as e:
                reply = f"[AI 调用失败] {e}"
            except RuntimeError as e:
                reply = f"[AI 调用失败] {e}"
            except Exception as e:  # noqa: BLE001
                reply = f"[AI 错误] {e}"

            if not reply:
                reply = "（模型未返回内容）"

            out_id = f"{mid}_ai" if isinstance(mid, str) and mid else str(uuid.uuid4())
            self.send_line({"type": "message", "payload": {"id": out_id, "text": reply}})
            print(f"[->] 已回复手机（Flutter 协议）: {reply[:120]!r}...", flush=True)
            return

        mtype = msg.get("message_type", "")
        if mtype == "heartbeat":
            return
        if mtype == "system":
            return
        if mtype != "text" and mtype:
            return

        sender = str(msg.get("sender", "")).strip()
        content = str(msg.get("content", "")).strip()
        if not content:
            return
        if sender == self.bot_name:
            return

        user_line = f"{sender}: {content}"
        user_for_model = (
            f"用户发来一条聊天消息:\n{user_line}\n\n"
            "请用简短、友好的中文直接回复，不要重复昵称前缀。"
        )

        try:
            if self.backend == "openai":
                reply = openai_compatible_chat(
                    self.openai_base_url,
                    self.openai_model,
                    self.system_prompt,
                    user_line,
                    self.llm_timeout,
                )
            else:
                reply = ollama_complete(
                    self.ollama_url,
                    self.ollama_model,
                    self.system_prompt,
                    user_for_model,
                    self.llm_timeout,
                )
        except urllib.error.URLError as e:
            reply = f"[AI 调用失败] {e}"
        except RuntimeError as e:
            reply = f"[AI 调用失败] {e}"
        except Exception as e:  # noqa: BLE001
            reply = f"[AI 错误] {e}"

        if not reply:
            reply = "（模型未返回内容）"

        out = build_socket_message(reply, self.bot_name, "text")
        self.send_line(out)
        print(f"[bot] -> {reply[:80]}...")


def main() -> None:
    load_dotenv_file(Path(__file__).resolve().parent / ".env")
    p = argparse.ArgumentParser(description="PC AI 聊天桥接（兼容本 Android 项目 Socket 协议）")
    p.add_argument(
        "--host",
        default=env_or_default("AIIM_HOST", "0.0.0.0"),
        help="监听地址（env: AIIM_HOST）",
    )
    p.add_argument(
        "--port",
        type=int,
        default=env_or_default_int("AIIM_PORT", 8080),
        help="端口（env: AIIM_PORT；与 App Constants.SOCKET_PORT 一致）",
    )
    p.add_argument(
        "--bot-name",
        default=env_or_default("AIIM_BOT_NAME", "AI助手"),
        help="机器人显示昵称（env: AIIM_BOT_NAME；勿与用户昵称重复）",
    )
    p.add_argument(
        "--system",
        default=env_or_default(
            "AIIM_SYSTEM_PROMPT",
            "你是一个简洁、有帮助的中文聊天助手，在局域网聊天室里与用户对话。",
        ),
        help="系统提示（env: AIIM_SYSTEM_PROMPT；给模型的指令）",
    )
    p.add_argument(
        "--backend",
        choices=("ollama", "openai", "mock"),
        default=env_or_default("AIIM_BACKEND", "ollama"),
        help="ollama: 本机 Ollama；openai: OpenAI 兼容；mock: 回显（env: AIIM_BACKEND）",
    )
    p.add_argument(
        "--ollama-url",
        default=env_or_default("AIIM_OLLAMA_URL", "http://127.0.0.1:11434"),
        help="Ollama 根地址（env: AIIM_OLLAMA_URL）",
    )
    p.add_argument(
        "--ollama-model",
        default=env_or_default("AIIM_OLLAMA_MODEL", "llama3.2"),
        help="与 ollama list 中 NAME 一致（env: AIIM_OLLAMA_MODEL），例如 llama3.2、qwen2.5:latest",
    )
    p.add_argument(
        "--openai-base-url",
        default=env_or_default("AIIM_OPENAI_BASE_URL", "http://127.0.0.1:1234"),
        help="OpenAI 兼容服务根地址（env: AIIM_OPENAI_BASE_URL，如 LM Studio）",
    )
    p.add_argument(
        "--openai-model",
        default=env_or_default("AIIM_OPENAI_MODEL", "local-model"),
        help="OpenAI 兼容接口里的 model 字段（env: AIIM_OPENAI_MODEL）",
    )
    p.add_argument(
        "--llm-timeout",
        type=int,
        default=env_or_default_int("AIIM_LLM_TIMEOUT", 120),
        help="单次生成超时（秒，env: AIIM_LLM_TIMEOUT）",
    )
    args = p.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(4)
    print(
        f"[*] 监听 tcp://{args.host}:{args.port} | 后端={args.backend} | 机器人昵称={args.bot_name!r}"
    )
    print(f"[*] Ollama 模型: {args.ollama_model!r}（须与 ollama list 一致，否则易 HTTP 404）")
    print("[*] 用手机 App「连接服务器」填入本机局域网 IP 与此端口。")

    try:
        while True:
            conn, addr = srv.accept()
            handler = ClientHandler(
                conn,
                addr,
                bot_name=args.bot_name,
                system_prompt=args.system,
                backend=args.backend,
                ollama_url=args.ollama_url,
                ollama_model=args.ollama_model,
                openai_base_url=args.openai_base_url,
                openai_model=args.openai_model,
                llm_timeout=args.llm_timeout,
            )
            handler.start()
    except KeyboardInterrupt:
        print("\n[*] 退出")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
