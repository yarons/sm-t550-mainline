# FD_GT510 bit 32: a3xx const uploads from a buffer object are copied into the command stream
# (CP_LOAD_STATE SS_DIRECT from a CPU mapping) instead of CP_LOAD_STATE SS_INDIRECT.
p = 'src/gallium/drivers/freedreno/a3xx/fd3_emit.c'
s = open(p).read()
if 'gt510_dbg & 32' not in s:
    old = '''   uint32_t dst_off = regid / 2;
   /* The blob driver aligns all const uploads dst_off to 64.'''
    new = '''   static int gt510_dbg = -1;
   if (gt510_dbg < 0) {
      const char *e = getenv("FD_GT510");
      gt510_dbg = e ? atoi(e) : 0;
   }
   if (gt510_dbg & 32) {
      const uint32_t *p = (const uint32_t *)((const char *)fd_bo_map(bo) + offset);
      if (gt510_dbg & 8)
         fprintf(stderr, "gt510 const_bo direct: stage %d regid %u off %u dwords %u\\n",
                 v->type, regid, offset, sizedwords);
      fd3_emit_const_user(ring, v, regid, sizedwords, p);
      return;
   }

   uint32_t dst_off = regid / 2;
   /* The blob driver aligns all const uploads dst_off to 64.'''
    assert s.count(old) == 1; s = s.replace(old, new)
    open(p, 'w').write(s)
print('direct32 added')
