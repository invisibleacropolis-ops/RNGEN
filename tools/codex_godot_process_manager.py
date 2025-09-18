"""Process management helpers for Codex driven Godot sessions.

This module exposes :class:`CodexGodotProcessManager`, a small orchestration
utility that wraps :class:`subprocess.Popen` with sensible defaults for the
Codex automation workflows described in the "Python Godot Automation Design
Bible".  The class is intentionally light-weight – it focuses on starting a
headless Godot instance, ensuring JSON-RPC style communication via
line-delimited messages, and surfacing diagnostics that are useful when the
engine misbehaves.

The behaviour of the process manager can be tweaked via a small set of
environment variables:

``CODEX_GODOT_BIN``
    Absolute path to the Godot executable that should be launched when a new
    session is created.
``CODEX_PROJECT_ROOT``
    Filesystem path that will be passed to the ``--path`` flag when starting
    Godot.  This must contain the ``project.godot`` manifest.

These defaults can be overridden programmatically when instantiating
:class:`CodexGodotProcessManager` which keeps the API flexible for local
experimenters and automated Codex operators alike.
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Dict, Generator, Iterable, List, Optional


@dataclass
class SessionDescription:
    """Describes an active Codex managed Godot session."""

    session_id: str
    pid: Optional[int]
    command: List[str]
    project_root: str
    banner: Optional[dict] = None
    heartbeat_interval: Optional[float] = None
    heartbeat_timeout: Optional[float] = None


class CodexGodotProcessManager:
    """Manage the lifecycle of a headless Godot process for Codex automation.

    Parameters
    ----------
    godot_binary:
        Path to the Godot executable.  Defaults to the ``CODEX_GODOT_BIN``
        environment variable.
    project_root:
        Path to the Godot project that will be supplied via ``--path``.
        Defaults to the ``CODEX_PROJECT_ROOT`` environment variable.
    extra_args:
        Additional command line arguments forwarded to Godot.
    env_overrides:
        Optional environment overrides that are merged with the inherited
        environment.
    heartbeat_interval:
        Optional number of seconds between heartbeat checks.  When provided a
        lightweight monitor thread will emit timeout diagnostics whenever no
        stdout message is observed for longer than ``heartbeat_timeout``.
    heartbeat_timeout:
        Number of seconds to tolerate without receiving a message before a
        heartbeat diagnostic is published.  When omitted it defaults to
        ``heartbeat_interval`` if that is set.
    banner_timeout:
        Maximum number of seconds to wait for the banner response that is
        negotiated automatically when the session starts.
    """

    #: Method invoked automatically to negotiate a banner for Codex sessions.
    _BANNER_METHOD = "codex.banner"

    def __init__(
        self,
        *,
        godot_binary: Optional[str] = None,
        project_root: Optional[str] = None,
        extra_args: Optional[Iterable[str]] = None,
        env_overrides: Optional[Dict[str, str]] = None,
        heartbeat_interval: Optional[float] = None,
        heartbeat_timeout: Optional[float] = None,
        banner_timeout: float = 5.0,
    ) -> None:
        self.godot_binary = godot_binary or os.environ.get("CODEX_GODOT_BIN")
        self.project_root = project_root or os.environ.get("CODEX_PROJECT_ROOT")
        if not self.godot_binary:
            raise ValueError(
                "Godot binary not provided. Set CODEX_GODOT_BIN or pass godot_binary."
            )
        if not self.project_root:
            raise ValueError(
                "Project root not provided. Set CODEX_PROJECT_ROOT or pass project_root."
            )

        self.extra_args = list(extra_args or [])
        self.env_overrides = dict(env_overrides or {})
        self.heartbeat_interval = heartbeat_interval
        self.heartbeat_timeout = (
            heartbeat_timeout if heartbeat_timeout is not None else heartbeat_interval
        )
        self.banner_timeout = banner_timeout

        self._process: Optional[subprocess.Popen[str]] = None
        self._stdout_thread: Optional[threading.Thread] = None
        self._stderr_thread: Optional[threading.Thread] = None
        self._heartbeat_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
        self._stdout_queue: "queue.Queue[str | None]" = queue.Queue()
        self._stderr_queue: "queue.Queue[dict | None]" = queue.Queue()
        self._id_counter = 1
        self._banner_request_id: Optional[int] = None
        self._banner: Optional[dict] = None
        self._session_id = str(uuid.uuid4())
        self._last_activity = time.monotonic()

    # ------------------------------------------------------------------
    # Context manager support
    def __enter__(self) -> "CodexGodotProcessManager":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.stop()

    # ------------------------------------------------------------------
    # Public API
    @property
    def is_running(self) -> bool:
        return bool(self._process and self._process.poll() is None)

    def start(self) -> None:
        """Start the Godot process and associated reader threads."""

        if self.is_running:
            return

        env = os.environ.copy()
        env.update(self.env_overrides)

        command = [
            self.godot_binary,
            "--headless",
            "--path",
            self.project_root,
        ] + self.extra_args

        self._process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            env=env,
        )

        assert self._process.stdout is not None  # for type-checkers
        assert self._process.stderr is not None
        assert self._process.stdin is not None

        self._stop_event.clear()
        self._stdout_thread = threading.Thread(
            target=self._reader_thread,
            args=(self._process.stdout, self._stdout_queue, "stdout"),
            daemon=True,
        )
        self._stderr_thread = threading.Thread(
            target=self._reader_thread,
            args=(self._process.stderr, self._stderr_queue, "stderr"),
            daemon=True,
        )
        self._stdout_thread.start()
        self._stderr_thread.start()

        self._banner_request_id = self.send_command(
            self._BANNER_METHOD,
            {
                "client": "codex",
                "session": self._session_id,
                "protocol": "json-rpc",
            },
            id_override=0,
        )

        if self.heartbeat_interval:
            self._heartbeat_thread = threading.Thread(
                target=self._heartbeat_monitor,
                name="CodexGodotHeartbeat",
                daemon=True,
            )
            self._heartbeat_thread.start()

    def stop(self) -> None:
        """Terminate the Godot process and wait for reader threads to exit."""

        self._stop_event.set()
        if not self._process:
            return

        if self._process.stdin and not self._process.stdin.closed:
            try:
                self._process.stdin.flush()
                self._process.stdin.close()
            except Exception:
                pass

        if self.is_running:
            try:
                self._process.terminate()
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait(timeout=5)

        if self._stdout_thread and self._stdout_thread.is_alive():
            self._stdout_thread.join(timeout=1)
        if self._stderr_thread and self._stderr_thread.is_alive():
            self._stderr_thread.join(timeout=1)
        if self._heartbeat_thread and self._heartbeat_thread.is_alive():
            self._heartbeat_thread.join(timeout=1)

        self._process = None

    def describe_session(self) -> SessionDescription:
        """Return a snapshot of the currently running session."""

        command: List[str] = [
            self.godot_binary,
            "--headless",
            "--path",
            self.project_root,
        ] + self.extra_args
        pid = self._process.pid if self._process else None
        return SessionDescription(
            session_id=self._session_id,
            pid=pid,
            command=command,
            project_root=self.project_root,
            banner=self._banner,
            heartbeat_interval=self.heartbeat_interval,
            heartbeat_timeout=self.heartbeat_timeout,
        )

    # Communication helpers -------------------------------------------------
    def send_command(
        self,
        method: str,
        params: Optional[dict] = None,
        *,
        id_override: Optional[int] = None,
    ) -> int:
        """Send a JSON-RPC style command to the running Godot process."""

        if not self.is_running or not self._process or not self._process.stdin:
            raise RuntimeError("Godot process is not running.")

        request_id = id_override if id_override is not None else self._id_counter
        self._id_counter = max(self._id_counter, request_id + 1)

        payload = {
            "id": request_id,
            "method": method,
            "params": params or {},
        }
        message = json.dumps(payload, separators=(",", ":")) + "\n"
        try:
            self._process.stdin.write(message)
            self._process.stdin.flush()
        except (BrokenPipeError, ValueError) as error:  # pragma: no cover - I/O failure
            raise RuntimeError("Failed to send command to Godot process") from error

        return request_id

    def iter_messages(
        self,
        *,
        timeout: Optional[float] = None,
    ) -> Generator[dict, None, None]:
        """Yield parsed JSON messages produced by the Godot process.

        The iterator consumes responses from the stdout queue.  It silently
        handles the banner response that is negotiated automatically during
        :meth:`start`.  Non-JSON lines are treated as diagnostics and will be
        surfaced via :meth:`iter_stderr_diagnostics` with structured metadata.
        """

        if not self.is_running:
            raise RuntimeError("Godot process is not running.")

        while True:
            try:
                line = self._stdout_queue.get(timeout=timeout)
            except queue.Empty:
                self._maybe_emit_heartbeat_timeout()
                continue

            if line is None:
                break

            stripped = line.strip()
            if not stripped:
                continue

            try:
                message = json.loads(stripped)
            except json.JSONDecodeError:
                self._stderr_queue.put(
                    {
                        "timestamp": time.time(),
                        "stream": "stdout",
                        "text": stripped,
                        "level": "protocol",
                    }
                )
                continue

            self._last_activity = time.monotonic()

            if self._banner_request_id is not None and message.get("id") == self._banner_request_id:
                banner_payload = message.get("result")
                if isinstance(banner_payload, dict):
                    self._banner = banner_payload
                else:
                    self._banner = {"message": banner_payload}
                self._banner_request_id = None
                continue

            yield message

    def iter_stderr_diagnostics(self) -> Generator[dict, None, None]:
        """Yield structured diagnostics that originated from stderr or decoding errors."""

        while True:
            try:
                payload = self._stderr_queue.get(timeout=0.1)
            except queue.Empty:
                if not self.is_running and self._stderr_queue.empty():
                    return
                if self._stop_event.is_set():
                    return
                continue

            if payload is None:
                if not self.is_running and self._stderr_queue.empty():
                    return
                continue
            yield payload

    # ------------------------------------------------------------------
    # Internal helpers
    def _reader_thread(self, pipe, sink: "queue.Queue", source: str) -> None:
        try:
            for raw_line in iter(pipe.readline, ""):
                if self._stop_event.is_set():
                    break
                if source == "stdout":
                    sink.put(raw_line.rstrip("\n"))
                else:
                    sink.put(
                        {
                            "timestamp": time.time(),
                            "stream": source,
                            "text": raw_line.rstrip("\n"),
                            "level": "error",
                        }
                    )
        finally:
            sink.put(None)
            pipe.close()

    def _heartbeat_monitor(self) -> None:
        assert self.heartbeat_interval is not None
        while not self._stop_event.wait(self.heartbeat_interval):
            if not self.is_running:
                break
            self._maybe_emit_heartbeat_timeout()

    def _maybe_emit_heartbeat_timeout(self) -> None:
        if not self.heartbeat_timeout:
            return
        elapsed = time.monotonic() - self._last_activity
        if elapsed < self.heartbeat_timeout:
            return
        diagnostic = {
            "timestamp": time.time(),
            "stream": "heartbeat",
            "text": f"No stdout messages for {elapsed:.2f}s",
            "level": "warning",
            "session": self._session_id,
        }
        self._stderr_queue.put(diagnostic)
        self._last_activity = time.monotonic()


__all__ = ["CodexGodotProcessManager", "SessionDescription"]
