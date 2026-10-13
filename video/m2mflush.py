#!/usr/bin/env python3
# m2mflush.py <file.h264> [output|both] [cycles] [hold] — raw V4L2 stateful-decoder test of a seek on the Venus decoder
# (ISSUES 23 freeze, kernel 0129 gate). Decodes 40 frames, then repeats <cycles> times: keep the next <hold> decoded
# frames (like a compositor holding them), flush, requeue the held frames INSIDE the flush window, restart from the
# first IDR and decode 30 more frames. Flush modes:
#   output: FFmpeg's v4l2_decode_flush — STREAMOFF OUTPUT, (requeue), STREAMON OUTPUT, DECODER_CMD START; the
#           capture queue keeps streaming (the V4L2 stateful-decoder seek)
#   both:   GStreamer's seek — STREAMOFF OUTPUT + CAPTURE, (requeue), STREAMON CAPTURE, queue bitstream,
#           STREAMON OUTPUT
#   both-empty: the same, but STREAMON OUTPUT before any bitstream is queued
# Per cycle it prints the frames decoded, and which of the requeued capture buffers came back. A buffer that never
# comes back is stranded in the driver; once all are, decoding stops (STALL).
# Input: an Annex-B stream, e.g. ffmpeg -i clip.mp4 -c:v copy -bsf:v h264_mp4toannexb -an -frames:v 400 -f h264 x.h264
import ctypes as C
import errno
import fcntl
import glob
import mmap
import os
import select
import sys
import time

u8, u32, s32 = C.c_uint8, C.c_uint32, C.c_int32
CAP, OUT, MMAP = 9, 10, 1  # V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, _OUTPUT_MPLANE, V4L2_MEMORY_MMAP


def fourcc(s):
    return sum(ord(c) << (8 * i) for i, c in enumerate(s))


class PlanePix(C.Structure):
    _fields_ = [("sizeimage", u32), ("bytesperline", u32), ("reserved", C.c_uint16 * 6)]


class PixMp(C.Structure):
    _fields_ = [("width", u32), ("height", u32), ("pixelformat", u32), ("field", u32), ("colorspace", u32),
                ("plane_fmt", PlanePix * 8), ("num_planes", u8), ("flags", u8), ("ycbcr_enc", u8),
                ("quantization", u8), ("xfer_func", u8), ("reserved", u8 * 7)]


class FmtU(C.Union):
    _fields_ = [("pix_mp", PixMp), ("raw", u8 * 200), ("_align", C.c_void_p)]


class Format(C.Structure):
    _fields_ = [("type", u32), ("fmt", FmtU)]


class ReqBufs(C.Structure):
    _fields_ = [("count", u32), ("type", u32), ("memory", u32), ("capabilities", u32), ("flags", u8),
                ("reserved", u8 * 3)]


class PlaneM(C.Union):
    _fields_ = [("mem_offset", u32), ("userptr", C.c_ulong), ("fd", s32)]


class Plane(C.Structure):
    _fields_ = [("bytesused", u32), ("length", u32), ("m", PlaneM), ("data_offset", u32), ("reserved", u32 * 11)]


class Timeval(C.Structure):
    _fields_ = [("sec", C.c_long), ("usec", C.c_long)]


class Timecode(C.Structure):
    _fields_ = [("type", u32), ("flags", u32), ("frames", u8), ("seconds", u8), ("minutes", u8), ("hours", u8),
                ("userbits", u8 * 4)]


class BufM(C.Union):
    _fields_ = [("offset", u32), ("userptr", C.c_ulong), ("planes", C.POINTER(Plane)), ("fd", s32)]


class Buffer(C.Structure):
    _fields_ = [("index", u32), ("type", u32), ("bytesused", u32), ("flags", u32), ("field", u32),
                ("timestamp", Timeval), ("timecode", Timecode), ("sequence", u32), ("memory", u32), ("m", BufM),
                ("length", u32), ("reserved2", u32), ("request_fd", s32)]


class EventSub(C.Structure):
    _fields_ = [("type", u32), ("id", u32), ("flags", u32), ("reserved", u32 * 5)]


class EventU(C.Union):
    _fields_ = [("data", u8 * 64), ("_align", C.c_int64)]


class Timespec(C.Structure):
    _fields_ = [("sec", C.c_long), ("nsec", C.c_long)]


class Event(C.Structure):
    _fields_ = [("type", u32), ("u", EventU), ("pending", u32), ("sequence", u32), ("timestamp", Timespec),
                ("id", u32), ("reserved", u32 * 8)]


class DecCmdU(C.Union):
    _fields_ = [("raw", u32 * 16), ("_align", C.c_uint64)]


class DecCmd(C.Structure):
    _fields_ = [("cmd", u32), ("flags", u32), ("u", DecCmdU)]


class Control(C.Structure):
    _fields_ = [("id", u32), ("value", s32)]


assert (C.sizeof(Format), C.sizeof(Buffer), C.sizeof(Event), C.sizeof(DecCmd)) == (208, 88, 136, 72)


def ioc(d, nr, size):
    return (d << 30) | (size << 16) | (ord("V") << 8) | nr


G_FMT, S_FMT = ioc(3, 4, 208), ioc(3, 5, 208)
REQBUFS, QUERYBUF, QBUF, DQBUF = ioc(3, 8, 20), ioc(3, 9, 88), ioc(3, 15, 88), ioc(3, 17, 88)
STREAMON, STREAMOFF = ioc(1, 18, 4), ioc(1, 19, 4)
G_CTRL, DQEVENT, SUB_EVENT, DEC_CMD = ioc(3, 27, 8), ioc(2, 89, 136), ioc(1, 90, 32), ioc(3, 96, 72)
EV_EOS, EV_SRC = 2, 5

path = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else "output"
cycles = int(sys.argv[3]) if len(sys.argv) > 3 else 5
hold = int(sys.argv[4]) if len(sys.argv) > 4 else 4

# access units: a new one starts at an AUD/SEI/SPS/PPS or at a slice with first_mb_in_slice == 0 after a slice
data = open(path, "rb").read()
starts, i = [], 0
while (j := data.find(b"\x00\x00\x01", i)) >= 0:
    starts.append(j - 1 if j and data[j - 1] == 0 else j)
    i = j + 3
starts.append(len(data))
aus, cur, last_vcl = [], None, False
for a, b in zip(starts, starts[1:]):
    nal = data[a:b]
    h = nal.index(b"\x00\x00\x01") + 3
    t = nal[h] & 0x1F
    vcl = t in (1, 5)
    new = (t in (6, 7, 8, 9) and last_vcl) or (vcl and nal[h + 1] & 0x80 and last_vcl)
    if cur is None or new:
        cur = bytearray()
        aus.append(cur)
    cur += nal
    last_vcl = vcl
print(f"{len(aus)} access units from {path}")

dev = next(f"/dev/{p.split('/')[-2]}" for p in glob.glob("/sys/class/video4linux/video*/name")
           if open(p).read().strip() == "qcom-venus-decoder")
fd = os.open(dev, os.O_RDWR | os.O_NONBLOCK)


def xioctl(req, arg):
    while True:
        try:
            return fcntl.ioctl(fd, req, arg)
        except InterruptedError:
            continue


def stream(on, t):
    xioctl(STREAMON if on else STREAMOFF, C.c_int(t))


f = Format(type=OUT)
f.fmt.pix_mp.pixelformat, f.fmt.pix_mp.width, f.fmt.pix_mp.height = fourcc("H264"), 1920, 1080
f.fmt.pix_mp.num_planes, f.fmt.pix_mp.plane_fmt[0].sizeimage = 1, 1 << 20
xioctl(S_FMT, f)
for ev in (EV_SRC, EV_EOS):
    xioctl(SUB_EVENT, EventSub(type=ev))


def reqbufs(t, n):
    r = ReqBufs(count=n, type=t, memory=MMAP)
    xioctl(REQBUFS, r)
    return r.count


def buf(t, idx, planes):
    b = Buffer(index=idx, type=t, memory=MMAP, length=1)
    b.m.planes = C.cast(planes, C.POINTER(Plane))
    return b


nout = reqbufs(OUT, 8)
out_maps, out_free = [], []
for k in range(nout):
    pl = (Plane * 1)()
    xioctl(QUERYBUF, buf(OUT, k, pl))
    out_maps.append(mmap.mmap(fd, pl[0].length, offset=pl[0].m.mem_offset))
    out_free.append(k)

au_next = 0


def feed():
    global au_next
    while out_free:
        k = out_free.pop(0)
        au = aus[au_next % len(aus)]
        out_maps[k][:len(au)] = au
        pl = (Plane * 1)()
        pl[0].bytesused, pl[0].length = len(au), len(out_maps[k])
        b = buf(OUT, k, pl)
        b.timestamp.sec, b.timestamp.usec = au_next // 1000, au_next % 1000
        xioctl(QBUF, b)
        au_next += 1


feed()
stream(True, OUT)
ncap, cap_out, frames = 0, set(), 0  # cap_out: capture buffers we hold (dequeued, not requeued)


def setup_capture():
    global ncap
    g = Format(type=CAP)
    xioctl(G_FMT, g)
    c = Control(id=0x00980927)  # V4L2_CID_MIN_BUFFERS_FOR_CAPTURE
    try:
        xioctl(G_CTRL, c)
    except OSError:
        c.value = 4
    ncap = reqbufs(CAP, c.value + hold + 2)
    print(f"capture {g.fmt.pix_mp.width}x{g.fmt.pix_mp.height}, min {c.value}, {ncap} buffers")
    for k in range(ncap):
        qcap(k)
    stream(True, CAP)


def qcap(k):
    pl = (Plane * 1)()
    xioctl(QBUF, buf(CAP, k, pl))
    cap_out.discard(k)


def run(nframes, keep, timeout=5.0):
    """Decode until nframes more frames arrived; keep the last `keep` of them out. Returns (frames, indices)."""
    global frames
    got, seen, kept = 0, [], []
    p = select.poll()
    p.register(fd, select.POLLIN | select.POLLOUT | select.POLLPRI)
    t_end = time.monotonic() + timeout
    feed()  # after a flush nothing is queued on OUTPUT, and poll() has nothing to report until something is
    while got < nframes and time.monotonic() < t_end:
        if not p.poll(200):
            continue
        while True:  # events
            e = Event()
            try:
                xioctl(DQEVENT, e)
            except OSError as x:
                if x.errno in (errno.ENOENT, errno.EAGAIN):
                    break
                raise
            if e.type == EV_SRC and not ncap:
                setup_capture()
        for t in (OUT, CAP):
            while True:
                pl = (Plane * 1)()
                b = buf(t, 0, pl)
                try:
                    xioctl(DQBUF, b)
                except OSError as x:
                    if x.errno == errno.EAGAIN:
                        break
                    raise
                if t == OUT:
                    out_free.append(b.index)
                else:
                    got += 1
                    frames += 1
                    seen.append(b.index)
                    cap_out.add(b.index)
                    if got > nframes - keep:
                        kept.append(b.index)
                    else:
                        qcap(b.index)
        feed()
    return got, seen, kept


got, seen, _ = run(40, 0, timeout=10)
print(f"warm-up: {got} frames, capture indices {sorted(set(seen))}")
lost = set()
for c in range(1, cycles + 1):
    got, seen, kept = run(hold, hold)
    held = sorted(set(kept))
    if mode == "output":
        stream(False, OUT)
        for k in held:
            qcap(k)  # requeued INSIDE the window: codec_state SEEK, OUTPUT off, CAPTURE still streaming
        out_free[:] = list(range(nout))
        au_next = 0
        stream(True, OUT)
        try:
            xioctl(DEC_CMD, DecCmd(cmd=0))  # V4L2_DEC_CMD_START, as FFmpeg does
        except OSError as x:
            print(f"  DECODER_CMD START: {os.strerror(x.errno)}")
    else:
        stream(False, OUT)
        stream(False, CAP)
        cap_out.clear()
        for k in range(ncap):
            qcap(k)
        out_free[:] = list(range(nout))
        au_next = 0
        stream(True, CAP)
        if mode == "both":
            feed()  # GStreamer queues the first bitstream buffers before STREAMON OUTPUT
        stream(True, OUT)
    got, seen, _ = run(30, 0)
    back = sorted(set(held) & set(seen))
    lost = (lost | set(held)) - set(seen)
    state = "STALL" if got == 0 else ("short" if got < 30 else "ok")
    print(f"cycle {c} ({mode}): held+requeued {held} -> came back {back}; after flush {got}/30 frames "
          f"[{state}], indices seen {sorted(set(seen))}")
    if got == 0:
        break
print(f"RESULT {mode}: {frames} frames total; requeued-in-window buffers never seen again: {sorted(lost)}")
stream(False, OUT)
stream(False, CAP)
os.close(fd)
