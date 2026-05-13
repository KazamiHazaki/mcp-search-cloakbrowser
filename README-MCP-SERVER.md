# CloakBrowser MCP Google Search Server

An MCP (Model Context Protocol) server that uses **CloakBrowser** — a stealth Chromium binary with C++-level fingerprint patches — to search Google headlessly and return structured, LLM-readable results.

## Features

- **Stealth by default**: Uses CloakBrowser's patched Chromium binary — passes bot detection
- **MCP Protocol**: Exposes `search_google` tool for any MCP-compatible client (Claude Desktop, Cursor, etc.)
- **HTTP Fallback**: `GET /search?query=...&limit=N` at `localhost:8000` for direct API access
- **Structured output**: Every result has `title`, `url`, `snippet`
- **Customizable limit**: Request 1–20 results (default 5)
- **Consent handling**: Auto-accepts Google cookie banners
- **Error resilience**: Graceful handling of CAPTCHA/block pages and browser crashes

## Quick Start

### 1. Setup environment (Python 3.11+ recommended)

```bash
# Using uv (recommended)
uv venv --python 3.11 .venv
source .venv/bin/activate
uv pip install -r requirements.txt

# Or using pip
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Run the server

**HTTP mode** (for curl/browser access):
```bash
python mcp_server.py --http
# Server runs at http://localhost:8000
```

**MCP stdio mode** (for MCP clients):
```bash
python mcp_server.py
# Communicates via JSON-RPC over stdin/stdout
```

**MCP + HTTP SSE mode** (both protocols on one port):
```bash
python mcp_server.py --sse
# HTTP search: http://localhost:8000/search
# MCP SSE:     http://localhost:8000/sse
```

### 3. Search via HTTP

```bash
curl "http://localhost:8000/search?query=cuaca+hari+ini&limit=3"
```

Response:
```json
{
  "results": [
    {
      "title": "Prakiraan Cuaca Kota Cilegon",
      "url": "https://www.bmkg.go.id/cuaca/prakiraan-cuaca/36.72",
      "snippet": "Prakiraan Cuaca Kota Cilegon ·Cerah. 25–25 °C ..."
    },
    ...
  ]
}
```

### 4. Use as MCP Tool

Add to your MCP client config (e.g., Claude Desktop `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "google-search": {
      "command": "/absolute/path/to/.venv/bin/python",
      "args": ["/absolute/path/to/mcp_server.py"]
    }
  }
}
```

The tool `search_google` will be available with schema:
- `query` (string, required): Search query
- `limit` (integer, optional, default 5): Number of results (1-20)

## Files

| File | Purpose |
|------|---------|
| `mcp_server.py` | MCP server + FastAPI HTTP fallback |
| `google_searcher.py` | CloakBrowser automation & SERP parsing |
| `requirements.txt` | Python dependencies |

## Architecture

```
User / LLM Client
    │
    ├─► MCP stdio/jsonrpc ──► mcp_server.py ──► google_searcher.py ──► CloakBrowser ──► Google
    │
    └─► HTTP GET /search ───► mcp_server.py ──► google_searcher.py ──► CloakBrowser ──► Google
```

## Notes

- **First run** downloads the CloakBrowser stealth Chromium binary (~140 MB) automatically
- **Rate limits**: Google may block rapid repeated searches. Add delays between requests in production
- **Proxy support**: Pass proxy settings via CloakBrowser's built-in proxy args (see `google_searcher.py`)
