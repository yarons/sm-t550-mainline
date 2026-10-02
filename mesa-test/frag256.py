# FD_GT510 bit 256: copy (SS_DIRECT) only fragment-stage const_bo loads; bit 512: only loads > 32 dwords
p = 'src/gallium/drivers/freedreno/a3xx/fd3_emit.c'
s = open(p).read()
if 'gt510_dbg & 256' not in s:
    old = '   if ((gt510_dbg & 32) || ((gt510_dbg & 64) && (offset % 128))) {'
    new = ('   if ((gt510_dbg & 32) || ((gt510_dbg & 64) && (offset % 128)) ||\n'
           '       ((gt510_dbg & 256) && v->type == MESA_SHADER_FRAGMENT) ||\n'
           '       ((gt510_dbg & 512) && sizedwords > 32)) {')
    assert s.count(old) == 1; s = s.replace(old, new); open(p, 'w').write(s)
print('frag256 added')
