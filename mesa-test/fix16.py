p = 'src/gallium/drivers/freedreno/freedreno_resource.c'
s = open(p).read()
if 'gt510_dbg & 16' not in s:
    old = '''         if (!(gt510_dbg & 1) && needs_flush &&
             !(usage & TC_TRANSFER_MAP_NO_INVALIDATE) &&'''
    new = '''         /* bit 16: buffers on gens without a hw blitter always try a shadow */
         bool gt510_buf = (gt510_dbg & 16) && prsc->target == PIPE_BUFFER && !ctx->blit;
         if (!(gt510_dbg & 1) && (needs_flush || gt510_buf) &&
             !(usage & TC_TRANSFER_MAP_NO_INVALIDATE) &&'''
    assert s.count(old) == 1; s = s.replace(old, new)
    old = '''            needs_flush = busy = false;
            ctx->stats.shadow_uploads++;'''
    new = '''            needs_flush = busy = false;
            ctx->stats.shadow_uploads++;
            if (gt510_dbg & 8)
               fprintf(stderr, "gt510 shadow upload: %" PRSC_FMT "\\n", PRSC_ARGS(prsc));'''
    assert s.count(old) == 1; s = s.replace(old, new)
    old = '''            if (!(gt510_dbg & 2) && is_renderable(prsc))'''
    new = '''            if (!(gt510_dbg & 2) && !gt510_buf && is_renderable(prsc))'''
    assert s.count(old) == 1; s = s.replace(old, new)
    open(p, 'w').write(s)
print('fix16 added')
