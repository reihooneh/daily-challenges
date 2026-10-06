"""End-to-end check in a real browser (headless Chromium via Playwright).

Usage:  make web && python3 scripts/browser-check.py [screenshot-dir]
Serves web/ on a local port, then drives the page at desktop and phone sizes.
"""
import asyncio
import functools
import http.server
import pathlib
import sys
import threading

from playwright.async_api import async_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent / "web"
SHOTS = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"


def serve():
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    handler = functools.partial(Quiet, directory=str(ROOT))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


async def check(browser, base, name, width, height):
    page = await browser.new_page(viewport={"width": width, "height": height})
    problems = []
    page.on("console", lambda m: problems.append(m.text) if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: problems.append(str(e)))
    await page.goto(base)
    await page.wait_for_selector(".verdict.no")

    async def verdict_says(text):
        await page.wait_for_function("t => document.getElementById('verdict').textContent.includes(t)", arg=text)

    async def shot(label):
        if SHOTS:
            await page.screenshot(path=str(SHOTS / f"{name}-{label}.png"), full_page=True)

    # 1. The default example is impossible, with three single-wish ways out.
    assert await page.locator(".way").count() == 3, "expected three ways out"
    assert await page.locator("#conflict li").count() == 6
    assert await page.locator(".way.selected").count() == 1, "first way out should be previewed"
    assert await page.locator(".block").count() > 0
    assert not await page.evaluate("document.documentElement.scrollWidth > window.innerWidth"), "page overflows sideways"
    await shot("impossible")

    # 2. "Give this up" unticks the wish and the plan becomes possible.
    await page.locator(".way button.primary").nth(1).click()
    await page.wait_for_selector(".verdict.ok")
    assert not await page.locator('#no-days input[value="4"]').is_checked()
    assert await page.locator("#why").is_hidden()
    await shot("fits")

    # 3. Other examples.
    await page.select_option("#sample", "firstyear")
    await page.wait_for_selector(".verdict.ok")
    assert await page.locator(".block").count() >= 12
    await page.select_option("#sample", "pair")
    await page.wait_for_selector(".verdict.no")
    assert await page.locator(".way-label").first.text_content() == "Drop a course"

    # 4. Typing an error shows a friendly message pointing at the right box.
    await page.fill("#courses", "COMP1010\n  Lecture: Someday 10-12")
    await verdict_says("Line 2 of your classes")
    await page.fill("#courses", "COMP1010\n  Lecture: Mon 10-12")
    await verdict_says("Everything fits")
    await page.fill("#busy", "Blursday 9-10")
    await verdict_says("In your wishes or busy times")

    # 5. Markup typed by the user is never rendered as HTML.
    await page.fill("#busy", "")
    await verdict_says("Everything fits")
    await page.fill("#courses", "COMP1010 <img src=x onerror=alert(1)>\n  Lecture: Mon 10-12")
    await verdict_says("Line 1 of your classes")
    assert await page.locator("img").count() == 0

    # 6. A shared link restores the plan; a hostile one is ignored.
    await page.select_option("#sample", "friday")
    await page.wait_for_selector(".verdict.no")
    await page.click("#share")
    link = page.url
    assert "#" in link
    other = await browser.new_page(viewport={"width": width, "height": height})
    await other.goto(link)
    await other.wait_for_selector(".verdict.no")
    assert await other.locator(".way").count() == 3
    await other.goto(base + "#%3Cimg%20src%3Dx%20onerror%3Dalert(1)%3E")
    await other.reload()
    await other.wait_for_selector(".verdict.no")
    assert "#" not in other.url and await other.locator("img").count() == 0
    await other.close()

    # 7. Keyboard only: tab to a day chip and toggle it with the space bar.
    await page.focus('#no-days input[value="4"]')
    await page.keyboard.press("Space")
    await page.wait_for_selector(".verdict.ok")

    assert problems == [], f"console problems: {problems}"
    print(f"{name}: all checks passed")
    await page.close()


async def main():
    server = serve()
    base = f"http://127.0.0.1:{server.server_address[1]}/"
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROMIUM if pathlib.Path(CHROMIUM).exists() else None)
        await check(browser, base, "desktop", 1280, 900)
        await check(browser, base, "phone", 375, 760)
        await browser.close()
    server.shutdown()


asyncio.run(main())
