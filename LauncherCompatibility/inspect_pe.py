from pathlib import Path
import struct

class PE:
    def __init__(self, path):
        self.d=Path(path).read_bytes()
        pe=self.u32(60); opt=pe+24
        self.base=self.u64(opt+24)
        self.dirs=opt+112
        self.sections=[]
        for i in range(self.u16(pe+6)):
            off=opt+self.u16(pe+20)+40*i
            vs,va,rs,rp=struct.unpack_from('<IIII',self.d,off+8)
            self.sections.append((va,max(vs,rs),rp))
    def u16(self,o):return struct.unpack_from('<H',self.d,o)[0]
    def u32(self,o):return struct.unpack_from('<I',self.d,o)[0]
    def u64(self,o):return struct.unpack_from('<Q',self.d,o)[0]
    def offset(self,rva):
        for va,size,rp in self.sections:
            if va<=rva<va+size:return rp+rva-va
        return rva
    def string(self,o):return self.d[o:self.d.index(b'\0',o)].decode(errors='replace')
    def exports(self):
        o=self.offset(self.u32(self.dirs));n=self.u32(o+24);tab=self.offset(self.u32(o+32))
        return {self.string(self.offset(self.u32(tab+4*i))) for i in range(n)}
    def delay_imports(self):
        rva=self.u32(self.dirs+13*8)
        if not rva:return {}
        o=self.offset(rva);result={}
        while self.u32(o+4):
            attr=self.u32(o);name=self.u32(o+4);names=self.u32(o+16)
            if not attr&1:name-=self.base;names-=self.base
            lib=self.string(self.offset(name));imp=[];t=self.offset(names)
            while self.u64(t):
                v=self.u64(t)
                if not v>>63:imp.append(self.string(self.offset(v)+2))
                t+=8
            result[lib]=imp;o+=32
        return result
    def imported_address(self, library, function):
        o=self.offset(self.u32(self.dirs+8))
        while self.u32(o+12):
            lib=self.string(self.offset(self.u32(o+12)))
            names=self.u32(o) or self.u32(o+16); iat=self.u32(o+16)
            t=self.offset(names);i=0
            while self.u64(t+8*i):
                v=self.u64(t+8*i)
                if not v>>63 and lib.lower()==library.lower() and self.string(self.offset(v)+2)==function:return iat+8*i
                i+=1
            o+=20
        return None

if __name__=='__main__':
    root=Path(__file__).resolve().parent
    browser=Path('/private/tmp/mnm-launcher-auto-r1m_jy6q/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application/154.0.4258.48/msedge.dll')
    imports=PE(browser).delay_imports()
    for engine in ['engine','engine11']:
        p=PE(root/engine/'wswine.bundle/lib/wine/x86_64-windows/user32.dll')
        names=next(v for k,v in imports.items() if k.lower()=='user32.dll')
        print(engine,'missing USER32 functions:',sorted(set(names)-p.exports()))
        print('SetLastError',p.imported_address('kernel32.dll','SetLastError'))
