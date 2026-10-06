#!/usr/bin/env python3
# provtest.py [runs] [--portal] — ISSUES 33: replay aperture's DeviceProvider::start_with_default() without opening a camera.
# Starts GStreamer's pipewiredeviceprovider like aperture (provider.start(), then devices() = the list init() picks
# from), then watches the provider bus for DeviceAdded like aperture's handle_message() for 1.5 s. Per run prints
# the Video/Source devices present at start and the order/time of late arrivals; aperture starts the FIRST late
# arrival if nothing was listed at start (camera_added handler ignores last-camera-id).
# --portal: like Snapshot, take the PipeWire remote from org.freedesktop.portal.Camera.OpenPipeWireRemote and give
# it to the provider's fd property (nodes then appear as the portal client's permissions are granted).
import sys, time
import gi
gi.require_version("Gst", "1.0")
from gi.repository import Gst, GLib, Gio

Gst.init(None)
args = [a for a in sys.argv[1:] if not a.startswith('--')]
runs = int(args[0]) if args else 10
portal = '--portal' in sys.argv

def portal_fd():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    if not getattr(portal_fd, 'registered', False):  # as Snapshot does: use its (pre-granted) camera permission
        bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop',
            'org.freedesktop.host.portal.Registry', 'Register', GLib.Variant('(sa{sv})', ('org.gnome.Snapshot', {})),
            None, Gio.DBusCallFlags.NONE, -1, None)
        portal_fd.registered = True
    ret, fds = bus.call_with_unix_fd_list_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop',
        'org.freedesktop.portal.Camera', 'OpenPipeWireRemote', GLib.Variant('(a{sv})', ({},)),
        GLib.VariantType('(h)'), Gio.DBusCallFlags.NONE, -1, None, None)
    return fds.get(ret.unpack()[0])
name = lambda d: d.get_display_name().replace("Built-in ", "").replace(" Camera", "")
tally = {}
for r in range(runs):
    p = Gst.DeviceProviderFactory.get_by_name("pipewiredeviceprovider")
    if portal:
        p.set_property("fd", portal_fd())
    t0 = time.monotonic()
    p.start()
    at_start = [name(d) for d in p.get_devices() if d.has_classes("Video/Source")]
    late = []

    def on_msg(bus, msg):
        if msg.type == Gst.MessageType.DEVICE_ADDED:
            d = msg.parse_device_added()
            if d.has_classes("Video/Source") and name(d) not in at_start:
                late.append("%s@%.0fms" % (name(d), 1000 * (time.monotonic() - t0)))
        return True

    bus = p.get_bus()
    watch = bus.add_watch(GLib.PRIORITY_DEFAULT, on_msg)
    loop = GLib.MainLoop()
    GLib.timeout_add(1500, loop.quit)
    loop.run()
    GLib.source_remove(watch)
    p.stop()
    # what aperture would open with last-camera-id = Back
    pick = "Back" if "Back" in at_start else (at_start[0] if at_start else (late[0].split("@")[0] if late else "none"))
    tally[pick] = tally.get(pick, 0) + 1
    print("run %2d start=%s late=%s -> aperture opens %s" % (r + 1, at_start, late, pick), flush=True)
    time.sleep(0.5)
print("summary:", tally)
