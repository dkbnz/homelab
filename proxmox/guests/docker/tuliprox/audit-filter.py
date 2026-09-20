#!/usr/bin/env python3
"""Audit the tuliprox channel filter against the live provider catalogue.

Answers "is my filter cutting channels I actually want?" by applying the same
market regex tuliprox uses and printing a KEEP/DROP verdict for every category,
biggest dropped ones first.

Read-only: it calls the provider's player_api.php and nothing else. Safe to run
while tuliprox is up — it does not open a stream, so it does not consume the
provider's single connection slot.

    source /opt/jellystack/.env && python3 audit-filter.py
    python3 audit-filter.py --markets NZ,AU,US,UK,CA
    python3 audit-filter.py --show-kept
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter, defaultdict

DEFAULT_MARKETS = "NZ,AU,US,UK,CA"

# Categories worth a second look if they get dropped: likely-English markets and
# generic buckets that often hide English channels behind a non-country prefix.
SUSPECT = re.compile(
    r"\b(4K|8K|UHD|VIP|GOLD|HD|FHD|RAW|SPORT|NEWS|MOVIE|DOC|KIDS|ENTERTAIN|"
    r"GENERAL|PPV|EVENT|IE|IRE|ZA|IN|SG|PH)\b", re.I)


def api(base, user, pw, action):
    q = urllib.parse.urlencode({"username": user, "password": pw, "action": action})
    url = "%s/player_api.php?%s" % (base.rstrip("/"), q)
    req = urllib.request.Request(url, headers={"User-Agent": "VLC/3.0.20 LibVLC/3.0.20"})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode("utf-8", "replace")
    # tuliprox 3.3.0 emits trailing commas; the provider may too. Be tolerant.
    raw = re.sub(r",\s*([\]}])", r"\1", raw.strip())
    return json.loads(raw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--markets", default=DEFAULT_MARKETS,
                    help="comma-separated market prefixes (default: %s)" % DEFAULT_MARKETS)
    ap.add_argument("--show-kept", action="store_true", help="also list kept categories")
    ap.add_argument("--min", type=int, default=1,
                    help="only list dropped categories with at least N channels")
    args = ap.parse_args()

    base = os.environ.get("XTREAM_URL")
    user = os.environ.get("XTREAM_USERNAME")
    pw = os.environ.get("XTREAM_PASSWORD")
    if not (base and user and pw):
        sys.exit("Set XTREAM_URL, XTREAM_USERNAME, XTREAM_PASSWORD "
                 "(source /opt/jellystack/.env)")

    markets = [m.strip().upper() for m in args.markets.split(",") if m.strip()]
    # Mirrors the `wanted_markets` template in source.yml.
    market_re = re.compile(r"^\s*(%s)\s*[|:]" % "|".join(markets), re.I)
    sep_re = re.compile(r"^\s*[#=_-]+")

    info = api(base, user, pw, "get_account_info").get("user_info", {})
    print("provider: status=%s active_cons=%s max_connections=%s"
          % (info.get("status"), info.get("active_cons"), info.get("max_connections")))

    cats = {c["category_id"]: c["category_name"] for c in api(base, user, pw, "get_live_categories")}
    streams = api(base, user, pw, "get_live_streams")
    print("catalogue: %d live channels in %d categories\n" % (len(streams), len(cats)))

    kept_by_cat, dropped_by_cat = Counter(), Counter()
    sep = 0
    for s in streams:
        cat = cats.get(str(s.get("category_id")), "(uncategorised)")
        name = s.get("name", "")
        if sep_re.match(name):
            sep += 1
            continue
        if market_re.match(cat) or market_re.match(name):
            kept_by_cat[cat] += 1
        else:
            dropped_by_cat[cat] += 1

    kept, dropped = sum(kept_by_cat.values()), sum(dropped_by_cat.values())
    total = kept + dropped + sep
    print("markets: %s" % ", ".join(markets))
    print("  KEEP        %6d  (%.1f%%)" % (kept, 100.0 * kept / max(total, 1)))
    print("  drop        %6d" % dropped)
    print("  separators  %6d  (padding rows, never wanted)\n" % sep)

    # Per-market breakdown of what is kept, so you can see nothing is missing.
    per = defaultdict(int)
    for cat, n in kept_by_cat.items():
        m = market_re.match(cat)
        per[(m.group(1).upper() if m else "via title")] += n
    print("kept by market:")
    for k, v in sorted(per.items(), key=lambda kv: -kv[1]):
        print("  %-10s %6d" % (k, v))

    flagged = [(c, n) for c, n in dropped_by_cat.items() if SUSPECT.search(c) and n >= args.min]
    if flagged:
        print("\n*** DROPPED but possibly English — review these ***")
        for c, n in sorted(flagged, key=lambda kv: -kv[1])[:40]:
            print("  %6d  %s" % (n, c[:70]))
        print("  (widen --markets, or add an OR term to channel_lineup in source.yml)")

    print("\nlargest dropped categories:")
    for c, n in dropped_by_cat.most_common(25):
        if n >= args.min:
            print("  %6d  %s" % (n, c[:70]))

    if args.show_kept:
        print("\nkept categories:")
        for c, n in kept_by_cat.most_common():
            print("  %6d  %s" % (n, c[:70]))


if __name__ == "__main__":
    main()
