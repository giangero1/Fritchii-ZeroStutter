#!/usr/bin/env python3
"""Capture candidate OoT v131072 guest state using the local NX2 debug server."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import socket
import struct
import time


GAME_ID = "0400486024DEC000"
# Fingerprints of the game's menu, ocarina display, ocarina play and loading pause getters.
GETTERS = (
    (0x340B780, 24, "eecd19373d6db0cce995392a38308c0f22427df935a51ccf106e98018fd937fd"),
    (0x32F8E90, 32, "13c6c962b1b38cbf48e73b3eb6bd1f025fffa38530231531b13f17a49e7ab15b"),
    (0x32F9020, 32, "58313aaedb6e348ccf4a7ad2846dcfe0edeca5de6397fdb6428609ebbce5eb42"),
    (0x32FD964, 32, "4d8f54b686962e7ec7c0d34861c0c5cb7b2bce87c05a005b0f536ec00e5b52ad"),
)
UI_MANAGER = 0x4E7CFA8
PLAYER_MANAGER = 0x4E97648
OCARINA_MANAGER_FIRST_VIRTUAL = 0x3299390
LOG_EPOCH = re.compile(r"^\[\s*([\d.]+)\] .*Debug server listening on 127\.0\.0\.1:(\d+),")


class GuestMemory:
    def __init__(self, requests):
        self.requests = requests
        self.sequence = 0

    def call(self, method, **params):
        self.sequence += 1
        request = {"id": self.sequence, "method": method, "params": params}
        self.requests.write(json.dumps(request).encode() + b"\n")
        self.requests.flush()
        response = self.requests.readline()
        if not response:
            raise EOFError("Emulator disconnected")
        reply = json.loads(response)
        if "error" in reply:
            raise RuntimeError(reply["error"])
        return reply["result"]

    def read(self, address, size):
        result = self.call("read_memory", address=hex(address), size=size)
        return bytes.fromhex(result["hex"])

    def pointer(self, address):
        return struct.unpack("<Q", self.read(address, 8))[0]

    def verify(self, status):
        if status["program_id"] != GAME_ID:
            raise RuntimeError("Expected Ocarina of Time v131072")
        main = int(self.call("oot_high_refresh")["main"], 16)
        for offset, length, expected in GETTERS:
            if not main or hashlib.sha256(self.read(main + offset, length)).hexdigest() != expected:
                raise RuntimeError(f"Unsupported OoT executable (getter at {offset:#x})")
        return main

    def sample(self, main):
        ui = self.pointer(main + UI_MANAGER)
        if not ui:
            return {"available": False}
        menu = self.read(ui + 0x52C, 0x14)
        result = {
            "available": True,
            "menu_slots": list(struct.unpack_from("<4i", menu)),
            "menu_flags": list(menu[16:]),
            "ocarina_play": None,
            "ocarina_display": None,
        }
        player = self.pointer(main + PLAYER_MANAGER)
        components = self.pointer(player + 0x1F0) if player else 0
        if components:
            count, entries = struct.unpack("<i4xQ", self.read(components + 0x50, 16))
            if count > 0x20 and entries:
                ocarina = self.pointer(entries + 0x100)
                vtable = self.pointer(ocarina) if ocarina else 0
                if vtable and self.pointer(vtable) == main + OCARINA_MANAGER_FIRST_VIRTUAL:
                    modes = self.read(ocarina + 0x230, 0x4C)
                    result["ocarina_play"] = struct.unpack_from("<i", modes)[0]
                    result["ocarina_display"] = struct.unpack_from("<i", modes, 0x48)[0]
        return result


def log_epoch(log, port):
    with log.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            event = LOG_EPOCH.match(line)
            if event and int(event[2]) == port:
                return float(event[1])
    raise RuntimeError("The log did not contain the matching debug server startup")


def capture(args):
    with (
        socket.create_connection(("127.0.0.1", args.port), timeout=3) as connection,
        connection.makefile("rwb") as requests,
    ):
        guest = GuestMemory(requests)
        start = time.monotonic()
        status = guest.call("status", fps_window_ms=0)
        log_offset = log_epoch(args.log, args.port) + status["uptime_s"]
        main = guest.verify(status)
        with args.output.open("x", encoding="utf-8", buffering=1) as output:
            print(f"Tracing OoT v131072 to {args.output}", flush=True)
            previous = None
            deadline = start + args.seconds
            while (sample_start := time.monotonic()) < deadline:
                try:
                    state = guest.sample(main)
                except RuntimeError:
                    # A guest object may disappear while the scene is being destroyed.
                    state = {"available": False}
                if state != previous:
                    row = {"log_seconds": round(log_offset + sample_start - start, 3), **state}
                    print(json.dumps(row), file=output)
                    previous = state
                time.sleep(max(0.0, 0.05 - (time.monotonic() - sample_start)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="eden_log.txt from the running emulator")
    parser.add_argument("output", type=Path, help="new JSONL capture file")
    parser.add_argument("--port", type=int, default=48723)
    parser.add_argument("--seconds", type=int, default=600)
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    try:
        capture(args)
    except (EOFError, KeyboardInterrupt):
        return
    except (OSError, RuntimeError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
