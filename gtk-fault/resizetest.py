#!/usr/bin/env python3
"""GTK4 resize stress for the a306 'GPU reads a freed buffer at app start' bug (ISSUES 11).

  resizetest.py <mode> <seconds> [period_ms]
  mode: fullscreen  toggle fullscreen/unfullscreen every period (compositor resizes the toplevel)
        relaunch    just open a window, draw for <seconds>, exit (use in a loop: app start-up path)
The window shows text + a continuously animated drawing area so every frame is a real GL draw.
"""
import sys, time
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib

mode, secs = sys.argv[1], float(sys.argv[2])
period = int(sys.argv[3]) if len(sys.argv) > 3 else 400

def on_activate(app):
    win = Gtk.ApplicationWindow(application=app, title="resizetest")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.append(Gtk.Label(label="resize test " + mode))
    # no cairo (python3-gi-cairo absent): spinner + pulsing bar + a label updated every frame
    sp = Gtk.Spinner(spinning=True, hexpand=True, vexpand=True)
    pb = Gtk.ProgressBar()
    lb = Gtk.Label(label="0")
    t0 = time.monotonic()
    def tick(w, clock):
        pb.pulse()
        lb.set_label("%.2f" % (time.monotonic() - t0))
        return True
    lb.add_tick_callback(tick)
    for w in (sp, pb, lb):
        box.append(w)
    box.append(Gtk.Entry(text="text entry"))
    win.set_child(box)
    win.present()
    if mode == "fullscreen":
        state = {"fs": False}
        def toggle():
            state["fs"] = not state["fs"]
            (win.fullscreen if state["fs"] else win.unfullscreen)()
            return True
        GLib.timeout_add(period, toggle)
    GLib.timeout_add(int(secs * 1000), lambda: (app.quit(), False)[1])

app = Gtk.Application(application_id="org.gt510.ResizeTest")
app.connect("activate", on_activate)
app.run([])
