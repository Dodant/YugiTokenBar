#!/usr/bin/env python3
"""Fixture preparation and result checks for scripts/linux-smoke.sh and scripts/linux-scenarios.sh (stdlib only)."""
import datetime, json, os, shutil, struct, sys, zlib

FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tests", "Fixtures", "linux-smoke", "state.json")
TOKENS_PER_COIN = 10_000       # Balance.tokensPerCoin in Sources/YugiTokenBar/Game.swift
FIRST_RUN_ENTRIES = [(0, 250_000), (10, 500_000)]   # (days ago, tokens), inside Balance.firstRunCreditDays (14)
TODAY_TOKENS = 1_200_000          # also the fixture's claimed ledger, so nothing is credited
# The list is oldest first, so most of the sample sits in the oldest days to be visible without scrolling.
HISTORY_DAYS = {30: 2_400_000, 29: 900_000, 28: 1_500_000, 26: 300_000, 25: 1_800_000, 24: 600_000, 12: 1_200_000, 5: 150_000, 2: 900_000}


def fail(message):
    print("CHECK_FAIL", message)
    sys.exit(1)


def today():
    return datetime.date.today().isoformat()


def write_log(run, entries, name="synthetic"):
    """Claude Code JSONL under <run>/claude/projects/<project>/<session>.jsonl (the app gets CLAUDE_CONFIG_DIR=<run>/claude,
    because Foundation on Linux resolves the home directory from the passwd entry, not $HOME); entries = [(days_ago, input_tokens)]."""
    folder = os.path.join(run, "claude", "projects", "smoke")
    os.makedirs(folder, exist_ok=True)
    now = datetime.datetime.now(datetime.timezone.utc)
    with open(os.path.join(folder, name + ".jsonl"), "w") as out:
        for index, (days_ago, tokens) in enumerate(entries):
            when = (now - datetime.timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            out.write(json.dumps({"type": "assistant", "timestamp": when, "requestId": f"smoke-{index}",
                                  "message": {"id": f"msg-{index}", "model": "claude-opus-5-5",
                                              "usage": {"input_tokens": tokens, "output_tokens": 0}}}) + "\n")


def normalise(state):
    """Drop what legitimately differs between runs: the card log and today's ledger date."""
    state = json.loads(json.dumps(state))
    state.pop("log", None)
    if state.get("claimedDate") == today():
        state["claimedDate"] = "<today>"
    return state


def load_state(run):
    with open(os.path.join(run, "state", "state.json")) as handle:
        return json.load(handle)


def dump(path, value):
    with open(path, "w") as handle:
        json.dump(value, handle, indent=1, sort_keys=True)
        handle.write("\n")


def prepare(run, mode):
    for sub in ("home", "state", "config", "data", "cache"):
        os.makedirs(os.path.join(run, sub), exist_ok=True)
    if mode == "fixture":
        with open(FIXTURE) as handle:
            state = json.load(handle)
        if state["claimedByProvider"] != {"claude_code": TODAY_TOKENS}:
            fail("fixture ledger does not match the synthetic usage of today")
        state["claimedDate"] = today()   # a ledger exists, so no first-run credit fires
        dump(os.path.join(run, "state", "state.json"), state)
        write_log(run, [(0, TODAY_TOKENS)] + [(d, t) for d, t in HISTORY_DAYS.items()])
        dump(os.path.join(run, "initial-state.json"), normalise(state))
    elif mode == "first-run":
        write_log(run, FIRST_RUN_ENTRIES)
    else:
        fail("unknown prepare mode " + mode)


def read_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"{path} is not a PNG")
    pos, idat, header = 8, b"", None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, depth, color, _, _, interlace = header
    if depth != 8 or color not in (2, 6) or interlace:
        fail(f"{path}: unsupported PNG layout {header}")
    return width, height, 3 if color == 2 else 4, zlib.decompress(idat), len(data)


def check_png(path, expect=(1280, 1024)):
    width, height, bpp, raw, size = read_png(path)
    if (width, height) != expect:
        fail(f"{path}: size {width}x{height}, expected {expect[0]}x{expect[1]}")
    stride, prev, colours, dark = width * bpp, bytearray(width * bpp), set(), 0
    for row in range(height):
        base = row * (stride + 1)
        kind, line = raw[base], bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up, upleft = prev[i], prev[i - bpp] if i >= bpp else 0
            if kind == 1: line[i] = (line[i] + left) & 255
            elif kind == 2: line[i] = (line[i] + up) & 255
            elif kind == 3: line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - upleft
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upleft)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else upleft)) & 255
        if row % 4 == 0:
            for x in range(0, width, 2):
                colours.add(bytes(line[x * bpp:x * bpp + 3]))
        prev = line
    if size < 20_000 or len(colours) < 50:
        fail(f"{path}: looks blank ({size} bytes, {len(colours)} distinct colours sampled)")
    print(f"PNG_OK {path} {width}x{height} bytes={size} colours>={len(colours)}")


def verify(screen, run, out):
    check_png(os.path.join(out, screen + ".png"))
    initial = json.load(open(os.path.join(run, "initial-state.json")))
    final = normalise(load_state(run))
    dump(os.path.join(out, screen + "-state.json"), final)
    if screen == "open":
        copies = lambda s: sum(s["owned"].values())
        if final["coins"] >= initial["coins"]: fail(f"coins did not decrease: {initial['coins']} -> {final['coins']}")
        if final["coins"] != initial["coins"] - 1000: fail(f"expected exactly one pack bought, coins {initial['coins']} -> {final['coins']}")
        if copies(final) != copies(initial) + 5: fail(f"expected 5 more owned copies: {copies(initial)} -> {copies(final)}")
        if final["packStamp"] != initial["packStamp"] + 1: fail("packStamp did not advance by one")
    elif final != initial:
        diff = {k: (initial.get(k), final.get(k)) for k in set(initial) | set(final) if initial.get(k) != final.get(k)}
        fail(f"{screen}: state changed during a view-only run: {diff}")
    print(f"STATE_OK {screen} coins={final['coins']} copies={sum(final['owned'].values())}")


def main(argv):
    cmd = argv[1]
    if cmd == "prepare": prepare(argv[2], argv[3])
    elif cmd == "png": check_png(argv[2])
    elif cmd == "verify": verify(argv[2], argv[3], argv[4])
    elif cmd == "state":
        dump(argv[3], normalise(load_state(argv[2])))
    elif cmd == "expect-first-run":
        state = load_state(argv[2])
        dump(argv[3], normalise(state))
        total = sum(tokens for _, tokens in FIRST_RUN_ENTRIES)
        if (state["coins"], state["coinRemainder"]) != divmod(total, TOKENS_PER_COIN):
            fail(f"expected {divmod(total, TOKENS_PER_COIN)} coins and remainder, got {state['coins']} (+{state['coinRemainder']})")
        if not state.get("claimedDate"): fail("no usage ledger was written")
        print(f"FIRST_RUN_OK coins={state['coins']} claimedDate={state['claimedDate']} claimed={state['claimedByProvider']}")
    elif cmd == "expect":   # expect <run> <key> <value-json>
        state = load_state(argv[2])
        if state.get(argv[3]) != json.loads(argv[4]): fail(f"{argv[3]} = {state.get(argv[3])!r}, expected {argv[4]}")
        print(f"EXPECT_OK {argv[3]}={argv[4]}")
    else:
        fail("unknown command " + cmd)


if __name__ == "__main__":
    main(sys.argv)
