"""One-time login: opens a browser window with the bot's own profile.
Log into TikTok yourself, then close the window. The session is saved in ./profile."""
import os
from pathlib import Path

# Chromium lives inside the venv (not %LOCALAPPDATA%) so Task Scheduler can find it.
os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", "0")

from playwright.sync_api import sync_playwright

HERE = Path(__file__).parent
PROFILE = HERE / "profile"

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PROFILE, headless=False, viewport=None, args=["--start-maximized", "--disable-gpu"]
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto("https://www.tiktok.com/login")
    print("Log into TikTok in the browser window, then close it to finish.")
    try:
        page.wait_for_event("close", timeout=0)
    except Exception:
        pass
    ctx.close()
print("Saved. You can now run streak.py.")
