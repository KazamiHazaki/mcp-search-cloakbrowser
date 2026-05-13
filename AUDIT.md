# Portability Audit — Hardcoded/Static Values

## 🔴 CRITICAL

### 1. install.sh — Wrong REPO_URL
```bash
REPO_URL="https://github.com/CloakHQ/cloakbrowser"
```
Ini clone repo **CloakBrowser source code**, bukan repo **MCP server kita**! User akan clone repo yang salah.
**Fix:** `https://github.com/KazamiHazaki/mcp-search-cloakbrowser`

### 2. bin/* wrapper scripts — Hardcoded MacBook path
Semua wrapper scripts punya path absolute ke `/Users/samuraiheart/work/cloackbrowser-mcp/...` — ini **hanya jalan di mesin developer**.
```bash
source "/Users/samuraiheart/work/cloackbrowser-mcp/.venv/bin/activate"
exec python "/Users/samuraiheart/work/cloackbrowser-mcp/mcp_server.py" "$@"
```
Di VM Linux: path ini nggak ada → gagal.
**Fix:** Buat self-locating atau generate ulang saat install.

---

## 🟡 MODERATE

### 3. mcp_server.py — Port hardcoded 8000
```python
uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
```
Kalau port 8000 sudah dipakai service lain, user harus edit file.
**Fix:** Support `PORT` env var dan `--port` argument.

### 4. google_searcher.py — Timeout hardcoded 30 detik
```python
page.goto(..., timeout=30000)
```
Di network lambat (proxy, VPS) ini bisa terlalu ketat.
**Fix:** Support `CLOAK_SEARCH_TIMEOUT` env var.

### 5. page_scraper.py — Cache TTL hardcoded 24 jam
```python
CACHE_TTL_SECONDS = 24 * 60 * 60
```
**Fix:** Support `CLOAK_CACHE_TTL_SECONDS` env var.

### 6. page_scraper.py — Scrape timeout hardcoded 30 detik
```python
page.goto(..., timeout=30000)
```
**Fix:** Support `CLOAK_SCRAPE_TIMEOUT` env var.

### 7. install.sh — wrapper scripts overwrite existing bin/
Kalau user clone repo lalu jalanin install.sh, `create_wrappers()` nulis ke `$INSTALL_DIR/bin/`. Kalau `$INSTALL_DIR` sama dengan repo directory, ini overwrite wrapper scripts yang sudah di-git. Tapi kalau beda (default `~/.cloakbrowser-mcp`), user harus panggil `~/.cloakbrowser-mcp/bin/cloak-search`, bukan `./bin/cloak-search` dari repo.
**Fix:** Buat wrapper scripts self-locating agar bisa jalan dari mana saja.

---

## 🟢 LOW / ACCEPTABLE

### 8. test_mcp.py — hardcoded test query
```python
"query": "python programming", "limit": 2
```
Ini test data, acceptable.

### 9. README — contoh path absolute
```json
"command": "/absolute/path/to/.venv/bin/python"
```
Ini intentional sebagai placeholder, tapi sebaiknya ditandai jelas.

### 10. requirements.txt — cloakbrowser dari PyPI
Sekarang sudah `cloakbrowser>=0.3.28` (PyPI). Sebelumnya `-e ./cloakbrowser` (local path) sudah di-fix. ✅
