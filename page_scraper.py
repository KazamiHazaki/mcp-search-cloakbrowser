"""Page scraping with CloakBrowser — extract full page content as markdown."""

from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from typing import Any

import trafilatura
from markdownify import markdownify as md

logger = logging.getLogger("page_scraper")

# Configurable via environment variables
CACHE_TTL_SECONDS = int(os.environ.get("CLOAK_CACHE_TTL_SECONDS", str(24 * 60 * 60)))
SCRAPE_TIMEOUT_MS = int(os.environ.get("CLOAK_SCRAPE_TIMEOUT", "30000"))
SCRAPE_WAIT_SECS = float(os.environ.get("CLOAK_SCRAPE_WAIT", "1.5"))


@dataclass
class _CacheEntry:
    markdown: str
    timestamp: float
    title: str = ""


# In-memory cache: url -> _CacheEntry
_page_cache: dict[str, _CacheEntry] = {}


def _is_cached(url: str) -> bool:
    entry = _page_cache.get(url)
    if not entry:
        return False
    if time.time() - entry.timestamp > CACHE_TTL_SECONDS:
        logger.info("Cache expired for %s", url)
        del _page_cache[url]
        return False
    return True


def _get_cached(url: str) -> dict[str, Any] | None:
    if _is_cached(url):
        entry = _page_cache[url]
        logger.info("Cache HIT for %s", url)
        return {
            "url": url,
            "title": entry.title,
            "markdown": entry.markdown,
            "cached": True,
            "cached_at": entry.timestamp,
        }
    return None


def _extract_with_trafilatura(html: str, url: str) -> tuple[str, str]:
    """Use trafilatura for intelligent main-content extraction.
    Returns (title, markdown)."""
    extracted = trafilatura.extract(
        html,
        url=url,
        output_format="markdown",
        include_comments=False,
        include_tables=True,
        include_images=False,
        include_links=True,
        deduplicate=True,
    )
    title = trafilatura.extract_metadata(html, url=url)
    title_str = title.title if title and title.title else ""
    return title_str, (extracted or "")


def _extract_fallback(html: str) -> tuple[str, str]:
    """Fallback: convert entire page body to markdown."""
    from selectolax.lexbor import LexborHTMLParser
    parser = LexborHTMLParser(html)

    title = ""
    title_node = parser.css_first("title")
    if title_node:
        title = title_node.text(strip=True)

    # Try to find main content area
    main = parser.css_first("main") or parser.css_first("article") or parser.css_first("[role='main']")
    if not main:
        main = parser.css_first("body")

    if main:
        markdown = md(main.html, heading_style="ATX", strip=["script", "style", "nav", "footer", "header", "aside"])
    else:
        markdown = md(html, heading_style="ATX", strip=["script", "style", "nav", "footer", "header", "aside"])

    return title, markdown


def scrape_page(url: str, headless: bool = True, use_cache: bool = True) -> dict[str, Any]:
    """Scrape a webpage and return its content as markdown.

    Args:
        url: The URL to scrape.
        headless: Run browser headless.
        use_cache: If True, return cached result if available and fresh.

    Returns:
        dict with keys: url, title, markdown, cached, word_count, char_count
        or on error: error, message
    """
    if use_cache:
        cached = _get_cached(url)
        if cached:
            cached["word_count"] = len(cached["markdown"].split())
            cached["char_count"] = len(cached["markdown"])
            return cached

    try:
        from cloakbrowser import launch
    except ImportError as e:
        return {"error": "cloakbrowser_not_found", "message": str(e)}

    browser = None
    try:
        logger.info("Scraping %s (headless=%s)", url, headless)
        browser = launch(headless=headless)
        page = browser.new_page()

        page.goto(url, wait_until="domcontentloaded", timeout=SCRAPE_TIMEOUT_MS)
        time.sleep(SCRAPE_WAIT_SECS)  # Let dynamic content settle

        html = page.content()
        page_title = page.title()

        # --- Try trafilatura first (best content extraction) ---
        try:
            extracted_title, markdown = _extract_with_trafilatura(html, url)
            if not extracted_title and page_title:
                extracted_title = page_title
        except Exception as e:
            logger.warning("Trafilatura failed (%s), using fallback", e)
            extracted_title, markdown = _extract_fallback(html)
            if not extracted_title and page_title:
                extracted_title = page_title

        if not markdown or len(markdown.strip()) < 100:
            # If extraction is too thin, fallback to full body markdown
            logger.warning("Trafilatura output too short, using fallback")
            extracted_title, markdown = _extract_fallback(html)
            if not extracted_title and page_title:
                extracted_title = page_title

        # Clean up excessive whitespace
        lines = [line.rstrip() for line in markdown.splitlines()]
        markdown = "\n".join(line for line in lines if line or (lines and lines[lines.index(line) - 1] if lines.index(line) > 0 else False))
        markdown = markdown.strip()

        # Cache the result
        _page_cache[url] = _CacheEntry(
            markdown=markdown,
            timestamp=time.time(),
            title=extracted_title,
        )

        result = {
            "url": url,
            "title": extracted_title,
            "markdown": markdown,
            "cached": False,
            "word_count": len(markdown.split()),
            "char_count": len(markdown),
        }
        logger.info(
            "Scraped %s — title=%r words=%d chars=%d",
            url, extracted_title, result["word_count"], result["char_count"]
        )
        return result

    except Exception as e:
        logger.exception("Scrape failed for %s", url)
        return {"error": "scrape_failed", "message": str(e)}

    finally:
        if browser:
            try:
                browser.close()
            except Exception as e:
                logger.warning("Browser close error: %s", e)


def get_cache_status() -> dict[str, Any]:
    """Return cache statistics."""
    now = time.time()
    active = {k: v for k, v in _page_cache.items() if now - v.timestamp <= CACHE_TTL_SECONDS}
    expired = len(_page_cache) - len(active)
    # Clean expired
    for k in list(_page_cache.keys()):
        if now - _page_cache[k].timestamp > CACHE_TTL_SECONDS:
            del _page_cache[k]
    return {
        "cached_urls": list(active.keys()),
        "active_count": len(active),
        "expired_cleaned": expired,
        "ttl_hours": CACHE_TTL_SECONDS / 3600,
    }
