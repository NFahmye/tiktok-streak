"""Sends one streak message per friend per day via tiktok.com/messages.

Usage:
  python streak.py            send to everyone not yet messaged today
  python streak.py --dry-run  open each chat and type the message, but don't send
  python streak.py --check    only check every friend can be found in the chat list
  python streak.py --test-notify  send a test notification to this PC and your phone
"""
import json
import msvcrt
import os
import random
import socket
import subprocess
import sys
import time
import traceback
import unicodedata
import urllib.request
from datetime import date, datetime
from pathlib import Path

# Chromium lives inside the venv (not %LOCALAPPDATA%) so Task Scheduler can find it.
os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", "0")

from playwright.sync_api import TimeoutError as PWTimeout
from playwright.sync_api import sync_playwright

HERE = Path(__file__).parent
PROFILE = HERE / "profile"
CONFIG = HERE / "config.json"
STATE = HERE / "state.json"
ALERTS = HERE / "alerts.json"
LOG = HERE / "streak.log"
SHOTS = HERE / "screenshots"

DRY_RUN = "--dry-run" in sys.argv
CHECK = "--check" in sys.argv
TEST_NOTIFY = "--test-notify" in sys.argv
REAL_RUN = not (DRY_RUN or CHECK)


def log(msg):
    line = f"{datetime.now():%Y-%m-%d %H:%M:%S}  {msg}"
    print(line)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def load_json(path, default):
    try:
        # utf-8-sig: Notepad/PowerShell may save the file with a BOM
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


TOAST_PS = r"""
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$t = $x.GetElementsByTagName('text')
$t.Item(0).AppendChild($x.CreateTextNode($env:TOAST_TITLE)) | Out-Null
$t.Item(1).AppendChild($x.CreateTextNode($env:TOAST_MSG)) | Out-Null
$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($x))
"""


def notify(title, msg, error=True, key=None):
    """Windows toast on this PC + push to the phone via ntfy.sh. Never raises.
    With a key, the same kind of alert is sent at most once per day (runs retry hourly)."""
    cfg = load_json(CONFIG, {})
    today = date.today().isoformat()
    alerts = load_json(ALERTS, {})
    if key and alerts.get(key) == today:
        log(f"(alert '{key}' already sent today)")
        return
    delivered = False
    if cfg.get("pc_notification", True):
        try:
            subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", TOAST_PS],
                env={**os.environ, "TOAST_TITLE": title, "TOAST_MSG": msg},
                creationflags=subprocess.CREATE_NO_WINDOW, timeout=30, capture_output=True,
            )
            delivered = True
        except Exception as e:
            log(f"PC notification failed: {e}")
    topic = cfg.get("ntfy_topic")
    if topic:
        try:
            req = urllib.request.Request(
                f"https://ntfy.sh/{topic}", data=msg.encode("utf-8"),
                headers={"Title": title, "Priority": "high" if error else "default",
                         "Tags": "warning" if error else "fire"},
            )
            urllib.request.urlopen(req, timeout=15)
            delivered = True
        except Exception as e:
            log(f"Phone notification failed: {e}")
    if key and delivered:
        alerts[key] = today
        ALERTS.write_text(json.dumps(alerts, indent=2), encoding="utf-8")


def wait_for_internet(minutes=3):
    """After waking from sleep, Wi-Fi can take a while to come back."""
    deadline = time.time() + minutes * 60
    while True:
        try:
            socket.create_connection(("www.tiktok.com", 443), timeout=5).close()
            return True
        except OSError:
            if time.time() > deadline:
                return False
            time.sleep(15)


def pause(lo=1.5, hi=4.0):
    time.sleep(random.uniform(lo, hi))


def strip_emoji(s):
    """Drop emoji/symbols so 'alex' matches 'alex😾'."""
    return "".join(
        c for c in s if not unicodedata.category(c).startswith(("S", "M", "C"))
    ).strip().casefold()


def name_matches(shown, friend):
    shown, friend = shown.strip(), friend.strip()
    if shown == friend:
        return True
    # only fall back to emoji-insensitive matching when the name has real letters,
    # and never to substring matching (so "m" can't hit "man")
    return bool(strip_emoji(friend)) and strip_emoji(shown) == strip_emoji(friend)


def find_chat(page, friend):
    """Return the friend's nickname element in the chat list, scrolling down if needed."""
    page.locator('[data-e2e="dm-new-conversation-item"]').first.wait_for(timeout=20000)
    names = page.locator('[data-e2e="dm-new-conversation-nickname"]')
    # start from the top of the list each time
    page.locator('[data-e2e="dm-new-conversation-item"]').first.hover()
    page.mouse.wheel(0, -50000)
    pause(0.8, 1.5)
    for _ in range(20):
        for i, shown in enumerate(names.all_inner_texts()):
            if name_matches(shown, friend):
                return names.nth(i)
        page.locator('[data-e2e="dm-new-conversation-item"]').last.hover()
        page.mouse.wheel(0, 1500)
        pause(1, 2)
    raise PWTimeout(f"{friend!r} not in chat list")


def open_chat(page, friend):
    item = find_chat(page, friend)
    item.scroll_into_view_if_needed()
    item.click()
    # make sure the right chat actually opened before typing anything
    header = page.locator('[data-e2e="dm-new-chat-nickname"]').first
    header.wait_for(timeout=10000)
    for _ in range(10):
        if name_matches(header.inner_text(), friend):
            return
        pause(0.5, 1)
    raise PWTimeout(f"opened chat header is {header.inner_text()!r}, not {friend!r}")


def send_message(page, text):
    box = page.locator(
        '[data-e2e="message-input-area"] [contenteditable="true"]'
    ).first
    box.wait_for(state="visible", timeout=15000)
    box.click()
    pause(0.5, 1.2)
    page.keyboard.type(text, delay=random.randint(60, 140))
    pause(0.6, 1.5)
    if DRY_RUN:
        # clear what we typed so nothing is left in the draft
        page.keyboard.press("Control+A")
        page.keyboard.press("Backspace")
        return
    page.keyboard.press("Enter")
    pause(1.5, 3.0)
    # the editor empties once TikTok accepts the message
    if box.inner_text().strip():
        raise PWTimeout("message still in the input box after pressing Enter")


def main():
    if TEST_NOTIFY:
        notify("TikTok streak: test", "Notifications work. You'll get one like this if a run fails.")
        return 0
    cfg = load_json(CONFIG, {})
    friends = cfg.get("friends", [])
    messages = cfg.get("messages", ["🔥"])
    if not friends:
        log("No friends in config.json - nothing to do.")
        if REAL_RUN:
            notify("TikTok streak: config problem", "config.json has no friends (or isn't valid JSON).",
                   key="config")
        return 1

    today = date.today().isoformat()
    state = load_json(STATE, {})
    todo = friends if CHECK else [f for f in friends if state.get(f) != today]
    if not todo:
        log("Everyone already messaged today.")
        return 0

    # the scheduled task retries every hour, so only alert about connection problems late in the day
    late = datetime.now().hour >= 21
    if not wait_for_internet():
        log("No internet - will retry on the next run.")
        return 4

    failed, sent = [], []
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            PROFILE, headless=cfg.get("headless", False), viewport={"width": 1280, "height": 900},
            # some laptop GPU drivers crash Windows under Chromium; keep it off the GPU
            args=["--disable-gpu"],
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        try:
            page.goto("https://www.tiktok.com/messages", wait_until="domcontentloaded", timeout=60000)
        except PWTimeout:
            ctx.close()
            log("TikTok didn't load - will retry on the next run.")
            if REAL_RUN and late:
                notify("TikTok streak: not sent yet", f"Couldn't reach TikTok today - {len(todo)} friends "
                       "still not messaged. Check your internet, or run streak.py.", key="unreachable")
            return 4
        pause(4, 7)

        if "login" in page.url:
            log("Not logged in - run login.py first.")
            ctx.close()
            if REAL_RUN:
                notify("TikTok streak: logged out", "TikTok login expired. Run login.py on your PC, then streak.py.",
                       key="logged_out")
            return 2

        random.shuffle(todo)
        for friend in todo:
            text = random.choice(messages)
            try:
                if CHECK:
                    find_chat(page, friend)
                    log(f"[check] found {friend}")
                    continue
                open_chat(page, friend)
                pause()
                send_message(page, text)
                if DRY_RUN:
                    log(f"[dry-run] {friend}: would send {text!r}")
                else:
                    state[friend] = today
                    STATE.write_text(json.dumps(state, indent=2, ensure_ascii=False), encoding="utf-8")
                    sent.append(friend)
                    log(f"Sent to {friend}: {text!r}")
            except PWTimeout:
                failed.append(friend)
                SHOTS.mkdir(exist_ok=True)
                safe = "".join("_" if c in '<>:"/\\|?* ' else c for c in friend)
                shot = SHOTS / f"{today}_{safe}.png"
                page.screenshot(path=str(shot))
                log(f"FAILED for {friend} (chat or input box not found) - see {shot.name}")
                continue
            pause(3, 8)

        ctx.close()

    if REAL_RUN and failed:
        notify(
            f"TikTok streak: {len(failed)} failed",
            f"Not sent to: {', '.join(failed)}. Sent {len(sent)}/{len(todo)}. "
            "It retries every hour. Check streak.log and screenshots if this keeps happening.",
            key="failed",
        )
    elif REAL_RUN and cfg.get("notify_on_success"):
        notify("TikTok streak done", f"Sent to all {len(sent)} friends.", error=False)
    return 1 if failed else 0


if __name__ == "__main__":
    # only one run at a time - a second one (e.g. scheduled catch-up during a manual run) just exits
    lock = open(HERE / "run.lock", "w")
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        log("Another run is already in progress - skipping.")
        sys.exit(0)
    try:
        sys.exit(main())
    except Exception as e:
        log("CRASHED:\n" + traceback.format_exc())
        if REAL_RUN:
            notify("TikTok streak crashed", f"{type(e).__name__}: {str(e)[:200]} - see streak.log", key="crashed")
        sys.exit(3)
