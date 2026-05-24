#!/usr/bin/env python3
"""Aquila Language Server — minimal LSP implementation.

Provides diagnostics (errors) for .aquila files in any LSP-compatible editor.
Uses the Aquila compiler's --json flag for structured error output.
"""

import json
import sys
import subprocess
import os
import re

AQUILA_COMPILER = os.environ.get("AQUILA_COMPILER", "aquila")


def send_message(msg):
    """Send a JSON-RPC message to the client."""
    body = json.dumps(msg)
    header = f"Content-Length: {len(body)}\r\n\r\n"
    sys.stdout.write(header + body)
    sys.stdout.flush()


def read_message():
    """Read a JSON-RPC message from stdin."""
    headers = {}
    while True:
        line = sys.stdin.readline()
        if not line or line == "\r\n":
            break
        if ":" in line:
            key, val = line.split(":", 1)
            headers[key.strip()] = val.strip()
    length = int(headers.get("Content-Length", 0))
    if length == 0:
        return None
    body = sys.stdin.read(length)
    return json.loads(body)


def get_diagnostics(file_path):
    """Run the Aquila compiler and extract diagnostics."""
    diagnostics = []
    try:
        result = subprocess.run(
            [AQUILA_COMPILER, "--json", file_path],
            capture_output=True, text=True, timeout=10
        )
        # Parse compiler output for errors
        output = result.stdout + result.stderr
        for line in output.split("\n"):
            line = line.strip()
            if not line:
                continue
            # Try JSON format first
            if line.startswith("{"):
                try:
                    err = json.loads(line)
                    diag = {
                        "range": {
                            "start": {"line": err.get("line", 1) - 1, "character": err.get("col", 0)},
                            "end": {"line": err.get("line", 1) - 1, "character": err.get("col", 0) + 10}
                        },
                        "severity": 1,  # Error
                        "source": "aquila",
                        "message": err.get("error", "") + ": " + err.get("suggestion", "")
                    }
                    diagnostics.append(diag)
                    continue
                except json.JSONDecodeError:
                    pass
            # Fallback: parse "error: ..." format
            if line.startswith("error:"):
                diagnostics.append({
                    "range": {
                        "start": {"line": 0, "character": 0},
                        "end": {"line": 0, "character": 100}
                    },
                    "severity": 1,
                    "source": "aquila",
                    "message": line
                })
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        diagnostics.append({
            "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}},
            "severity": 1, "source": "aquila",
            "message": f"Aquila compiler error: {e}"
        })
    return diagnostics


def uri_to_path(uri):
    """Convert file:// URI to filesystem path."""
    if uri.startswith("file://"):
        return uri[7:]
    return uri


def main():
    while True:
        msg = read_message()
        if msg is None:
            break

        method = msg.get("method", "")
        msg_id = msg.get("id")
        params = msg.get("params", {})

        if method == "initialize":
            send_message({
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {
                    "capabilities": {
                        "textDocumentSync": 1,  # Full sync
                        "diagnosticProvider": {"interFileDependencies": False, "workspaceDiagnostics": False}
                    },
                    "serverInfo": {"name": "aquila-lsp", "version": "0.1.0"}
                }
            })

        elif method == "initialized":
            pass  # No action needed

        elif method == "textDocument/didOpen" or method == "textDocument/didSave":
            uri = params.get("textDocument", {}).get("uri", "")
            file_path = uri_to_path(uri)
            diagnostics = get_diagnostics(file_path)
            send_message({
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": {
                    "uri": uri,
                    "diagnostics": diagnostics
                }
            })

        elif method == "textDocument/didChange":
            # On change, re-run diagnostics
            uri = params.get("textDocument", {}).get("uri", "")
            file_path = uri_to_path(uri)
            diagnostics = get_diagnostics(file_path)
            send_message({
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": {
                    "uri": uri,
                    "diagnostics": diagnostics
                }
            })

        elif method == "shutdown":
            send_message({"jsonrpc": "2.0", "id": msg_id, "result": None})

        elif method == "exit":
            break

        elif msg_id is not None:
            # Unknown request — respond with null
            send_message({"jsonrpc": "2.0", "id": msg_id, "result": None})


if __name__ == "__main__":
    main()
