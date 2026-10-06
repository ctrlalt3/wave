#!/usr/bin/env python3
"""Reproduce las comprobaciones de spotify-viability-findings.md.

No forma parte del servicio. Es la herramienta del paso 1 del plan:
medir si el trackList del embed de Spotify tiene tope.

Uso:
    python3 specs/research/verify_providers.py                 # todas las pruebas
    python3 specs/research/verify_providers.py --spotify URL   # solo contar tracks
    python3 specs/research/verify_providers.py --match "query" --ms 85400
"""

import argparse
import json
import re
import sys

import requests

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
TIMEOUT = 20

DEMO_ALBUM = "https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy"
DEMO_PLAYLISTS = [
    "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M",
    "https://open.spotify.com/playlist/37i9dQZEVXbMDoHDwVN2tF",
]


def check_connectivity():
    print("== 1. Conectividad ==")
    targets = [
        ("GET", "https://open.spotify.com/", None),
        ("GET", "https://api.spotify.com/v1/albums/4aawyAB9vmqN3uQ7FjRGTy", None),
        ("POST", "https://accounts.spotify.com/api/token",
         {"grant_type": "client_credentials", "client_id": "x", "client_secret": "x"}),
        ("GET", "https://music.youtube.com/", None),
        ("GET", "https://soundcloud.com/", None),
    ]
    for method, url, data in targets:
        try:
            r = requests.request(method, url, data=data, headers=UA, timeout=TIMEOUT)
            note = ""
            if r.status_code == 403 and "spotify.com" in url:
                note = "  <- bloqueo por IP de datacenter, no es auth"
            print(f"  {r.status_code}  {method:4} {url}{note}")
        except Exception as exc:
            print(f"  ERR  {method:4} {url}  {type(exc).__name__}: {exc}")


def parse_spotify_url(url):
    """open.spotify.com/[intl-xx/]<kind>/<id> o spotify:<kind>:<id> -> (kind, id)."""
    m = re.match(r"spotify:(track|album|playlist):([A-Za-z0-9]+)", url.strip())
    if m:
        return m.group(1), m.group(2)
    m = re.search(r"open\.spotify\.com/(?:intl-[a-z]{2}/)?(track|album|playlist)/([A-Za-z0-9]+)", url)
    if m:
        return m.group(1), m.group(2)
    return None, None


def spotify_entity(url):
    """Metadata via el embed del web player. Sin credenciales."""
    kind, sid = parse_spotify_url(url)
    if not kind:
        raise ValueError(f"URL de Spotify no reconocida: {url}")
    r = requests.get(f"https://open.spotify.com/embed/{kind}/{sid}", headers=UA, timeout=TIMEOUT)
    r.raise_for_status()
    m = re.search(
        r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', r.text, re.S
    )
    if not m:
        raise RuntimeError("spotify_parse_failed: no aparece __NEXT_DATA__")
    return json.loads(m.group(1))["props"]["pageProps"]["state"]["data"]["entity"]


def check_spotify(urls):
    print("== 2. Embed de Spotify ==")
    for url in urls:
        try:
            ent = spotify_entity(url)
            tracks = ent.get("trackList", [])
            print(f"  {ent.get('type'):8} {ent.get('name')!r}: {len(tracks)} tracks")
            if len(tracks) in (50, 100):
                print("         ^ OJO: cifra redonda, puede ser tope del embed. "
                       "Contrastar con el numero real en la app de Spotify.")
            if tracks:
                t = tracks[0]
                print(f"         ej: {t.get('title')!r} / {t.get('subtitle')!r} "
                      f"/ {t.get('duration')} ms")
        except Exception as exc:
            print(f"  ERR  {url}  {type(exc).__name__}: {exc}")


def sc_client_id():
    """Scrapea el client_id del web player. El bundle cambia en cada deploy."""
    html = requests.get("https://soundcloud.com/discover", headers=UA, timeout=TIMEOUT).text
    scripts = re.findall(r'<script[^>]+src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"', html)
    for src in reversed(scripts):
        js = requests.get(src, headers=UA, timeout=TIMEOUT).text
        m = re.search(r'client_id\s*[:=]\s*"([a-zA-Z0-9]{20,})"', js)
        if m:
            return m.group(1), src.rsplit("/", 1)[-1], len(scripts)
    raise RuntimeError("no se encontro client_id en ningun bundle")


def check_match(query, target_ms, tolerance_ms=15000):
    print("== 3. Busqueda y matching en SoundCloud ==")
    try:
        cid, bundle, total = sc_client_id()
        print(f"  client_id: {cid[:6]}... (de {bundle}, {total} bundles inspeccionados)")
    except Exception as exc:
        print(f"  ERR client_id: {type(exc).__name__}: {exc}")
        return

    r = requests.get(
        "https://api-v2.soundcloud.com/search/tracks",
        params={"q": query, "limit": 8, "client_id": cid},
        headers=UA, timeout=TIMEOUT,
    )
    print(f"  search HTTP {r.status_code} para {query!r} (objetivo {target_ms} ms)")
    if not r.ok:
        return
    for t in r.json().get("collection", [])[:5]:
        dur = t.get("duration") or 0
        delta = abs(dur - target_ms)
        ok = "OK " if delta <= tolerance_ms else "no "
        print(f"    {ok} {dur:>7} ms (delta {delta:>7}) {t.get('title')!r} "
              f"/ {(t.get('user') or {}).get('username')}")
    print(f"  (tolerancia {tolerance_ms} ms; los 'no' son previews de 30 s o remixes)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spotify", action="append", metavar="URL",
                    help="cuenta tracks de esta URL (repetible)")
    ap.add_argument("--match", metavar="QUERY", help="busca este texto en SoundCloud")
    ap.add_argument("--ms", type=int, default=85400, help="duracion objetivo para --match")
    args = ap.parse_args()

    if args.spotify:
        check_spotify(args.spotify)
    elif args.match:
        check_match(args.match, args.ms)
    else:
        check_connectivity()
        print()
        check_spotify([DEMO_ALBUM] + DEMO_PLAYLISTS)
        print()
        check_match("Pitbull Global Warming Sensato", 85400)
    return 0


if __name__ == "__main__":
    sys.exit(main())
