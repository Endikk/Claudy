"""Claudy waving hello, generated from the same 2:1 isometric scene as the typing mascot.

Boxes (body, legs, arms) are ray-cast into pixels, faces shaded top / left / right, then an
outline is added. Writes raw.json next to this file; export.py turns it into the deliverables.

    python3 wave.py && python3 export.py && swift make_gif.swift
"""
import math, json, os
# +x screen right-down, +y left-down, +z up. Claude faces +y (down-left), like the typing sprite.
# He waves with his left hand (-x side), lit, so it reads against the background.
def boxes(arm, hop):
    z=hop
    B=[(0,12,0,6,4+z,12+z,'body')]
    for lx in (1,4,7,10): B.append((lx,lx+1,5,6,z,4+z,'body'))      # front legs
    for lx in (1,10): B.append((lx,lx+1,0,1,z,4+z,'body'))          # back legs
    B.append((12,13,2,4,6+z,8+z,'body'))                             # right arm, resting stub
    if arm=='down':
        B.append((-1,0,2,4,6+z,8+z,'body'))
    else:
        # Left hand, on the lit side where it stands out against the background.
        # The hand swings across the view (toward and away along y), never into the head.
        lean={'up':0,'left':2,'right':-2,'half':0}[arm]
        B.append((-1,0,2,4,7+z,9+z,'body'))                             # shoulder
        if arm=='half':
            B.append((-3,-1,2,4,7+z,12+z,'body'))
        else:
            B.append((-3,-1,2,4,7+z,13+z,'body'))                       # upper arm
            if lean<0:
                # Swinging away (up-right on screen) lifts the hand a row: start the forearm one
                # step lower so the hand stays level with the other poses, and let the upper
                # arm close the joint, since an elbow box would stick out as a lit notch.
                B.append((-3,-1,2+lean,4+lean,12+z,16+z,'body'))        # forearm and hand
            else:
                B.append((-3,-1,2+lean//2,4+lean//2,12+z,14+z,'body'))  # elbow, keeps the joint closed
                B.append((-3,-1,2+lean,4+lean,13+z,17+z,'body'))        # forearm and hand
    return B
def classify(b,face,x,y,z,eyes,hop):
    ch={'z':'T','y':'C','x':'D'}[face]
    if b[:4]==(0,12,0,6) and face=='y':
        zz=z-hop
        if eyes=='open' and 9<=zz<11 and (3<=x<4 or 8<=x<9): return 'E'
    return ch
def cast(B,sx,sy):
    u=90.0
    while u>-20:
        x=(u+sx)/2;y=(u-sx)/2;z=u/2-sy
        for b in B:
            if b[0]<=x<b[1] and b[2]<=y<b[3] and b[4]<=z<b[5]:
                dx=b[1]-x;dy=b[3]-y;dz=b[5]-z
                return b,('x' if dx<=min(dy,dz) else ('y' if dy<=dz else 'z')),x,y,z
        u-=0.02
    return None
POSES=[('down','open',0),('half','open',0),('up','happy',1),('left','happy',1),('up','happy',0),('right','happy',0),('down','blink',0)]
allB=[b for a,e,h in POSES for b in boxes(a,h)]
xs=[];ys=[]
for b in allB:
    for x in b[0:2]:
        for y in b[2:4]:
            for z in b[4:6]: xs.append(x-y); ys.append((x+y)/2-z)
X0=math.floor(min(xs))-2; X1=math.ceil(max(xs))+2; Y0=math.floor(min(ys))-2; Y1=math.ceil(max(ys))+3
W=X1-X0; H=Y1-Y0
def eye_px(hop):
    # screen position of the eye cells' top-left, for drawing ^ and blink by hand
    out=[]
    for ex in (3,8):
        x,y,z=ex+0.5,6,10.5+hop
        out.append((int(math.floor(x-y-X0)), int(math.floor((x+y)/2-z-Y0))))
    return out
def render(arm,eyes,hop):
    B=boxes(arm,hop)
    g=[['.']*W for _ in range(H)]
    # ground shadow under the feet, drawn first
    cx,cy=(6-3)-X0, (6+3)/2-0-Y0+0.5
    for py in range(H):
        for px in range(W):
            if ((px+0.5-cx)/8.5)**2+((py+0.5-cy)/3.2)**2<=1: g[py][px]='s'
    for py in range(H):
        for px in range(W):
            h=cast(B,X0+px+0.5,Y0+py+0.5)
            if h: g[py][px]=classify(h[0],h[1],h[2],h[3],h[4],eyes,hop)
    for (c,r) in eye_px(hop):
        if eyes=='happy':
            for dx,dy in ((-1,1),(0,0),(1,1)):
                if 0<=r+dy<H and 0<=c+dx<W: g[r+dy][c+dx]='E'
        elif eyes=='blink':
            g[r+1][c]='E'; 
            if c+1<W: g[r+1][c-1 if c>0 else c]='E'
    out=[r[:] for r in g]
    for py in range(H):
        for px in range(W):
            if g[py][px] in '.s' and any(0<=px+dx<W and 0<=py+dy<H and g[py+dy][px+dx] not in '.s' for dx,dy in((1,0),(-1,0),(0,1),(0,-1))):
                out[py][px]='o'
    return out
FR=[render(*p) for p in POSES]
# playback: idle, raise, wave x3, lower, blink, idle
ORDER=[(0,700),(1,90),(2,110),(3,140),(4,140),(5,140),(4,140),(3,140),(4,140),(5,140),(4,140),(3,140),(2,110),(1,90),(0,400),(6,110),(0,500)]
PAL={'C':'#d97757','T':'#e9a07c','D':'#9b4e45','o':'#3a1a1e','E':'#2a1418','s':'#00000033'}
NAMES=['idle','raise','wave-up-hop','wave-left-hop','wave-up','wave-right','blink']
json.dump({'w':W,'h':H,'names':NAMES,'frames':[[''.join(r) for r in f] for f in FR],'order':ORDER,'pal':PAL},
          open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'raw.json'),'w'))
print(W,H,len(FR))
