#!/usr/bin/env python3
"""MCP Server + HTTP API for Google Search and Page Scraping via CloakBrowser.

Modes:
  python mcp_server.py          → MCP stdio server (default)
  python mcp_server.py --http   → FastAPI HTTP server on port 8000
  python mcp_server.py --sse    → FastAPI with MCP SSE endpoint on port 8000
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse

# Configure logging before anything else
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("mcp_server")

# ---------------------------------------------------------------------------
# Core logic wrappers (synchronous — wrapped in executor for async)
# ---------------------------------------------------------------------------

def _do_search(query: str, limit: int = 5) -> dict[str, Any]:
    from google_searcher import search_google
    return search_google(query=query, limit=limit, headless=True)


def _do_scrape(url: str, use_cache: bool = True) -> dict[str, Any]:
    from page_scraper import scrape_page
    return scrape_page(url=url, headless=True, use_cache=use_cache)


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

from mcp.server.fastmcp import FastMCP  # type: ignore[import-untyped]

mcp = FastMCP("google-search")


@mcp.tool()
async def search_google(query: str, limit: int = 5) -> str:
    """Search Google using a stealth browser and return structured results.

    Args:
        query: The search query string.
        limit: Maximum number of results to return (1-20, default 5).

    Returns:
        JSON string with either {"results": [{title, url, snippet, date?}, ...]}
        or {"error": ..., "message": ...}.
    """
    logger.info("MCP tool search_google called: query=%r limit=%d", query, limit)
    result = await asyncio.get_event_loop().run_in_executor(None, _do_search, query, limit)
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
async def scrape_page(url: str, use_cache: bool = True) -> str:
    """Scrape a webpage and return its full content as markdown.

    Automatically caches results for 24 hours so repeated requests
    for the same URL return instantly without re-scraping.

    Args:
        url: The full URL of the page to scrape (must include http:// or https://).
        use_cache: Whether to use cached result if available (default True).

    Returns:
        JSON string with keys: url, title, markdown, cached, word_count, char_count
        or on error: error, message.
    """
    logger.info("MCP tool scrape_page called: url=%r use_cache=%s", url, use_cache)
    result = await asyncio.get_event_loop().run_in_executor(None, _do_scrape, url, use_cache)
    return json.dumps(result, ensure_ascii=False, indent=2)


@mcp.tool()
async def cache_status() -> str:
    """Show which scraped pages are currently cached.

    Returns:
        JSON string with cache statistics.
    """
    from page_scraper import get_cache_status
    result = get_cache_status()
    return json.dumps(result, ensure_ascii=False, indent=2)


# ---------------------------------------------------------------------------
# FastAPI HTTP Server
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: ARG001
    logger.info("HTTP server starting")
    yield
    logger.info("HTTP server shutting down")


app = FastAPI(title="CloakBrowser Search & Scrape", lifespan=lifespan)


@app.get("/search")
async def search_endpoint(
    query: str = Query(..., description="Search query"),
    limit: int = Query(5, description="Number of results (1-20)"),
) -> JSONResponse:
    """HTTP endpoint for Google search.

    Example:
        curl "http://localhost:8000/search?query=python+programming&limit=3"
    """
    logger.info("HTTP search called: query=%r limit=%d", query, limit)
    result = await asyncio.get_event_loop().run_in_executor(None, _do_search, query, limit)
    return JSONResponse(content=result)


@app.get("/scrape")
async def scrape_endpoint(
    url: str = Query(..., description="URL to scrape"),
    use_cache: bool = Query(True, description="Use cached result if available"),
) -> JSONResponse:
    """HTTP endpoint to scrape a webpage and return markdown.

    Example:
        curl "http://localhost:8000/scrape?url=https://python.org"
    """
    logger.info("HTTP scrape called: url=%r use_cache=%s", url, use_cache)
    result = await asyncio.get_event_loop().run_in_executor(None, _do_scrape, url, use_cache)
    return JSONResponse(content=result)


@app.get("/cache")
async def cache_endpoint() -> JSONResponse:
    """Show cache status.

    Example:
        curl "http://localhost:8000/cache"
    """
    from page_scraper import get_cache_status
    result = get_cache_status()
    return JSONResponse(content=result)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "cloakbrowser-search-scrape"}


# ---------------------------------------------------------------------------
# SSE-based MCP transport (optional, shares HTTP port)
# ---------------------------------------------------------------------------

def _mount_sse(app: FastAPI) -> None:
    from mcp.server.sse import SseServerTransport  # type: ignore[import-untyped]

    sse = SseServerTransport("/messages/")

    async def handle_sse(request):
        async with sse.connect_sse(
            request.scope, request.receive, request._send
        ) as (read_stream, write_stream):
            await mcp._mcp_server.run(
                read_stream,
                write_stream,
                mcp._mcp_server.create_initialization_options(),
            )

    app.add_route("/sse", handle_sse)
    app.add_route("/messages/{session_id}", endpoint=sse.handle_post_message, methods=["POST"])
    logger.info("Mounted MCP SSE endpoint at /sse")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    args = sys.argv[1:]

    if "--http" in args:
        logger.info("Starting HTTP server on http://localhost:8000")
        uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

    elif "--sse" in args:
        _mount_sse(app)
        logger.info("Starting HTTP+SSE server on http://localhost:8000")
        logger.info("MCP SSE endpoint: http://localhost:8000/sse")
        logger.info("HTTP search endpoint: http://localhost:8000/search")
        logger.info("HTTP scrape endpoint: http://localhost:8000/scrape")
        uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

    else:
        # Default: stdio MCP server
        logger.info("Starting MCP stdio server")
        mcp.run()
