#!/usr/bin/env python3
"""Проигрывает на маке ответы, которые VDS кладёт в локальный inbox.

Зачем отдельный демон, а не ssh + afplay: из ssh-сессии CoreAudio недоступен
(`AudioQueueStart failed -66681`), а `launchctl asuser` упирается в
заблокированный экран. Работает только процесс, живущий внутри графической
сессии — отсюда LaunchAgent.

💣 До 2026-09-30 демон опрашивал ЛИСТИНГ каталога по HTTP. 23.09 листинг
выключили в Caddy ради приватности («имена файлов предсказуемы по датам») — и
звук умер МОЛЧА: 124 тысячи строк `ошибка опроса ... 404` в логе, но никто не
смотрит лог плеера, пока ждёт голос. Возвращать листинг нельзя, а гадать имена
файлов плеер не может.

Поэтому доставка перевёрнута: VDS сам кладёт mp3 в `~/.voice-agent-mac/inbox/`
по scp (`voice-mac-reply-both`), демон играет и удаляет. Ни листинга, ни
токенов, ни сети в плеере — значит и нечему отдавать 404. Побочно исчез опрос
раз в две секунды.

Если мак спал в момент ответа — scp не дошёл, файла нет, и это правильно:
голосовое уведомление ценно в момент действия, проигрывать его через час хуже,
чем не проигрывать.

    ./voice-mac-player.py
    VOICE_INBOX=~/some/dir ./voice-mac-player.py
"""
import os
import subprocess
import sys
import time

INBOX = os.path.expanduser(os.environ.get("VOICE_INBOX", "~/.voice-agent-mac/inbox"))
POLL_S = float(os.environ.get("VOICE_POLL_S", "1"))


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


def ready_files():
    """Готовые к проигрыванию mp3, в порядке имён (имена — timestamp'ы).

    Файл в процессе передачи scp уже видно в каталоге, поэтому играть его
    нельзя: afplay получит обрезанный поток. Признак завершённости — размер не
    менялся между двумя опросами; scp пишет непрерывно, пауза в секунду при
    100 КБ значит, что передача кончилась.
    """
    out = []
    for name in sorted(os.listdir(INBOX)):
        if not name.endswith(".mp3"):
            continue
        path = os.path.join(INBOX, name)
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size == 0:
            continue
        prev = _sizes.get(path)
        _sizes[path] = size
        if prev == size:
            out.append(path)
    return out


_sizes = {}


def play(path):
    size = os.path.getsize(path)
    log(f"играю {os.path.basename(path)} ({size}B)")
    subprocess.run(["/usr/bin/afplay", path], check=False)
    try:
        os.unlink(path)
    except OSError:
        pass
    _sizes.pop(path, None)


def main():
    os.makedirs(INBOX, exist_ok=True)
    log(f"старт: inbox={INBOX}")
    while True:
        try:
            for path in ready_files():
                play(path)
        except Exception as e:
            # Демон не имеет права умирать: его подъём требует графической
            # сессии, то есть человека за компьютером.
            log(f"ошибка: {e}")
        time.sleep(POLL_S)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
