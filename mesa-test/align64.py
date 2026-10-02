# FD_GT510 bit 64: copy (SS_DIRECT) only const_bo loads whose source is not 128-byte aligned
p = 'src/gallium/drivers/freedreno/a3xx/fd3_emit.c'
s = open(p).read()
if 'gt510_dbg & 64' not in s:
    old = '   if (gt510_dbg & 32) {'
    new = '   if ((gt510_dbg & 32) || ((gt510_dbg & 64) && (offset % 128))) {'
    assert s.count(old) == 1; s = s.replace(old, new)
    old = '''   uint32_t dst_off = regid / 2;
   /* The blob driver aligns all const uploads dst_off to 64.'''
    new = '''   if (gt510_dbg & 8)
      fprintf(stderr, "gt510 const_bo indirect: stage %d regid %u off %u dwords %u\\n",
              v->type, regid, offset, sizedwords);

   uint32_t dst_off = regid / 2;
   /* The blob driver aligns all const uploads dst_off to 64.'''
    assert s.count(old) == 1; s = s.replace(old, new)
    open(p, 'w').write(s)
print('align64 added')
