#!/usr/bin/env python3
"""Quick MCP stdio client test — line-delimited JSON."""

import json
import subprocess
import sys
import time


def main():
    proc = subprocess.Popen(
        [sys.executable, "mcp_server.py"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )

    def _send(msg: dict) -> None:
        data = json.dumps(msg)
        proc.stdin.write((data + "\n").encode())
        proc.stdin.flush()

    def _recv() -> dict:
        line = proc.stdout.readline()
        return json.loads(line.decode())

    # Initialize
    init_req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test-client", "version": "1.0.0"},
        },
    }
    _send(init_req)
    resp = _recv()
    print("INIT:", json.dumps(resp, indent=2))

    # Initialized notification
    _send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    # List tools
    list_req = {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
    _send(list_req)
    resp = _recv()
    print("TOOLS:", json.dumps(resp, indent=2))

    # Call search_google
    call_req = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "search_google",
            "arguments": {"query": "python programming", "limit": 2},
        },
    }
    _send(call_req)
    resp = _recv()
    print("CALL:", json.dumps(resp, indent=2))

    proc.terminate()
    proc.wait()


if __name__ == "__main__":
    main()
