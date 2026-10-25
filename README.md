# 🔥 TikTok Streak

Keeps your TikTok DM streaks alive by sending a short message (like 🔥) to the friends you choose, once a day, from your Windows laptop.

- Sends **one message per friend per day** at the time you choose (default: midnight)
- Picks a random message from your list, types it like a person, and opens chats in random order
- Opens the correct chat by checking the chat header before typing, so it can't message the wrong person
- **Catches up** if your laptop was off or asleep: it runs as soon as you open the laptop
- Sends an **alert to your phone** if something goes wrong (free ntfy app, no account needed)

> ⚠️ **Read before using**
> - Automating TikTok is against TikTok's Terms of Service. Accounts that use bots *can* get restricted. Use at your own risk.
> - A streak needs **both** people to message every day. This only sends **your** side. Your friend has to reply, or run this too.
> - It only works while your laptop is on. Open it at least once a day.

---

## Contents
1. [What you need](#1-what-you-need)
2. [Install (one command)](#2-install-one-command)
3. [What the installer asks you to do](#3-what-the-installer-asks-you-to-do)
4. [Phone alerts](#4-phone-alerts)
5. [Change friends or messages](#5-change-friends-or-messages)
6. [Change the time](#6-change-the-time)
7. [Useful commands](#7-useful-commands)
8. [Troubleshooting](#8-troubleshooting)
9. [Update](#9-update)
10. [Uninstall](#10-uninstall)
11. [Privacy & safety](#11-privacy--safety)

---

## 1. What you need
- A **Windows 10 or 11** laptop/PC
- About **500 MB** of free space
- Your TikTok login (you log in yourself in a browser window; your password is never stored by this tool)

Python is installed for you if you don't have it.

## 2. Install (one command)

1. Press **Start**, type **PowerShell**, and open **Windows PowerShell** (no need for admin).
2. Copy this line, paste it into PowerShell (right-click pastes), and press **Enter**:

```powershell
irm https://raw.githubusercontent.com/enNeF/tiktok-streak/main/install.ps1 | iex
```

3. Follow the steps on screen. It takes about 5 minutes, mostly downloading.

Everything is installed into `C:\Users\<you>\tiktok-streak`.

## 3. What the installer asks you to do

| Step | What happens | What you do |
|---|---|---|
| **1–3** | Checks or installs Python, downloads this tool, and installs a private Chrome browser just for the bot | Nothing, just wait |
| **4. Log in** | A browser window opens on TikTok's login page | Log in **(QR code from the TikTok app on your phone is easiest)**, wait for your feed to load, then **close the browser window** |
| **5. Friends** | Notepad opens `config.json` | Type your friends' names **exactly as they appear in your TikTok DM list**, save (Ctrl+S) and close Notepad. The installer then checks every name is found |
| **6. Time** | Asks what time to run each day | Type a time like `00:00` (midnight) or `21:30`, or just press Enter for midnight |
| **7. Phone alerts** | Shows your personal alert topic | Optional, see [Phone alerts](#4-phone-alerts) |

### How to write names in `config.json`

```json
{
  "friends": [
    "ali",
    "moon.",
    "Siti 🌸",
    "هادي"
  ],
  "messages": [
    "🔥",
    "🔥🔥"
  ],
  ...
}
```

- Use the **display name** shown in your DM list (bold text), **not** the @username.
- Every name goes in `"double quotes"`, with a **comma after every one except the last**.
- Emoji at the end can be left out: `"Siti"` also matches `Siti 🌸`. A name that is *only* emoji must match exactly.
- Short names are safe: `"m"` only matches a chat called exactly `m`, never `man`.
- If two chats have the same name, the one higher in your DM list (most recent) is used.

## 4. Phone alerts

You get a push notification when:
- a friend couldn't be messaged (it tells you who),
- your TikTok login expired, or
- the bot crashed or `config.json` is broken.

To set it up:
1. Install **ntfy** on your phone ([iPhone](https://apps.apple.com/app/ntfy/id1625396347) / [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy)).
2. Tap **+**, enter your topic (the installer shows it, and it's also `ntfy_topic` in `config.json`), and tap **Subscribe**.
3. Test it:
   ```powershell
   cd $env:USERPROFILE\tiktok-streak; .\.venv\Scripts\python.exe streak.py --test-notify
   ```

Want a message when everything **succeeds** too? Set `"notify_on_success": true` in `config.json`.

> Your topic name is random. Don't share it, or others could read your alerts.

## 5. Change friends or messages

Open the config:
```powershell
notepad $env:USERPROFILE\tiktok-streak\config.json
```
Edit `friends` and/or `messages`, save, then check every friend is found:
```powershell
cd $env:USERPROFILE\tiktok-streak; .\.venv\Scripts\python.exe streak.py --check
```
Each friend shows `found` or `FAILED`. A failed name usually has a small spelling difference.

## 6. Change the time
```powershell
cd $env:USERPROFILE\tiktok-streak; .\setup_task.ps1 -Time 21:30
```
Use 24-hour time. The bot runs at that time plus a random 0–30 minutes, so it isn't the exact same second every day.

> If PowerShell says *"running scripts is disabled"*, use:
> `powershell -ExecutionPolicy Bypass -File .\setup_task.ps1 -Time 21:30`

**When does it actually run?**

| Your laptop at that time | Result |
|---|---|
| On or locked | Runs on time |
| Asleep / shut down | Runs **as soon as you open the laptop and log in** that day |
| Not opened all day | Doesn't run, so the streak can break |

## 7. Useful commands
Run these in PowerShell inside the folder (`cd $env:USERPROFILE\tiktok-streak` first):

| Command | What it does |
|---|---|
| `.\.venv\Scripts\python.exe streak.py` | Send today's messages now (skips friends already messaged today) |
| `.\.venv\Scripts\python.exe streak.py --check` | Only check every friend can be found (sends nothing) |
| `.\.venv\Scripts\python.exe streak.py --dry-run` | Open each chat and type the message, then delete it (sends nothing) |
| `.\.venv\Scripts\python.exe streak.py --test-notify` | Send a test phone alert |
| `.\.venv\Scripts\python.exe login.py` | Log into TikTok again |
| `.\setup_task.ps1 -Time HH:MM` | Change the daily time |
| `.\setup_task.ps1 -Remove` | Stop the daily automation |
| `notepad streak.log` | See what happened on each run |

## 8. Troubleshooting

**"TikTok streak: logged out" alert / log says "Not logged in"**
Your TikTok session expired. Run `.\.venv\Scripts\python.exe login.py`, log in, and close the window.

**A friend shows `FAILED`**
- Check the spelling against your DM list (`--check` helps). Look in the `screenshots` folder for a picture of what the bot saw.
- The chat may be very old. Send them one message by hand so it moves up your DM list.

**Everyone fails at once**
TikTok may have changed its website. Check `screenshots\` and open an issue on this GitHub page.

**Nothing happened today**
- Was the laptop on (or opened) that day and were you logged into Windows?
- Open **Task Scheduler**, find **TikTok Streak**, and check *Last Run Result*.
- Read `streak.log`.

**The installer says Python failed**
Install Python from <https://www.python.org/downloads/>, tick **"Add python.exe to PATH"**, then run the install command again.

**The PC crashed / blue-screened while the bot ran**
The bot itself can't crash Windows, but a buggy graphics driver can. The bot already runs its browser with the GPU disabled. Update your graphics drivers (AMD / NVIDIA / Intel) from the manufacturer's website.

## 9. Update
Run the install command again:
```powershell
irm https://raw.githubusercontent.com/enNeF/tiktok-streak/main/install.ps1 | iex
```
Your login, friends and settings are kept. Answer **N** when it asks to log in or edit again.

## 10. Uninstall
```powershell
cd $env:USERPROFILE\tiktok-streak; .\setup_task.ps1 -Remove; cd ..; Remove-Item -Recurse -Force tiktok-streak
```

## 11. Privacy & safety
- **Never share your `tiktok-streak` folder.** The `profile` folder inside it holds your logged-in TikTok session; anyone with it is logged into your account. Share **this GitHub link** instead.
- Your password is never saved by this tool. You type it into TikTok's own login page.
- Your friend list, logs and session stay on your PC. The only thing sent anywhere else is the alert text to ntfy.sh (and only if you set a topic).

---

### How it works (for the curious)
`streak.py` uses [Playwright](https://playwright.dev/python/) to open `tiktok.com/messages` in a private Chromium profile, finds each friend in the chat list, checks the chat header, types the message and presses Enter, then checks that the message box emptied (meaning TikTok accepted it). `state.json` remembers who was messaged today, so running twice never double-sends. Windows Task Scheduler starts it daily with *"run as soon as possible after a missed start"* turned on.
