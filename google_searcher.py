"""Google search automation using CloakBrowser."""

from __future__ import annotations

import logging
import os
import time
import urllib.parse
from typing import Any

from selectolax.lexbor import LexborHTMLParser

logger = logging.getLogger("google_searcher")

# Configurable via environment variables
SEARCH_TIMEOUT_MS = int(os.environ.get("CLOAK_SEARCH_TIMEOUT", "30000"))
SEARCH_WAIT_SECS = float(os.environ.get("CLOAK_SEARCH_WAIT", "1.5"))


def _clamp_limit(value: int) -> int:
    return max(1, min(20, value))


def _extract_full_text_from_node(node) -> str:
    """Extract all readable text from a result node, including all child text."""
    texts: list[str] = []

    def _walk(n):
        if hasattr(n, 'text') and n.text:
            t = n.text(strip=True)
            if t:
                texts.append(t)
        if hasattr(n, 'iter'):
            for child in n.iter():
                if hasattr(child, 'text') and child.text:
                    t = child.text(strip=True)
                    if t and t not in texts:
                        texts.append(t)

    _walk(node)

    # Deduplicate while preserving order
    seen = set()
    unique = []
    for t in texts:
        if t not in seen:
            seen.add(t)
            unique.append(t)

    # Join with space, but avoid title duplication
    return " ".join(unique)


def _extract_results(html: str, limit: int) -> list[dict[str, str]]:
    """Parse Google SERP HTML and extract search results with maximum snippet context."""
    parser = LexborHTMLParser(html)
    results: list[dict[str, str]] = []

    # Try multiple known Google result container selectors
    selectors = [
        "div.g",
        "div[data-result-index]",
        "div[data-ved].g",
        "div.tF2Cxc",
        "div[class*='g '][data-ved]",
        "div[jscontroller][data-ved]",
    ]

    nodes = []
    for sel in selectors:
        nodes = parser.css(sel)
        if nodes:
            logger.debug("Using selector '%s', found %d nodes", sel, len(nodes))
            break

    for node in nodes:
        if len(results) >= limit:
            break

        # Title: usually the first <h3>
        title = ""
        h3 = node.css_first("h3")
        if h3:
            title = h3.text(strip=True)

        # Link: first <a> with href
        url = ""
        a = node.css_first("a[href]")
        if a:
            href = a.attributes.get("href", "")
            if href and not href.startswith("/search?q=related:") and not href.startswith("/url?q="):
                url = href
            elif href.startswith("/url?q="):
                parsed = urllib.parse.urlparse(href)
                qs = urllib.parse.parse_qs(parsed.query)
                if qs.get("q"):
                    url = qs["q"][0]

        if not title or not url:
            continue

        # --- Extract snippet with multiple strategies ---
        snippet = ""

        # Strategy 1: Known snippet selectors
        snippet_selectors = [
            "div.VwiC3b",
            "div[data-sokoban-container] div.VwiC3b",
            "span.st",
            "div.s span",
            "div.yXK7lf",
            "div[data-sokoban-container] div",
            ".s3v94d",
            ".YyVfkd",
            "div[class*='VwiC3']",
        ]
        for snippet_sel in snippet_selectors:
            snip = node.css_first(snippet_sel)
            if snip:
                text = snip.text(strip=True)
                if text and len(text) > len(snippet):
                    snippet = text

        # Strategy 2: Extract all text from the result container and remove title
        if not snippet or len(snippet) < 50:
            full_text = _extract_full_text_from_node(node)
            # Remove title from beginning if present
            if full_text.startswith(title):
                full_text = full_text[len(title):].strip()
            # Also try to remove URL text if it appears
            domain = urllib.parse.urlparse(url).netloc
            if domain and domain in full_text:
                full_text = full_text.replace(domain, "", 1).strip()
            # Clean up common prefix patterns
            for prefix in ["·", "•", "-", "—"]:
                if full_text.startswith(prefix):
                    full_text = full_text[1:].strip()
            if len(full_text) > len(snippet):
                snippet = full_text

        # Strategy 3: Look for nested spans/divs that contain description text
        if not snippet or len(snippet) < 30:
            for desc in node.css("span, div"):
                text = desc.text(strip=True)
                if text and text != title and len(text) > 20 and len(text) < 2000:
                    if len(text) > len(snippet):
                        snippet = text

        # Extract date if present
        date = ""
        for date_sel in ["span.MUxGbd", "span.f", "span.ZuY7Ue", "span.YVIoue", "div.foot"]:
            dnode = node.css_first(date_sel)
            if dnode:
                dtext = dnode.text(strip=True)
                if dtext and len(dtext) < 100 and any(c.isdigit() for c in dtext):
                    date = dtext
                    break

        results.append({
            "title": title,
            "url": url,
            "snippet": snippet,
            **({"date": date} if date else {}),
        })

    return results


def search_google(query: str, limit: int = 5, headless: bool = True) -> dict[str, Any]:
    """Search Google using CloakBrowser and return structured results.

    Returns:
        dict with either:
        - {"results": [{title, url, snippet, date?}, ...]}
        - {"error": str, "message": str}
    """
    limit = _clamp_limit(limit)

    try:
        from cloakbrowser import launch
    except ImportError as e:
        return {"error": "cloakbrowser_not_found", "message": str(e)}

    browser = None
    try:
        logger.info("Launching CloakBrowser (headless=%s)", headless)
        browser = launch(headless=headless)
        page = browser.new_page()

        search_url = f"https://www.google.com/search?q={urllib.parse.quote_plus(query)}"
        logger.info("Navigating to %s", search_url)
        page.goto(search_url, wait_until="domcontentloaded", timeout=SEARCH_TIMEOUT_MS)

        time.sleep(SEARCH_WAIT_SECS)

        html = page.content()

        # --- Consent page detection & handling ---
        if "before you continue" in html.lower() or ("google.co" in page.url and ("consent" in page.url or "privacy" in page.url)):
            logger.info("Consent interstitial detected; attempting to accept.")
            consent_selectors = [
                'button:has-text("Accept all")',
                'button:has-text("I agree")',
                'button:has-text("Setuju")',
                'button:has-text("Terima")',
                'button[aria-label*="Accept"]',
                'form[action*="consent"] button',
                '#L2AGLb',
            ]
            clicked = False
            for sel in consent_selectors:
                try:
                    btn = page.locator(sel).first
                    if btn.is_visible(timeout=2000):
                        btn.click(timeout=5000)
                        clicked = True
                        logger.info("Clicked consent button via selector: %s", sel)
                        time.sleep(2)
                        break
                except Exception:
                    continue

            if not clicked:
                try:
                    page.evaluate("""
                        const btn = document.querySelector('#L2AGLb') || 
                                    document.querySelector('button[aria-label*=\"Accept\"]') ||
                                    Array.from(document.querySelectorAll('button')).find(b => 
                                        /accept|agree|setuju|terima/i.test(b.innerText)
                                    );
                        if (btn) btn.click();
                    """)
                    time.sleep(SEARCH_WAIT_SECS)
                except Exception as e:
                    logger.warning("JS consent click failed: %s", e)

            html = page.content()

        # --- Rate limit / CAPTCHA detection ---
        lower_html = html.lower()
        if "unusual traffic" in lower_html or "captcha" in lower_html or "recaptcha" in lower_html:
            return {"error": "blocked", "message": "Google returned CAPTCHA or unusual traffic detection."}
        if "sorry" in lower_html and "google" in lower_html and page.url.startswith("https://www.google.com/sorry"):
            return {"error": "blocked", "message": "Google search rate-limited (sorry page)."}

        results = _extract_results(html, limit)

        if not results:
            logger.warning("No results parsed. URL: %s", page.url)
            time.sleep(1)
            html = page.content()
            results = _extract_results(html, limit)

        logger.info("Extracted %d results", len(results))
        return {"results": results}

    except Exception as e:
        logger.exception("Search failed")
        return {"error": "search_failed", "message": str(e)}

    finally:
        if browser:
            try:
                browser.close()
            except Exception as e:
                logger.warning("Browser close error: %s", e)
