"""Discord bot for the Minecraft server (CT 102).

Commands (in ALLOWED_CHANNEL_ID):
  !invite <username>   add a player to the whitelist (whitelist add via rcon)
  !who                 list whitelisted players
  !help                usage
  /<command>           forward a raw command to the server console via rcon
                       (requires the Manage Server permission on Discord)

Access log: tails the server log and posts events to LOG_CHANNEL_ID (defaults to
ALLOWED_CHANNEL_ID). Log file mounted read-only at /logs/latest.log.
Events: join/leave, denied (not whitelisted), deaths, advancements,
server start/stop, watchdog stalls.

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

NAME = r"[A-Za-z0-9_]{3,16}"
NAME_RE = re.compile(rf"^{NAME}$")
JOIN_RE = re.compile(rf"\]: ({NAME}) joined the game")
LEFT_RE = re.compile(rf"\]: ({NAME}) left the game")
DENY_RE = re.compile(rf"name=({NAME}).*?not white-?listed", re.IGNORECASE)

# Significant events tailed from the server log. Death lines are a bare player
# name (no <chat> brackets) followed by a vanilla death phrase.
DEATH_PHRASES = (
    "was slain|was shot|was killed|was blown up|blew up|was struck by lightning|"
    "fell from|fell off|fell out|fell while|hit the ground|drowned|burned to death|"
    "went up in flames|walked into fire|tried to swim in lava|discovered the floor was lava|"
    "suffocated|starved to death|withered away|froze to death|was squashed|was poked|"
    "was impaled|experienced kinetic energy|went off with a bang|was skewered|died"
)
DEATH_RE = re.compile(rf"\]: ({NAME}) ({DEATH_PHRASES})")
ADVANCE_RE = re.compile(
    rf"\]: ({NAME}) has (made the advancement|reached the goal|completed the challenge) (\[.+\])")
START_RE = re.compile(r"\]: Done \([\d.]+s\)!")
STOP_RE = re.compile(r"\]: Stopping server")
WATCHDOG_RE = re.compile(r"Watchdog.*has not responded for (\d+) seconds")

DENY_COOLDOWN = 60      # seconds; suppress repeat denials from a reconnecting client
WATCHDOG_COOLDOWN = 300  # one stall warning per 5 min, not one per dump line
_last_deny = {}
_last_watchdog = 0.0

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)


def rcon(cmd: str) -> str:
    with MCRcon(RCON_HOST, RCON_PASS, port=RCON_PORT) as m:
        return m.command(cmd)


def strip_colour(s: str) -> str:
    """Drop Minecraft §-codes from rcon output."""
    return re.sub(r"§.", "", s)


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
        await msg.reply(
            "`!invite <username>` add a player. `!who` list whitelist.\n"
            "`/<command>` run a server command via rcon (Manage Server only), "
            "e.g. `/list`, `/time set day`.")
    elif content.startswith("/") and len(content) > 1:
        # Forward to the server console. Gated: rcon is op-level (op, stop,
        # whitelist remove), so require the Manage Server permission.
        perms = getattr(msg.author, "guild_permissions", None)
        if not (perms and perms.manage_guild):
            await msg.reply("No. `/` commands need the Manage Server permission.")
            return
        cmd = content[1:].strip()
        try:
            out = strip_colour(rcon(cmd)).strip() or "(no output)"
            if len(out) > 1900:
                out = out[:1900] + " …"
            print(f"[cmd] {msg.author}: /{cmd} -> {out[:120]!r}", flush=True)
            await msg.reply(f"```{out}```")
        except Exception as e:
            await msg.reply(f"Failed: {e}")


async def tail_access_log():
    """Poll the server log and post joins/leaves/denials + significant events."""
    global _last_watchdog
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
                # Discord-native timestamp: renders in each viewer's local TZ
                ts = f" — <t:{int(time.time())}:t>"
                m = JOIN_RE.search(line)
                if m:
                    await channel.send(f"🟢 **{m.group(1)}** joined{ts}")
                    continue
                m = LEFT_RE.search(line)
                if m:
                    await channel.send(f"🔴 **{m.group(1)}** left{ts}")
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
                    continue
                m = DEATH_RE.search(line)
                if m:
                    detail = line.split("]: ", 1)[-1].strip()
                    await channel.send(f"💀 {detail}{ts}")
                    continue
                m = ADVANCE_RE.search(line)
                if m:
                    await channel.send(
                        f"🏆 **{m.group(1)}** {m.group(2)} **{m.group(3)}**{ts}")
                    continue
                if START_RE.search(line):
                    await channel.send(f"✅ Server started{ts}")
                    continue
                if STOP_RE.search(line):
                    await channel.send(f"🛑 Server stopping{ts}")
                    continue
                m = WATCHDOG_RE.search(line)
                if m:
                    now = time.monotonic()
                    if now - _last_watchdog > WATCHDOG_COOLDOWN:
                        _last_watchdog = now
                        await channel.send(
                            f"⚠️ Server stalled (no tick for {m.group(1)}s){ts}")
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
