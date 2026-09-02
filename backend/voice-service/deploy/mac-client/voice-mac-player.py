#!/usr/bin/env python3
"""Проигрывает на mac-home ответы, которые VDS кладёт в /srv/voice-out/.

Зачем отдельный демон, а не ssh + afplay: из ssh-сессии CoreAudio недоступен
(`AudioQueueStart failed -66681`), а `launchctl asuser` упирается в
заблокированный экран. Работает только процесс, живущий внутри графической
сессии — отсюда LaunchAgent.

Опрашивает листинг Caddy, берёт новые файлы своего client_id и играет.
При старте ставит отметку на текущий момент, чтобы не проигрывать архив.

    ./voice-mac-player.py                  # client_id по умолчанию mac-home
    VOICE_CLIENT_ID=phone ./voice-mac-player.py
"""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

BASE = os.environ.get("VOICE_OUT_URL", "https://cashflow-game.ru/voice-out/")
CLIENT_ID = os.environ.get("VOICE_CLIENT_ID", "mac-home")
POLL_S = float(os.environ.get("VOICE_POLL_S", "2"))
STATE = os.path.expanduser("~/.voice-agent-mac/player-watermark.txt")


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


# Резолвер внутри LaunchAgent отвечает через раз: сам DNS исправен (dig и
# dscacheutil отдают адрес мгновенно, роутер пингуется за 0.7 мс), но
# getaddrinfo в этом контексте регулярно возвращает "nodename nor servname".
# Кэшируем удачный ответ и переиспользуем — имя в URL остаётся прежним, так
# что SNI и проверка сертификата не ломаются.
_dns_cache = {}
_real_getaddrinfo = socket.getaddrinfo


def _cached_getaddrinfo(host, port, *args, **kwargs):
    key = (host, port)
    try:
        res = _real_getaddrinfo(host, port, *args, **kwargs)
        _dns_cache[key] = res
        return res
    except socket.gaierror:
        if key in _dns_cache:
            return _dns_cache[key]
        raise


socket.getaddrinfo = _cached_getaddrinfo


def listing():
    # Caddy отдаёт каталог как HTML и переключается на JSON только по этому
    # заголовку. Без него прилетает страница и парсер падает на первой строке.
    req = urllib.request.Request(BASE, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read()


def entries_for_me(items):
    """(ts, json_name) наших записей, отсортированы по времени."""
    out = []
    for it in items:
        name = it.get("name", "")
        if it.get("is_dir") or not name.endswith(".json"):
            continue
        if not name.startswith(CLIENT_ID + "-"):
            continue
        ts = name[len(CLIENT_ID) + 1:-len(".json")]
        out.append((ts, name))
    out.sort()
    return out


def read_watermark():
    try:
        return open(STATE).read().strip()
    except Exception:
        return ""


def write_watermark(ts):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(ts)
    os.replace(tmp, STATE)


def play(meta_name):
    meta = json.loads(fetch(BASE + meta_name).decode())
    audio_url = meta.get("audio_url")
    if not audio_url:
        log(f"нет audio_url в {meta_name}, пропускаю")
        return
    # audio_url приходит абсолютным путём вида /voice-out/xxx.mp3
    url = BASE.rstrip("/").rsplit("/voice-out", 1)[0] + audio_url
    data = fetch(url)
    tmp = f"/tmp/voice-mac-play-{os.getpid()}.mp3"
    with open(tmp, "wb") as fh:
        fh.write(data)
    text = (meta.get("text") or "")[:60]
    log(f"играю {len(data)}B | {text}")
    subprocess.run(["/usr/bin/afplay", tmp], check=False)
    try:
        os.unlink(tmp)
    except OSError:
        pass


def main():
    log(f"старт: client_id={CLIENT_ID} url={BASE}")

    # Отметка при первом запуске — самый свежий файл на сервере. Иначе демон
    # проиграл бы весь архив ответов подряд.
    mark = read_watermark()
    if not mark:
        try:
            items = entries_for_me(listing())
            mark = items[-1][0] if items else ""
        except Exception as e:
            log(f"не смог прочитать листинг на старте: {e}")
            mark = ""
        write_watermark(mark)
        log(f"отметка выставлена на {mark or '(пусто)'}")

    misses = 0
    while True:
        try:
            for ts, name in entries_for_me(listing()):
                if ts <= mark:
                    continue
                play(name)
                mark = ts
                write_watermark(mark)
            misses = 0
        except Exception as e:
            # Сеть моргнула или VDS перезапускается — не падаем.
            # Домашний резолвер (MikroTik) залипает кластерами: в первом же
            # прогоне 13 ошибок из 28 строк лога, и ответ уезжал на 8 секунд,
            # потому что после каждой ошибки ждали полный интервал. Теперь
            # первые попытки повторяем почти сразу, и только если не отпускает
            # надолго — переходим на обычный интервал, чтобы не долбить сеть.
            misses += 1
            log(f"ошибка опроса ({misses}): {e}")
            time.sleep(0.3 if misses <= 10 else POLL_S)
            continue
        time.sleep(POLL_S)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
