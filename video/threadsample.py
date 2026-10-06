#!/usr/bin/env python3
# threadsample.py <pid> <seconds> — (root) sample a process every ~10 ms: per-thread CPU % over the window, and for the
# main thread its state (R/S/D) plus the top of its kernel stack while it is not running (where it blocks).
import collections
import os
import sys
import time

pid, dur = int(sys.argv[1]), float(sys.argv[2])
hz = os.sysconf("SC_CLK_TCK")


def ticks():
    out = {}
    for t in os.listdir("/proc/%d/task" % pid):
        try:
            st = open("/proc/%d/task/%s/stat" % (pid, t)).read()
            comm = st[st.index("(") + 1:st.rindex(")")]
            f = st[st.rindex(")") + 2:].split()
            out[t] = (comm, int(f[11]) + int(f[12]))
        except (OSError, ValueError):
            pass
    return out


def kstack(tid):
    try:
        fr = [ln.split("]", 1)[-1].strip().split("+")[0] for ln in open("/proc/%d/task/%d/stack" % (pid, tid))]
    except OSError:
        return "?"
    skip = ("__switch_to", "__schedule", "schedule", "schedule_timeout", "schedule_hrtimeout_range",
            "schedule_hrtimeout_range_clock", "do_nanosleep", "hrtimer_nanosleep")
    fr = [f for f in fr if f and f not in skip]
    return " < ".join(fr[:4]) or "?"


t0, n = time.time(), 0
a = ticks()
states, stacks = collections.Counter(), collections.Counter()
while time.time() - t0 < dur:
    try:
        st = open("/proc/%d/task/%d/stat" % (pid, pid)).read()
    except OSError:
        break
    s = st[st.rindex(")") + 2]
    states[s] += 1
    if s != "R":
        stacks[kstack(pid)] += 1
    n += 1
    time.sleep(0.01)
el = time.time() - t0
b = ticks()
print("threads (CPU %% of one core over %.1f s):" % el)
rows = [(100.0 * (b[t][1] - a[t][1]) / hz / el, b[t][0], t) for t in b if t in a]
for pct, comm, t in sorted(rows, reverse=True)[:12]:
    print("  %5.1f %%  %s (%s)%s" % (pct, comm, t, "  <- main" if int(t) == pid else ""))
print("main thread states over %d samples: %s" % (n, ", ".join("%s %d%%" % (k, 100 * v // max(n, 1))
                                                                  for k, v in states.most_common())))
print("main thread blocked in (kernel stack top, % of samples):")
for k, v in stacks.most_common(8):
    print("  %3d%%  %s" % (100 * v // max(n, 1), k))
