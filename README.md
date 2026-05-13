# 🔍 CloakBrowser MCP Search & Scrape Server

An **[MCP (Model Context Protocol)](https://modelcontextprotocol.io)** server powered by **[CloakBrowser](https://github.com/CloakHQ/cloakbrowser)** — a stealth Chromium binary with **57 C++-level fingerprint patches** that passes every bot detection test.

> **For LLMs:** This server gives AI agents the ability to **search Google** and **scrape any webpage** into clean markdown, all through a stealth browser that appears 100% human to anti-bot systems.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🕵️ **Stealth Search** | Search Google via C++-patched Chromium — passes reCAPTCHA v3, Cloudflare, DataDome |
| 📄 **Page Scraper** | Scrape any URL into clean, LLM-readable markdown with automatic main-content extraction |
| 💾 **Smart Cache** | Scraped pages cached for **24 hours** — repeated requests are instant |
| 🔌 **MCP Protocol** | Native MCP stdio + SSE transport for Claude Desktop, Cursor, and any MCP client |
| 🌐 **HTTP API** | REST endpoints at `localhost:8000` for curl, scripts, and custom integrations |
| 🖥️ **Headless** | Zero GUI — runs entirely in background |
| 🌍 **Cross-Platform** | macOS (Intel/Apple Silicon), Linux (x64/ARM64), Windows (WSL/Git Bash) |

---

## 🚀 Quick Install (One-Liner)

```bash
# Clone this repo first, then run:
./install.sh

# Or download & run directly:
curl -fsSL https://raw.githubusercontent.com/KazamiHazaki/mcp-search-cloakbrowser/refs/heads/main/install.sh | bash
```

This will:
1. ✅ Detect your OS & architecture
2. ✅ Find or install Python 3.11+
3. ✅ Install `uv` (fast package manager) or fall back to `pip`
4. ✅ Create a virtual environment
5. ✅ Install all Python dependencies
6. ✅ Download the CloakBrowser stealth Chromium binary (~140 MB)
7. ✅ Fix macOS Gatekeeper if needed
8. ✅ Create wrapper scripts

### Requirements

- **Python 3.11+** (3.9 works for HTTP only; MCP SDK requires 3.11+)
- **~500 MB disk space** (venv + binary)
- **Internet connection** (for binary download)

---

## 📦 Manual Install

```bash
# 1. Clone
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO

# 2. Create virtual env (Python 3.11+)
python3.11 -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Download CloakBrowser binary
python -m cloakbrowser install

# 5. (macOS only) Fix Gatekeeper
xattr -cr ~/.cloakbrowser/chromium-*/Chromium.app
```

---

## 🎮 Usage

### Mode 1: HTTP Server (Simplest)

```bash
source .venv/bin/activate
python mcp_server.py --http
```

Then use `curl`:

```bash
# Search Google
curl "http://localhost:8000/search?query=machine+learning&limit=3"

# Scrape a page
curl "http://localhost:8000/scrape?url=https://python.org"

# Check cache
curl "http://localhost:8000/cache"

# Health check
curl "http://localhost:8000/health"
```

### Mode 2: MCP stdio (Claude Desktop, Cursor, etc.)

```bash
source .venv/bin/activate
python mcp_server.py
```

Add to your MCP client config:

**macOS Claude Desktop:**
```json
{
  "mcpServers": {
    "cloak-search": {
      "command": "/absolute/path/to/.venv/bin/python",
      "args": ["/absolute/path/to/mcp_server.py"]
    }
  }
}
```

Config file location:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

Restart Claude Desktop after editing. You'll see the 🔌 icon with 3 tools.

### Mode 3: HTTP + MCP SSE (Both Protocols)

```bash
source .venv/bin/activate
python mcp_server.py --sse
```

- **HTTP Search**: `http://localhost:8000/search`
- **HTTP Scrape**: `http://localhost:8000/scrape`
- **MCP SSE**: `http://localhost:8000/sse`

---

## 🛠️ MCP Tools

Once connected to an MCP client, the LLM gets access to these tools:

### `search_google`

Search Google and get structured results.

**Parameters:**
| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `query` | string | ✅ | — | Search query |
| `limit` | integer | ❌ | 5 | Max results (1–20) |

**Returns:**
```json
{
  "results": [
    {
      "title": "Welcome to Python.org",
      "url": "https://www.python.org/",
      "snippet": "The official home of the Python Programming Language.",
      "date": "2024-01-15"
    }
  ]
}
```

**Example prompt to LLM:**
> "Search Google for 'latest rust features 2025' and give me the top 3 results"

### `scrape_page`

Scrape any webpage into clean markdown.

**Parameters:**
| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `url` | string | ✅ | — | Full URL to scrape |
| `use_cache` | boolean | ❌ | `true` | Use cached result if available |

**Returns:**
```json
{
  "url": "https://www.python.org",
  "title": "Welcome to Python.org",
  "markdown": "# Welcome to Python.org\n\n## Get Started...",
  "cached": false,
  "word_count": 349,
  "char_count": 4243
}
```

**Example prompt to LLM:**
> "Read the content of https://docs.python.org/3/whatsnew/3.12.html and summarize the key changes"

### `cache_status`

Show which pages are currently cached.

**Returns:**
```json
{
  "cached_urls": ["https://python.org", "https://example.com"],
  "active_count": 2,
  "ttl_hours": 24.0
}
```

---

## 📡 HTTP API Reference

### `GET /search`

Search Google.

```bash
curl "http://localhost:8000/search?query=ai+news&limit=5"
```

**Query params:**
- `query` (string, required): Search term
- `limit` (integer, default 5): Results to return (1–20)

### `GET /scrape`

Scrape a webpage.

```bash
curl "http://localhost:8000/scrape?url=https://news.ycombinator.com"
```

**Query params:**
- `url` (string, required): URL to scrape
- `use_cache` (boolean, default `true`): Return cached if available

### `GET /cache`

View cache status.

```bash
curl "http://localhost:8000/cache"
```

### `GET /health`

Health check.

```bash
curl "http://localhost:8000/health"
```

---

## 💾 Caching System

Scraped pages are **cached in memory for 24 hours**.

- **First scrape**: Browser launches, visits page, extracts markdown (~3–10s)
- **Second scrape** (same URL, within 24h): Returns instantly from cache (~10ms)
- **Cache is per-process**: Restarting the server clears the cache

To force a fresh scrape, set `use_cache=false`:
```bash
curl "http://localhost:8000/scrape?url=https://example.com&use_cache=false"
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your LLM / MCP Client                     │
│  (Claude Desktop, Cursor, custom script, curl, etc.)        │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
        MCP stdio/SSE                 HTTP REST
               │                              │
        ┌──────▼──────┐              ┌────────▼────────┐
        │ mcp_server  │              │  mcp_server.py  │
        │   (stdio)   │              │   (FastAPI)     │
        └──────┬──────┘              └────────┬────────┘
               │                              │
               └──────────────┬───────────────┘
                              │
                    ┌─────────▼──────────┐
                    │   google_searcher   │
                    │     page_scraper    │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼──────────┐
                    │   CloakBrowser      │
                    │  (stealth Chromium) │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼──────────┐
                    │   Google / Web      │
                    └─────────────────────┘
```

---

## 🧪 Example LLM Prompts

Once the MCP server is connected, try these prompts:

> **"Search Google for the latest SpaceX Starship launch news and summarize the top 3 articles."**
> 
> LLM will: `search_google` → get URLs → `scrape_page` on each → summarize

> **"What are people saying on Hacker News about AI coding assistants?"**
> 
> LLM will: `search_google(query="hacker news ai coding assistants")` → `scrape_page` on relevant results → summarize discussions

> **"Read the Python 3.13 changelog and tell me the 5 most important features."**
> 
> LLM will: `scrape_page(url="https://docs.python.org/3/whatsnew/3.13.html")` → analyze markdown → extract features

---

## 🐛 Troubleshooting

### "Python 3.11+ is required"

Install Python 3.11 or newer:
```bash
# macOS
brew install python@3.11

# Ubuntu/Debian
sudo apt install python3.11 python3.11-venv

# Arch
sudo pacman -S python

# Or use pyenv
pyenv install 3.11.9
pyenv global 3.11.9
```

### "Binary download failed"

Set a custom download URL or use a local binary:
```bash
export CLOAKBROWSER_BINARY_PATH=/path/to/your/chrome
```

### macOS: "App is damaged" or Gatekeeper blocks

```bash
xattr -cr ~/.cloakbrowser/chromium-*/Chromium.app
```

### Google returns CAPTCHA / "unusual traffic"

This happens with rapid repeated searches. Solutions:
1. **Add delays** between searches (5–10 seconds)
2. **Use a proxy** with residential IP:
   ```python
   browser = launch(proxy="http://user:pass@residential-proxy:8080")
   ```
3. **Enable humanize** for mouse/keyboard behavior:
   ```python
   browser = launch(humanize=True)
   ```

### Still getting blocked on aggressive sites

Run in headed mode with a virtual display:
```bash
# Linux
sudo apt install xvfb
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99

# Then launch with headless=False
python mcp_server.py --http  # (modify to use headless=False)
```

### Port 8000 is already in use

```bash
# Find and kill the process
lsof -ti:8000 | xargs kill -9

# Or use a different port (modify mcp_server.py)
```

---

## 📁 Project Structure

```
.
├── mcp_server.py          # MCP server + FastAPI HTTP fallback
├── google_searcher.py     # Google SERP extraction via CloakBrowser
├── page_scraper.py        # Webpage → markdown with trafilatura
├── requirements.txt       # Python dependencies
├── install.sh             # Universal installer script
├── test_mcp.py            # MCP stdio test client
├── cloakbrowser/          # CloakBrowser source (submodule or cloned)
└── README.md              # This file
```

---

## 🔒 Security Notes

- The server runs locally — no external exposure by default
- CDP port is NOT exposed (unlike `cloakserve`)
- Cache is in-memory only — no data persists to disk
- No search history or user data is stored

**Do not** expose port 8000 to the public internet without authentication.

---

## 🤝 Integration Examples

### With Claude Desktop

1. Add the MCP config (see [MCP stdio mode](#mode-2-mcp-stdio-claude-desktop-cursor-etc))
2. Restart Claude Desktop
3. Ask: *"Search Google for the best Python web frameworks 2025"*
4. Claude will use `search_google` → show results → optionally `scrape_page` on the best link

### With Cursor

1. Open Cursor Settings → MCP
2. Add a new MCP server with command: `/path/to/.venv/bin/python /path/to/mcp_server.py`
3. Use in chat: *"Find and read the latest React documentation about Server Components"*

### With Custom Scripts

```python
import requests

# Search
r = requests.get("http://localhost:8000/search", params={"query": "rust async", "limit": 3})
results = r.json()["results"]

# Scrape best result
r = requests.get("http://localhost:8000/scrape", params={"url": results[0]["url"]})
markdown = r.json()["markdown"]
print(markdown)
```

---

## 📜 License

- **Wrapper code**: MIT (this repository)
- **CloakBrowser binary**: Free to use, no redistribution. See [BINARY-LICENSE.md](https://github.com/CloakHQ/CloakBrowser/blob/main/BINARY-LICENSE.md)

---

## 🙏 Credits

- [CloakBrowser](https://github.com/CloakHQ/cloakbrowser) — Stealth Chromium binary
- [MCP SDK](https://github.com/modelcontextprotocol/python-sdk) — Model Context Protocol
- [Trafilatura](https://github.com/adbar/trafilatura) — Intelligent web content extraction
- [FastAPI](https://fastapi.tiangolo.com) — Modern web framework

---

<p align="center">
  <sub>Built with ❤️ for AI agents that need real web access.</sub>
</p>
