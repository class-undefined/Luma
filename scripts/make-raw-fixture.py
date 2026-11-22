# Generates a deterministic, uncompressed 16-bit Bayer DNG. No third-party photos are used.
import struct, math
from pathlib import Path
w,h=512,512
tags=[]
def tag(n,t,v):
    if t==2:b=v.encode()+b'\0'; c=len(b)
    elif t==1:b=bytes(v);c=len(v)
    elif t in (3,4):b=struct.pack('<'+('H' if t==3 else 'I')*len(v),*v);c=len(v)
    elif t in (5,10):b=b''.join(struct.pack('<'+('II' if t==5 else 'ii'),*x) for x in v);c=len(v)
    tags.append((n,t,c,b))
for n,v in [(256,w),(257,h),(278,h),(279,w*h*2)]:tag(n,4,[v])
for n,v in [(258,16),(259,1),(262,32803),(274,1),(277,1),(284,1),(339,1)]:tag(n,3,[v])
tag(271,2,'Luma');tag(272,2,'Synthetic DNG');tag(50708,2,'Luma Synthetic DNG')
tag(50706,1,[1,4,0,0]);tag(50707,1,[1,3,0,0]);tag(33421,3,[2,2]);tag(33422,1,[0,1,1,2]);tag(50710,1,[0,1,2]);tag(50711,3,[1]);tag(50713,3,[1,1]);tag(50714,3,[0]);tag(50717,4,[65535]);tag(50719,4,[0,0]);tag(50720,4,[w,h]);tag(50829,4,[0,0,h,w]);tag(50721,10,[(1,1),(0,1),(0,1),(0,1),(1,1),(0,1),(0,1),(0,1),(1,1)]);tag(50728,5,[(1,1),(1,1),(1,1)]);tag(50778,3,[21]);tag(273,4,[0])
tag(254,4,[0]);tag(50718,5,[(1,1),(1,1)]);tags.sort();pos=8+2+len(tags)*12+4;extra=bytearray();entries=[]
for n,t,c,b in tags:
    if len(b)>4:
        if len(extra)%2:extra.append(0)
        v=struct.pack('<I',pos+len(extra));extra.extend(b)
    else:v=b.ljust(4,b'\0')
    entries.append((n,struct.pack('<HHI',n,t,c)+v))
raw_offset=pos+len(extra)
entries=[struct.pack('<HHII',273,4,1,raw_offset) if n==273 else b for n,b in entries]
raw=bytearray()
for y in range(h):
 for x in range(w):
    channel=((y%2)*2+x%2)
    levels=[0.15+0.65*x/w,0.2+0.45*y/h,0.2+0.45*y/h,0.3+0.3*(1-x/w)]
    raw.extend(struct.pack('<H',int(levels[channel]*65535)))
data=b'II'+struct.pack('<HIH',42,8,len(tags))+b''.join(entries)+struct.pack('<I',0)+extra+raw
Path(__file__).resolve().parents[1].joinpath('Tests/LumaCoreTests/Fixtures/synthetic.dng').write_bytes(data)
