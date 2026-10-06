#!/usr/bin/env python3
# Touch-key LED hunt (ISSUES 22): blink every unclaimed candidate pin, one phase at a time, so a watcher can say
# which phase (if any) lights the Back/Recents keys. Run as root. Each GPIO is handed back as input + pull-down
# (its state before the test); maXTouch T19 DIR/OUT are written back to 0.
# Usage: blink.py [phase ...]   (default: all phases)
import fcntl, os, struct, subprocess, sys, time

def iowr(nr, size):
    return (3 << 30) | (size << 16) | (0xB4 << 8) | nr

GET_LINE, SET_CONFIG, SET_VALUES = iowr(0x07, 592), iowr(0x0D, 272), iowr(0x0F, 16)
F_INPUT, F_OUTPUT, F_PULL_DOWN = 1 << 2, 1 << 3, 1 << 9

def line_config(flags):
    return struct.pack("<QI20x240x", flags, 0)

def gpio_open(chip, offsets):
    req = bytearray(592)
    struct.pack_into(f"<{len(offsets)}I", req, 0, *offsets)
    req[256:256 + 8] = b"keyled\0\0"
    req[288:288 + 272] = line_config(F_OUTPUT)
    struct.pack_into("<I", req, 560, len(offsets))
    with open(f"/dev/gpiochip{chip}", "rb") as f:
        fcntl.ioctl(f.fileno(), GET_LINE, req, True)
    return struct.unpack_from("<i", req, 588)[0]

def gpio_set(fd, n, on):
    mask = (1 << n) - 1
    fcntl.ioctl(fd, SET_VALUES, bytearray(struct.pack("<QQ", mask if on else 0, mask)), True)

def gpio_release(fd):
    fcntl.ioctl(fd, SET_CONFIG, bytearray(line_config(F_INPUT | F_PULL_DOWN)), True)
    os.close(fd)

def mxt_write(reg, val):
    subprocess.run(["i2ctransfer", "-f", "-y", "3", f"w3@0x4a", hex(reg & 0xFF), hex(reg >> 8), hex(val)], check=True)

T19 = 0x055F            # CTRL REPORTMASK DIR INTPULLUP OUT WAKE
T19_DIR, T19_OUT = T19 + 2, T19 + 4
MXT_PINS = 0xFD         # every T19 bit except bit1 (configured as a reported input)

def notify(text):
    env = "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/10000/bus"
    subprocess.run(["sudo", "-u", "user", "env", env, "gdbus", "call", "--session", "--dest",
                    "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications",
                    "--method", "org.freedesktop.Notifications.Notify", "keyled", "0", "", "Key LED test",
                    text, "[]", "{}", "9000"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

PHASES = {
    "1": ("TLMM GPIO 9", lambda: ("gpio", 0, [9])),
    "2": ("TLMM GPIO 10", lambda: ("gpio", 0, [10])),
    "3": ("PM8916 GPIO 1-4", lambda: ("gpio", 2, [0, 1, 2, 3])),
    "4": ("maXTouch T19 GPIOs", lambda: ("mxt", None, None)),
    "5": ("TLMM GPIO 60", lambda: ("gpio", 0, [60])),   # key LED pin on grandmax / serranove (mainline DTs)
}

def run_phase(key, secs=10):
    name, spec = PHASES[key]
    kind, chip, offs = spec()
    print(f"{time.strftime('%H:%M:%S')} phase {key}: {name}", flush=True)
    notify(f"Phase {key}: {name} blinking now ({secs} s)")
    if kind == "gpio":
        fd = gpio_open(chip, offs)
        try:
            for i in range(secs * 2):
                gpio_set(fd, len(offs), i % 2 == 0)
                time.sleep(0.5)
        finally:
            gpio_release(fd)
    else:
        try:
            mxt_write(T19_OUT, 0)
            mxt_write(T19_DIR, MXT_PINS)
            for i in range(secs * 2):
                mxt_write(T19_OUT, MXT_PINS if i % 2 == 0 else 0)
                time.sleep(0.5)
        finally:
            mxt_write(T19_OUT, 0)
            mxt_write(T19_DIR, 0)
    time.sleep(2)

if __name__ == "__main__":
    keys = sys.argv[1:] or sorted(PHASES)
    notify("Watch the Back / Recents keys. Phases start in 20 s.")
    time.sleep(20)
    for k in keys:
        run_phase(k)
    notify("Key LED test done")
    print(f"{time.strftime('%H:%M:%S')} done", flush=True)
