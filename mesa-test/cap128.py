# a3xx: UBO bind offsets must allow CP_LOAD_STATE SS_INDIRECT (source aligned to const_upload_unit * 16 = 128 B)
p = 'src/gallium/drivers/freedreno/freedreno_screen.c'
s = open(p).read()
old = '   caps->constant_buffer_offset_alignment = 64;\n'
if old in s:
    new = '''   /* a3xx loads UBO ranges into the const file with CP_LOAD_STATE SS_INDIRECT,
    * whose source must be aligned to const_upload_unit (8 vec4 = 128 bytes),
    * like ir3 aligns constant_data_offset; a 64-byte aligned UBO binding hangs
    * the GPU.
    */
   caps->constant_buffer_offset_alignment = is_a3xx(screen) ? 128 : 64;
'''
    s = s.replace(old, new); open(p, 'w').write(s)
print('cap128 added')
