p = 'src/gallium/drivers/freedreno/freedreno_resource.c'
s = open(p).read()
old = '''            if (staging_rsc) {
               trans->staging_prsc = &staging_rsc->b.b;'''
new = '''            if (staging_rsc) {
               if (gt510_dbg & 8)
                  fprintf(stderr, "gt510 staging upload: %" PRSC_FMT " box %dx%d+%d+%d usage 0x%x\\n",
                          PRSC_ARGS(prsc), box->width, box->height, box->x, box->y, usage);
               trans->staging_prsc = &staging_rsc->b.b;'''
if 'gt510 staging upload' not in s:
    assert s.count(old) == 1
    s = s.replace(old, new)
    open(p, 'w').write(s)
print('logging added')
