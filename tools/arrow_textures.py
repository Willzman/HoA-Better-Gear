import struct, sys
DOWN = len(sys.argv) > 2 and sys.argv[2] == 'down'
W=H=32; SS=4
def inside(x,y):
    # y up. head: triangle apex (16,30), base y=15 from x=3..29; stem x 10..22, y 2..16
    if 2<=y<=16.5 and 10.5<=x<=21.5: return True
    if 15<=y<=30:
        half=(30-y)/15*13
        return abs(x-16)<=half
    return False
def cov(px,py,grow):
    c=0
    for i in range(SS):
        for j in range(SS):
            x=px+(i+.5)/SS; y=py+(j+.5)/SS
            if grow==0:
                c+=inside(x,y)
            else:
                c+=any(inside(x+dx,y+dy) for dx in(-grow,0,grow) for dy in(-grow,0,grow))
    return c/(SS*SS)
rows=[]
for py in range(H):  # bottom-left origin: first row is bottom
    for px in range(W):
        sy = (H-1-py) if DOWN else py
        fill=cov(px,sy,0); out=cov(px,sy,1.6)
        a=max(fill,out)
        if a==0: rows.append((0,0,0,0)); continue
        # blend fill green over dark outline
        g=(245,60,50) if DOWN else (60,235,60); d=(50,0,0) if DOWN else (0,40,0)
        f=fill/a if a else 0
        # vertical shading on fill
        shade=0.75+0.25*(sy/H)
        col=tuple(int((g[k]*shade)*f+d[k]*(1-f)) for k in range(3))
        rows.append((col[2],col[1],col[0],int(a*255)))
hdr=struct.pack('<BBBHHBHHHHBB',0,0,2,0,0,0,0,0,W,H,32,8)
with open(sys.argv[1],'wb') as fh:
    fh.write(hdr); fh.write(bytes(b for p in rows for b in p))
