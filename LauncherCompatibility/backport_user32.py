"""Reproducible x64 PE backport of Wine 11's two user32 stubs.

IsWindowArranged returns FALSE. GetPointerPenInfo sets
ERROR_CALL_NOT_IMPLEMENTED and returns FALSE, matching Wine 11 input.c.
Original exports, ordinals, code and imports are preserved.
This is an isolated compatibility experiment, not a shipping artifact.
"""
from pathlib import Path
import struct, sys, hashlib
from inspect_pe import PE

path=Path(sys.argv[1])
p=PE(path)
if hashlib.sha256(p.d).hexdigest()!='52b981363ba79a50bcbe92fab041640630ee77806d99dbe29eb759c624c1323a':
    raise SystemExit('Unexpected Wine USER32 build; no changes made')
added=['GetPointerPenInfo','IsWindowArranged']
if any(name in p.exports() for name in added):
    raise SystemExit('Already has backported functions; no changes made')
original=p.d
d=bytearray(original)
pe=p.u32(60);opt=pe+24
section_count=p.u16(pe+6)
section_table=opt+p.u16(pe+20)
new_header=section_table+section_count*40
if new_header+40>p.u32(opt+60):raise SystemExit('No room for another section')
align=lambda value,boundary:(value+boundary-1)//boundary*boundary
section_alignment=p.u32(opt+32);file_alignment=p.u32(opt+36)
rva=align(max(va+size for va,size,_ in p.sections),section_alignment)
raw=align(len(d),file_alignment)
blob=bytearray()
emit=lambda fmt,*v:blob.extend(struct.pack(fmt,*v))
put=lambda data:(blob.extend(data),rva+len(blob)-len(data))[1]
# AMD64 TEB.LastErrorValue is GS:0x68. Windows' SetLastError stores here.
pen=put(bytes.fromhex('65 c7 04 25 68 00 00 00 78 00 00 00 31 c0 c3'))
arranged=put(bytes.fromhex('31 c0 c3'))
while len(blob)%4:blob.append(0)
old_rva=p.u32(p.dirs);old_size=p.u32(p.dirs+4);old=p.offset(old_rva)
_,timestamp,major,minor,name,base,nfunctions,nnames,functions,names,ordinals=struct.unpack_from('<IIHHIIIIIII',d,old)
f=list(struct.unpack_from('<'+'I'*nfunctions,d,p.offset(functions)))
named=[]
for i in range(nnames):
    named.append((p.string(p.offset(p.u32(p.offset(names)+i*4))),p.u16(p.offset(ordinals)+i*2)))
# Forwarders must remain inside the new export directory range.
forwarders={i:p.string(p.offset(v)) for i,v in enumerate(f) if old_rva<=v<old_rva+old_size}
directory=put(b'\0'*40)
new_function_table=put(b'\0'*((nfunctions+2)*4))
new_name_table=put(b'\0'*((nnames+2)*4))
new_ordinal_table=put(b'\0'*((nnames+2)*2))
module_name=put(p.string(p.offset(name)).encode()+b'\0')
for i,s in forwarders.items():f[i]=put(s.encode()+b'\0')
f.extend([pen,arranged])
named.extend([(added[0],nfunctions),(added[1],nfunctions+1)])
named.sort()
for i,(s,ordinal) in enumerate(named):
    nrva=put(s.encode()+b'\0')
    struct.pack_into('<I',blob,new_name_table-rva+4*i,nrva)
    struct.pack_into('<H',blob,new_ordinal_table-rva+2*i,ordinal)
struct.pack_into('<'+'I'*len(f),blob,new_function_table-rva,*f)
struct.pack_into('<IIHHIIIIIII',blob,directory-rva,0,timestamp,major,minor,module_name,base,len(f),len(named),new_function_table,new_name_table,new_ordinal_table)
export_size=rva+len(blob)-directory
raw_size=align(len(blob),file_alignment)
struct.pack_into('<8sIIIIIIHHI',d,new_header,b'.mnmapi\0',len(blob),rva,raw_size,raw,0,0,0,0,0x60000020)
struct.pack_into('<H',d,pe+6,section_count+1)
struct.pack_into('<I',d,opt+56,align(rva+len(blob),section_alignment))
struct.pack_into('<I',d,opt+4,p.u32(opt+4)+raw_size)
struct.pack_into('<I',d,opt+64,0)
struct.pack_into('<II',d,p.dirs,directory,export_size)
d.extend(b'\0'*(raw-len(d)))
d.extend(blob)
d.extend(b'\0'*(raw_size-len(blob)))
backup=path.with_suffix('.dll.before-mnm-backport')
if backup.exists():raise SystemExit('Backup already exists; refusing to overwrite')
backup.write_bytes(original)
path.write_bytes(d)
assert set(PE(path).exports())==set(p.exports())|set(added)
print('Added',added,'to',path)
print('Original SHA256',hashlib.sha256(original).hexdigest())
print('Patched SHA256',hashlib.sha256(d).hexdigest())
