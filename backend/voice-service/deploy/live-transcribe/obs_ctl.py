#!/usr/bin/env python3
"""Управление OBS на маке через obs-websocket v5. Запускается НА МАКЕ:

    ssh mac-work "python3 - status" < obs_ctl.py

Зачем: 28.10 запись 1:1 осталась включённой и писала 12 часов (15 ГБ), потому
что «остановить» было только глазами и руками. Теперь состояние записи
спрашивается машиной, а забытая запись останавливается командой.

Команды:
    status            — идёт ли запись, сколько уже, какой файл
    start             — начать запись (если уже идёт — скажет и не тронет)
    stop              — остановить (печатает путь готового файла)
    windows <источник> — список окон, доступных источнику захвата
    window <источник> <подстрока> — навести источник на окно по заголовку

Пароль берётся из конфига плагина, в аргументах и в логах не светится.
Соединение только с 127.0.0.1: наружу порт 4455 открывать незачем.
"""
import base64
import hashlib
import json
import os
import sys

try:
    import websocket  # websocket-client, на маке уже стоит
except ImportError:
    sys.exit("нет websocket-client: python3 -m pip install --user websocket-client")

CONFIG = os.path.expanduser(
    "~/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json")


def connect():
    cfg = json.load(open(CONFIG))
    if not cfg.get("server_enabled"):
        sys.exit("сервер WebSocket в OBS выключен: Tools → WebSocket Server Settings")
    ws = websocket.create_connection(
        f"ws://127.0.0.1:{cfg.get('server_port', 4455)}", timeout=10)
    hello = json.loads(ws.recv())["d"]
    ident = {"rpcVersion": 1}
    auth = hello.get("authentication")
    if auth:
        secret = base64.b64encode(hashlib.sha256(
            (cfg["server_password"] + auth["salt"]).encode()).digest())
        ident["authentication"] = base64.b64encode(hashlib.sha256(
            secret + auth["challenge"].encode()).digest()).decode()
    ws.send(json.dumps({"op": 1, "d": ident}))
    if json.loads(ws.recv())["op"] != 2:
        sys.exit("OBS не принял подключение (пароль?)")
    return ws


def call(ws, request, data=None):
    ws.send(json.dumps({"op": 6, "d": {
        "requestType": request, "requestId": "1", "requestData": data or {}}}))
    while True:
        msg = json.loads(ws.recv())
        if msg["op"] == 7:                      # события по пути игнорируем
            d = msg["d"]
            if not d["requestStatus"]["result"]:
                sys.exit(f"{request}: {d['requestStatus'].get('comment', 'отказ')}")
            return d.get("responseData") or {}


def hhmmss(ms):
    s = int(ms // 1000)
    return f"{s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}"


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    ws = connect()

    if cmd == "status":
        r = call(ws, "GetRecordStatus")
        if r["outputActive"]:
            # Размер нужен в выводе: забытая запись видна именно по нему.
            print(f"запись ИДЁТ {hhmmss(r['outputDuration'])}, "
                  f"{r.get('outputBytes', 0) / 1e9:.2f} ГБ")
        else:
            print("запись не идёт")

    elif cmd == "start":
        if call(ws, "GetRecordStatus")["outputActive"]:
            sys.exit("запись уже идёт — не трогаю (сначала stop)")
        call(ws, "StartRecord")
        print("запись начата")

    elif cmd == "stop":
        if not call(ws, "GetRecordStatus")["outputActive"]:
            print("записи и не было")
            return
        print("остановлена:", call(ws, "StopRecord").get("outputPath", "?"))

    elif cmd == "windows":
        src = sys.argv[2]
        items = call(ws, "GetInputPropertiesListPropertyItems",
                     {"inputName": src, "propertyName": "window"})["propertyItems"]
        for it in items:
            print(it["itemName"])

    elif cmd == "window":
        src, needle = sys.argv[2], sys.argv[3].lower()
        items = call(ws, "GetInputPropertiesListPropertyItems",
                     {"inputName": src, "propertyName": "window"})["propertyItems"]
        hit = [i for i in items if needle in i["itemName"].lower()]
        if not hit:
            sys.exit(f"окно с «{needle}» не найдено; список — команда windows")
        # type=1 — режим «окно» у screen_capture. Без него источник останется
        # на экране целиком, и наведение выглядело бы сработавшим впустую.
        call(ws, "SetInputSettings", {"inputName": src, "inputSettings": {
            "window": hit[0]["itemValue"], "type": 1}})
        print("источник наведён на:", hit[0]["itemName"])

    elif cmd == "inputs":
        for i in call(ws, "GetInputList")["inputs"]:
            print(f"{i['inputName']}  ({i['inputKind']})")

    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
