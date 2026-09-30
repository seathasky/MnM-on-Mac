"""Isolated Wine experiment: reject foreign-process RevokeDragDrop HWNDs.

Wine 10 dereferences a window property's IDropTarget pointer from another
process. The pointer is only valid in that process. This test adds an ownership
check before the original implementation; no official application is modified.
"""
from inspect_pe import PE
from pathlib import Path
import struct,sys,hashlib
p=PE(sys.argv[1]);path=Path(sys.argv[1]);d=bytearray(p.d)
if hashlib.sha256(p.d).hexdigest()!='e830fc029eb4ebadd7b2ebd74b418742bbe643ab8abeab8118463b3803e9627c':
    raise SystemExit('Unexpected Wine OLE32 build; no changes made')
pe=p.u32(60);opt=pe+24;count=p.u16(pe+6);header=opt+p.u16(pe+20)+40*count
assert header+40<=p.u32(opt+60)
align=lambda v,b:(v+b-1)//b*b
rva=align(max(va+size for va,size,_ in p.sections),p.u32(opt+32))
raw=align(len(d),p.u32(opt+36))
start=0x35c70;off=p.offset(start);original=bytes.fromhex('57 56 53 48 83 ec 40')
assert d[off:off+7]==original
iat=p.imported_address('user32.dll','GetWindowThreadProcessId');assert iat
blob=bytearray(bytes.fromhex('51 48 83 ec 30 48 8d 54 24 20 48 8b 4c 24 30 ff 15'))
blob.extend(struct.pack('<i',iat-(rva+len(blob)+4)))
# TEB.ClientId.UniqueProcess (GS:0x40), with the returned DWORD process id.
blob.extend(bytes.fromhex('65 8b 04 25 40 00 00 00 3b 44 24 20 48 83 c4 30 59 74 06 b8 02 01 04 80 c3'))
blob.extend(original)
blob.append(0xe9);blob.extend(struct.pack('<i',start+7-(rva+len(blob)+4)))
rawsize=align(len(blob),p.u32(opt+36))
struct.pack_into('<8sIIIIIIHHI',d,header,b'.mnmole\0',len(blob),rva,rawsize,raw,0,0,0,0,0x60000020)
struct.pack_into('<H',d,pe+6,count+1)
struct.pack_into('<I',d,opt+56,align(rva+len(blob),p.u32(opt+32)))
struct.pack_into('<I',d,opt+4,p.u32(opt+4)+rawsize)
struct.pack_into('<I',d,opt+64,0)
d[off:off+7]=b'\xe9'+struct.pack('<i',rva-start-5)+b'\x90\x90'
d.extend(b'\0'*(raw-len(d)));d.extend(blob);d.extend(b'\0'*(rawsize-len(blob)))
backup=path.with_suffix('.dll.before-mnm-ole-guard')
assert not backup.exists()
backup.write_bytes(p.d);path.write_bytes(d)
print('Added ownership guard:',path,hashlib.sha256(d).hexdigest())
