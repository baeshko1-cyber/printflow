#!/usr/bin/env python3
"""
Yandex Music Playlist Downloader
Скачивает плейлист с Яндекс Музыки в папку для записи на флешку.

Как получить токен:
  1. Откройте браузер и войдите в Яндекс
  2. Перейдите по ссылке:
     https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d
  3. Разрешите доступ — в адресной строке появится ваш токен (access_token=...)
  4. Скопируйте токен и передайте через --token или переменную YANDEX_TOKEN
"""

import os
import re
import sys
import time
import hashlib
import argparse
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlencode

import requests
from tqdm import tqdm

BASE_URL = "https://api.music.yandex.net"


def sanitize_filename(name: str) -> str:
    name = re.sub(r'[\\/:*?"<>|]', "_", name)
    return name.strip()[:200]


class YandexMusicClient:
    def __init__(self, token: str):
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"OAuth {token}",
            "X-Yandex-Music-Client": "YandexMusicAndroid/23020251",
        })
        self._uid = None

    def _get(self, path: str, **params) -> dict:
        resp = self.session.get(f"{BASE_URL}{path}", params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if data.get("error"):
            raise RuntimeError(f"API error: {data['error']}")
        return data.get("result", data)

    @property
    def uid(self) -> str:
        if not self._uid:
            info = self._get("/account/status")
            self._uid = str(info["account"]["uid"])
        return self._uid

    def list_playlists(self) -> list[dict]:
        return self._get(f"/users/{self.uid}/playlists/list")

    def get_playlist(self, kind: int) -> dict:
        return self._get(
            f"/users/{self.uid}/playlists/{kind}",
            rich_tracks="true",
        )

    def get_download_info(self, track_id: int) -> list[dict]:
        return self._get(f"/tracks/{track_id}/download-info")

    def get_direct_url(self, info: dict) -> str:
        """Получает прямую ссылку на файл через XML."""
        resp = self.session.get(info["downloadInfoUrl"] + "&format=json", timeout=15)
        if resp.ok and resp.headers.get("content-type", "").startswith("application/json"):
            j = resp.json()
            host = j["host"]
            path = j["path"]
            ts = j["ts"]
            s = j["s"]
            sign = hashlib.md5(("XGRlBW9FXlekgbPrRHuSiA" + path[1:] + s).encode()).hexdigest()
            return f"https://{host}/get-mp3/{sign}/{ts}{path}"
        # fallback: XML
        resp = self.session.get(info["downloadInfoUrl"], timeout=15)
        resp.raise_for_status()
        root = ET.fromstring(resp.content)
        ns = {"d": "http://www.yandex.ru/music/download-info"}
        host = root.find("d:host", ns).text
        path = root.find("d:path", ns).text
        ts = root.find("d:ts", ns).text
        s = root.find("d:s", ns).text
        sign = hashlib.md5(("XGRlBW9FXlekgbPrRHuSiA" + path[1:] + s).encode()).hexdigest()
        return f"https://{host}/get-mp3/{sign}/{ts}{path}"

    def best_download_info(self, track_id: int, codec: str = "mp3") -> dict | None:
        """Выбирает лучший вариант скачивания (по битрейту)."""
        try:
            infos = self.get_download_info(track_id)
        except Exception:
            return None
        candidates = [i for i in infos if i.get("codec") == codec]
        if not candidates:
            candidates = infos
        return max(candidates, key=lambda x: x.get("bitrateInKbps", 0), default=None)


def download_file(session: requests.Session, url: str, dest: Path, desc: str) -> bool:
    try:
        resp = session.get(url, stream=True, timeout=60)
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        with open(dest, "wb") as f, tqdm(
            total=total, unit="B", unit_scale=True, desc=desc[:40], leave=False
        ) as bar:
            for chunk in resp.iter_content(chunk_size=65536):
                f.write(chunk)
                bar.update(len(chunk))
        return True
    except Exception as e:
        print(f"  [!] Ошибка загрузки: {e}")
        if dest.exists():
            dest.unlink()
        return False


def choose_playlist(client: YandexMusicClient, kind_arg: str | None) -> dict:
    playlists = client.list_playlists()
    if not playlists:
        print("Плейлисты не найдены.")
        sys.exit(1)

    if kind_arg is not None:
        for pl in playlists:
            if str(pl["kind"]) == kind_arg:
                return pl
        print(f"Плейлист с kind={kind_arg} не найден.")
        sys.exit(1)

    print("\nВаши плейлисты:")
    for i, pl in enumerate(playlists, 1):
        count = pl.get("trackCount", "?")
        print(f"  {i:2}. [{pl['kind']}] {pl['title']}  ({count} треков)")

    print()
    choice = input("Введите номер плейлиста: ").strip()
    try:
        idx = int(choice) - 1
        return playlists[idx]
    except (ValueError, IndexError):
        print("Неверный выбор.")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Скачать плейлист с Яндекс Музыки",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--token", help="OAuth-токен Яндекс Музыки")
    parser.add_argument("--kind", help="Номер (kind) плейлиста (оставьте пустым для выбора из списка)")
    parser.add_argument(
        "--output", "-o",
        default="./music",
        help="Папка для сохранения (по умолчанию: ./music)",
    )
    parser.add_argument(
        "--codec",
        default="mp3",
        choices=["mp3", "aac"],
        help="Формат аудио (default: mp3)",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        default=True,
        help="Пропускать уже скачанные файлы (default: True)",
    )
    args = parser.parse_args()

    token = args.token or os.environ.get("YANDEX_TOKEN")
    if not token:
        print("Укажите токен через --token или переменную окружения YANDEX_TOKEN.")
        print()
        print("Как получить токен:")
        print("  1. Войдите в Яндекс в браузере")
        print("  2. Перейдите по ссылке:")
        print("     https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d")
        print("  3. Разрешите доступ")
        print("  4. Скопируйте access_token из адресной строки")
        sys.exit(1)

    client = YandexMusicClient(token)

    print("Подключение к Яндекс Музыке...")
    try:
        uid = client.uid
        print(f"Авторизован (uid={uid})")
    except Exception as e:
        print(f"Ошибка авторизации: {e}")
        sys.exit(1)

    playlist_meta = choose_playlist(client, args.kind)
    print(f"\nЗагружаю плейлист «{playlist_meta['title']}»...")

    playlist = client.get_playlist(playlist_meta["kind"])
    tracks = playlist.get("tracks", [])
    if not tracks:
        print("Плейлист пустой.")
        sys.exit(0)

    # Папка вывода: ./music/<Название плейлиста>/
    output_dir = Path(args.output) / sanitize_filename(playlist_meta["title"])
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Сохраняю в: {output_dir.resolve()}")
    print(f"Треков в плейлисте: {len(tracks)}\n")

    ok = skipped = failed = 0

    for idx, track_entry in enumerate(tracks, 1):
        # Структура может быть {track: {...}} или напрямую {...}
        track = track_entry.get("track") or track_entry
        track_id = track.get("id")
        if not track_id:
            failed += 1
            continue

        artists = ", ".join(a.get("name", "") for a in track.get("artists", []))
        title = track.get("title", "Unknown")
        display = f"{artists} — {title}" if artists else title
        filename = sanitize_filename(f"{idx:03d}. {display}.mp3")
        dest = output_dir / filename

        print(f"[{idx}/{len(tracks)}] {display}")

        if args.skip_existing and dest.exists() and dest.stat().st_size > 0:
            print("  пропущен (уже скачан)")
            skipped += 1
            continue

        # Получаем ссылку для скачивания
        info = client.best_download_info(track_id, args.codec)
        if not info:
            print("  [!] Нет доступной ссылки (трек недоступен или нет подписки)")
            failed += 1
            continue

        try:
            url = client.get_direct_url(info)
        except Exception as e:
            print(f"  [!] Не удалось получить ссылку: {e}")
            failed += 1
            continue

        success = download_file(client.session, url, dest, display)
        if success:
            ok += 1
        else:
            failed += 1

        # небольшая пауза чтобы не перегружать API
        time.sleep(0.3)

    print(f"\n{'='*50}")
    print(f"Готово! Скачано: {ok}, пропущено: {skipped}, ошибок: {failed}")
    print(f"Файлы находятся в: {output_dir.resolve()}")
    if failed:
        print("Треки с ошибками могут требовать активной подписки Яндекс Музыки.")
