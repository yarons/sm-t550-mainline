#!/usr/bin/env python3
# List ancillary links of /dev/media0 via MEDIA_IOC_G_TOPOLOGY (media-ctl -p hides them).
import ctypes, fcntl, os
class Topo(ctypes.Structure):
    _fields_ = [('topology_version', ctypes.c_uint64),
                ('num_entities', ctypes.c_uint32), ('reserved1', ctypes.c_uint32), ('ptr_entities', ctypes.c_uint64),
                ('num_interfaces', ctypes.c_uint32), ('reserved2', ctypes.c_uint32), ('ptr_interfaces', ctypes.c_uint64),
                ('num_pads', ctypes.c_uint32), ('reserved3', ctypes.c_uint32), ('ptr_pads', ctypes.c_uint64),
                ('num_links', ctypes.c_uint32), ('reserved4', ctypes.c_uint32), ('ptr_links', ctypes.c_uint64)]
class Ent(ctypes.Structure):
    _fields_ = [('id', ctypes.c_uint32), ('name', ctypes.c_char * 64), ('function', ctypes.c_uint32),
                ('flags', ctypes.c_uint32), ('reserved', ctypes.c_uint32 * 5)]
class Link(ctypes.Structure):
    _fields_ = [('id', ctypes.c_uint32), ('source_id', ctypes.c_uint32), ('sink_id', ctypes.c_uint32),
                ('flags', ctypes.c_uint32), ('reserved', ctypes.c_uint32 * 6)]
IOC = (3 << 30) | (ctypes.sizeof(Topo) << 16) | (ord('|') << 8) | 0x04
fd = os.open('/dev/media0', os.O_RDWR)
t = Topo(); fcntl.ioctl(fd, IOC, t)
ents = (Ent * t.num_entities)(); links = (Link * t.num_links)()
t.ptr_entities = ctypes.addressof(ents); t.ptr_links = ctypes.addressof(links)
t.ptr_interfaces = 0; t.ptr_pads = 0; t.num_interfaces = 0; t.num_pads = 0
t.num_entities = len(ents); t.num_links = len(links)
fcntl.ioctl(fd, IOC, t)
name = {e.id: e.name.decode() for e in ents}
anc = [(name.get(l.source_id, l.source_id), name.get(l.sink_id, l.sink_id)) for l in links if (l.flags >> 28) == 2]
print('ancillary links:', anc or 'none')
