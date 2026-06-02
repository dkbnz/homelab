"""Discord bot for the Minecraft server (CT 102).

Commands (in ALLOWED_CHANNEL_ID):
  !invite <username>   add a player to the whitelist (whitelist add via rcon)
  !who                 list whitelisted players
  !help                usage

Access log: tails the server log and posts join/leave events to LOG_CHANNEL_ID
(defaults to ALLOWED_CHANNEL_ID). Log file mounted read-only at /logs/latest.log.

Config via env: DISCORD_TOKEN, RCON_HOST, RCON_PORT, RCON_PASSWORD,
ALLOWED_CHANNEL_ID, LOG_CHANNEL_ID (optional), LOG_FILE (default /logs/latest.log).
"""
import os
import re
import time
import asyncio
import discord
from mcrcon import MCRcon

TOKEN = os.environ["DISCORD_TOKEN"]
RCON_HOST = os.environ.get("RCON_HOST", "127.0.0.1")
RCON_PORT = int(os.environ.get("RCON_PORT", "25575"))
RCON_PASS = os.environ["RCON_PASSWORD"]
ALLOWED_CHANNEL = os.environ.get("ALLOWED_CHANNEL_ID", "").strip()
LOG_CHANNEL = os.environ.get("LOG_CHANNEL_ID", "").strip() or ALLOWED_CHANNEL
LOG_FILE = os.environ.get("LOG_FILE", "/logs/latest.log")

NAME_RE = re.compile(r"^[A-Za-z0-9_]{3,16}$")
JOIN_RE = re.compile(r"\]: ([A-Za-z0-9_]{3,16}) joined the game")
LEFT_RE = re.compile(r"\]: ([A-Za-z0-9_]{3,16}) left the game")
DENY_RE = re.compile(r"name=([A-Za-z0-9_]{3,16}).*?not white-?listed", re.IGNORECASE)
TIME_RE = re.compile(r"\[(\d{2}:\d{2}:\d{2})")

DENY_COOLDOWN = 60      # seconds; suppress repeat denials from a reconnecting client
_last_deny = {}

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)


def rcon(cmd: str) -> str:
    with MCRcon(RCON_HOST, RCON_PASS, port=RCON_PORT) as m:
        return m.command(cmd)


@client.event
async def on_ready():
    print(f"[bot] online as {client.user}; cmd_channel={ALLOWED_CHANNEL or 'any'} "
          f"log_channel={LOG_CHANNEL or 'none'}", flush=True)


@client.event
async def on_message(msg: discord.Message):
    if msg.author.bot:
        return
    if ALLOWED_CHANNEL and str(msg.channel.id) != ALLOWED_CHANNEL:
        return
    content = msg.content.strip()

    if content.startswith("!invite"):
        name = content[len("!invite"):].strip()
        if not NAME_RE.match(name):
            await msg.reply("Usage: `!invite <username>` (3-16 chars, letters/numbers/underscore).")
            return
        try:
            res = rcon(f"whitelist add {name}")
            print(f"[invite] {msg.author} -> {name}: {res!r}", flush=True)
            await msg.reply(f"`{name}` — {res or 'added to the whitelist.'}")
        except Exception as e:
            await msg.reply(f"Failed to add `{name}`: {e}")
    elif content == "!who":
        try:
            await msg.reply(rcon("whitelist list") or "(empty)")
        except Exception as e:
            await msg.reply(f"Failed: {e}")
    elif content == "!help":
        await msg.reply("`!invite <username>` add a player. `!who` list whitelist.")


async def tail_access_log():
    """Poll the server log for join/leave lines and post them to LOG_CHANNEL."""
    await client.wait_until_ready()
    if not LOG_CHANNEL:
        return
    channel = client.get_channel(int(LOG_CHANNEL))
    if channel is None:
        print(f"[log] channel {LOG_CHANNEL} not found", flush=True)
        return

    pos = None      # byte offset; None until first stat (start at end, skip history)
    inode = None
    while not client.is_closed():
        try:
            st = os.stat(LOG_FILE)
            if pos is None:
                pos, inode = st.st_size, st.st_ino
            elif st.st_ino != inode or st.st_size < pos:   # rotated or truncated
                pos, inode = 0, st.st_ino
            with open(LOG_FILE, "r", errors="replace") as f:
                f.seek(pos)
                lines = f.readlines()
                pos = f.tell()
            for line in lines:
                m = JOIN_RE.search(line)
                if m:
                    t = TIME_RE.search(line)
                    await channel.send(f"🟢 **{m.group(1)}** joined" + (f" — {t.group(1)}" if t else ""))
                    continue
                m = LEFT_RE.search(line)
                if m:
                    t = TIME_RE.search(line)
                    await channel.send(f"🔴 **{m.group(1)}** left" + (f" — {t.group(1)}" if t else ""))
                    continue
                m = DENY_RE.search(line)
                if m:
                    name = m.group(1)
                    now = time.monotonic()
                    if now - _last_deny.get(name, 0) > DENY_COOLDOWN:
                        _last_deny[name] = now
                        await channel.send(
                            f"⛔ **{name}** tried to join but isn't whitelisted. "
                            f"`!invite {name}` to let them in.")
        except FileNotFoundError:
            pass
        except Exception as e:
            print(f"[log] tail error: {e}", flush=True)
        await asyncio.sleep(3)


async def main():
    async with client:
        client.loop.create_task(tail_access_log())
        await client.start(TOKEN)


asyncio.run(main())
