# gt510 test instrumentation for freedreno's reorder-only upload path in
# fd_resource_transfer_map(): FD_GT510 bits (read once)
#   1 = never shadow the resource, 2 = never use a staging upload,
#   4 = skip the whole reorder-only block (flush + wait, like inorder).
p = 'src/gallium/drivers/freedreno/freedreno_resource.c'
s = open(p).read()

old_if = '''      if (ctx->screen->reorder && busy && !(usage & PIPE_MAP_READ) &&
          (usage & PIPE_MAP_DISCARD_RANGE)) {
'''
new_if = '''      static int gt510_dbg = -1;
      if (gt510_dbg < 0) {
         const char *e = getenv("FD_GT510");
         gt510_dbg = e ? atoi(e) : 0;
      }

      if (ctx->screen->reorder && !(gt510_dbg & 4) && busy &&
          !(usage & PIPE_MAP_READ) && (usage & PIPE_MAP_DISCARD_RANGE)) {
'''
assert s.count(old_if) == 1
s = s.replace(old_if, new_if)

old_shadow = '''         if (needs_flush && !(usage & TC_TRANSFER_MAP_NO_INVALIDATE) &&
'''
new_shadow = '''         if (!(gt510_dbg & 1) && needs_flush &&
             !(usage & TC_TRANSFER_MAP_NO_INVALIDATE) &&
'''
assert s.count(old_shadow) == 1
s = s.replace(old_shadow, new_shadow)

old_staging = '''            if (is_renderable(prsc))
               staging_rsc = fd_alloc_staging(ctx, rsc, level, box, usage);
'''
new_staging = '''            if (!(gt510_dbg & 2) && is_renderable(prsc))
               staging_rsc = fd_alloc_staging(ctx, rsc, level, box, usage);
'''
assert s.count(old_staging) == 1
s = s.replace(old_staging, new_staging)

if '#include <stdlib.h>' not in s:
    s = s.replace('#include "util/format/u_format.h"', '#include <stdlib.h>\n#include "util/format/u_format.h"', 1)
open(p, 'w').write(s)
print('instrumented')
