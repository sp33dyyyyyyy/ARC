"""
glb_to_lua.py - reads assets/models/*.glb and writes src/ReplicatedStorage/Shared/ImportedModels.lua
(part names, colours, wheel / steering groups, pivots and axes of the animated parts).
Run:  python3 tools/glb_to_lua.py     (needs numpy)
If you edit the models, keep the node names (see the lists below) or update them here.
"""
import json,struct,numpy as np
def load(path):
    d=open(path,'rb').read()
    clen,=struct.unpack('<I',d[12:16])
    j=json.loads(d[20:20+clen])
    off=20+clen
    blen,btype=struct.unpack('<I4s',d[off:off+8]); bin_=d[off+8:off+8+blen]
    return j,bin_
def acc(j,b,i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    ct={5126:('f',4),5123:('H',2),5125:('I',4),5121:('B',1)}[a['componentType']]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    o=bv.get('byteOffset',0)+a.get('byteOffset',0)
    stride=bv.get('byteStride') or ct[1]*n
    arr=np.zeros((a['count'],n),dtype=np.float64)
    if stride==ct[1]*n:
        arr=np.frombuffer(b,dtype={'f':'<f4','H':'<u2','I':'<u4','B':'u1'}[ct[0]],count=a['count']*n,offset=o).reshape(-1,n).astype(np.float64)
    else:
        for k in range(a['count']):
            arr[k]=struct.unpack_from('<'+ct[0]*n,b,o+k*stride)
    return arr
def quat_mat(q):
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
def local(n):
    M=np.eye(4)
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    R=np.eye(3)
    if 'rotation' in n: R=quat_mat(n['rotation'])
    S=np.diag(n.get('scale',[1,1,1]))
    M[:3,:3]=R@S
    M[:3,3]=n.get('translation',[0,0,0])
    return M
def world(j):
    W={}
    def walk(i,P):
        M=P@local(j['nodes'][i]); W[i]=M
        for c in j['nodes'][i].get('children',[]): walk(c,M)
    for s in j['scenes'][0]['nodes']: walk(s,np.eye(4))
    return W
def mesh_world(j,b,i,W):
    n=j['nodes'][i]
    if 'mesh' not in n: return None
    P=[];T=[]
    base=0
    for p in j['meshes'][n['mesh']]['primitives']:
        pos=acc(j,b,p['attributes']['POSITION'])
        idx=acc(j,b,p['indices']).astype(int).ravel() if 'indices' in p else np.arange(len(pos))
        P.append(pos); T.append(idx.reshape(-1,3)+base); base+=len(pos)
    P=np.vstack(P);T=np.vstack(T)
    Pw=(W[i][:3,:3]@P.T).T+W[i][:3,3]
    return P,Pw,T


# ---------------------------------------------------------------------------
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
U = os.path.join(HERE, '..', 'assets', 'models') + os.sep
def srgb(c): return [int(round(255*(max(0,min(1,x))**(1/2.2)))) for x in c]
def matinfo(mname):
    n=mname.lower()
    if 'lens' in n or 'glass' in n or 'windscreen' in n or n=='headlight': return 'Glass'
    if 'lamp' in n or 'tail' in n: return 'Neon'
    if 'chrome' in n or 'metal' in n or 'steel' in n or 'alloy' in n or 'anodized' in n: return 'Metal'
    if 'rubber' in n or 'seat' in n: return 'Rubber'
    return 'SmoothPlastic'
def fv(v): return "Vector3.new(%.4f, %.4f, %.4f)"%tuple(v)
def gen(key,f,spec):
    j,b=load(U+f); W=world(j)
    names={n['name']:i for i,n in enumerate(j['nodes'])}
    bb={}
    for i,n in enumerate(j['nodes']):
        r=mesh_world(j,b,i,W)
        if r: bb[n['name']]=(r[1].min(0),r[1].max(0),r[1])
    ctr=lambda k:(bb[k][0]+bb[k][1])/2
    ft,rt=spec['tyres']
    fc=ctr(ft); rc=ctr(rt)
    fwd=(fc-rc); fwd[1]=0; fwd/=np.linalg.norm(fwd)
    out=[]
    out.append("\t%s = {"%key)
    out.append("\t\tforward = %s,"%fv(fwd))
    out.append('\t\tfrontTyre = "%s", rearTyre = "%s",'%(ft,rt))
    out.append("\t\tfrontCentre = %s, tyreRadius = %.4f, wheelbase = %.4f,"%(fv(fc),(bb[ft][1][1]-bb[ft][0][1])/2,np.linalg.norm(fc-rc)))
    # parts
    out.append("\t\tparts = {")
    for i,n in enumerate(j['nodes']):
        if 'mesh' not in n: continue
        m=j['materials'][j['meshes'][n['mesh']]['primitives'][0].get('material',0)]
        pb=m['pbrMetallicRoughness']; col=srgb(pb['baseColorFactor'][:3]); al=pb['baseColorFactor'][3]
        mt=matinfo(m['name']); tr=round(1-al,2)
        if mt=='Glass' and tr<0.15: tr=0.25
        paint=spec['paint'].get(m['name'])
        extra=(', paint = "%s"'%paint) if paint else ''
        out.append('\t\t\t[%s] = { c = Color3.fromRGB(%d, %d, %d), m = "%s", t = %.2f%s },'%('"%s"'%n['name'],col[0],col[1],col[2],mt,tr,extra))
    out.append("\t\t},")
    def lst(name,l): out.append("\t\t%s = { %s },"%(name,", ".join('"%s"'%x for x in l)))
    lst('wheelFront',spec['wheelFront']); lst('wheelRear',spec['wheelRear']); lst('steerParts',spec['steer'])
    # steering axis
    pts=np.vstack([bb[n][2] for n in spec['fork']]); c=pts.mean(0); u,s,vt=np.linalg.svd(pts-c,full_matrices=False); d=vt[0]
    if d[1]<0: d=-d
    # axis passes through the fork centroid; use the point at wheel-centre height
    t=(fc[1]-c[1])/d[1]; pa=c+d*t
    out.append("\t\tsteer = { point = %s, dir = %s },"%(fv(pa),fv(d)))
    def anim(nm,node):
        q=[a for a in j['animations'] if any(j['nodes'][ch['target']['node']]['name']==node for ch in a['channels'])][0]
        ch=[c_ for c_ in q['channels'] if j['nodes'][c_['target']['node']]['name']==node][0]
        s=q['samplers'][ch['sampler']]; o=acc(j,b,s['output']); qq=o[-1] if node!='Choke' or True else o[-1]
        # largest rotation among keys
        best=max(o,key=lambda z:abs(2*math.acos(max(-1,min(1,z[3])))))
        ang=2*math.acos(max(-1,min(1,best[3]))); ax=best[:3]/max(np.linalg.norm(best[:3]),1e-9)
        piv=W[names[node]][:3,3]
        lo,hi,_=bb[node]
        return '\t\t%s = { part = "%s", pivot = %s, axis = %s, angle = %.4f, size = %s },'%(nm,node,fv(piv),fv(ax),ang,fv(hi-lo))
    out.append(anim('stand','Kickstand'))
    out.append(anim('tap','FuelTap')); out.append(anim('key','IgnitionKey')); out.append(anim('choke','Choke'))
    # stand tip hint: far end of the stand mesh from the pivot
    lo,hi,P=bb['Kickstand']; piv=W[names['Kickstand']][:3,3]
    tip=P[np.argmax(np.linalg.norm(P-piv,axis=1))]
    out.append("\t\tstandTip = %s,"%fv(tip))
    pts_={}
    seat=bb['Seat']; pts_['seat']=np.array([ctr('Seat')[0],seat[1][1],ctr('Seat')[2]])
    pts_['bars']=ctr('Handlebar'); pts_['tap']=ctr('FuelTap'); pts_['ignition']=ctr('IgnitionKey'); pts_['choke']=ctr('Choke')
    pts_['exhaust']=ctr('ExhaustTip')
    right=np.cross(fwd,[0,1,0]); pts_['starter']=ctr('Handlebar')+right*0.22
    ek=spec['engine']; lo_,hi_,_=bb[ek]; ec=(lo_+hi_)/2
    back=-fwd
    half=(hi_[0]-lo_[0])/2
    pivot=ec+right*(half+0.02)+np.array([0,0.02,0])+back*0.04
    kt=pivot+back*0.20+right*0.04+np.array([0,0.10,0])
    pts_['kickPivot']=pivot; pts_['kickTip']=kt
    for k,v in pts_.items(): out.append("\t\t%s = %s,"%({'seat':'seatPoint','bars':'barsPoint','tap':'tapPoint','ignition':'ignitionPoint','choke':'chokePoint','exhaust':'exhaustPoint','starter':'starterPoint','kickPivot':'kickPivot','kickTip':'kickTip'}[k],fv(v)))
    out.append("\t},")
    return "\n".join(out)
aerox=dict(tyres=("FrontWheel_Tyre","RearWheel_Tyre"),paint={'Body_Blue':'body','Body_Blue_Light':'accent'},
  wheelFront=["FrontWheel_Tyre","FrontWheel_Rim","FrontWheel_Spokes","FrontWheel_Hub","FrontBrakeDisc"],
  wheelRear=["RearWheel_Tyre","RearWheel_Rim","RearWheel_Spokes","RearWheel_Hub","RearWheel_BrakeDisc"],
  steer=["FrontWheel_Tyre","FrontWheel_Rim","FrontWheel_Spokes","FrontWheel_Hub","FrontBrakeDisc","FrontBrakeCaliper","FrontFork","FrontMudguard","Handlebar","Grip_L","Grip_R","MirrorStem_L","Mirror_L","MirrorGlass_L","MirrorStem_R","Mirror_R","MirrorGlass_R","BrakeLever_L","BrakeLever_R","Dashboard","InstrumentDisplay","Choke"],
  fork=["FrontFork"],engine="EngineTransmission")
sj,sb=load(U+"supermoto80.glb")
def kids(j,name):
    names={n['name']:i for i,n in enumerate(j['nodes'])}
    out=[]
    def walk(i):
        for c in j['nodes'][i].get('children',[]):
            if 'mesh' in j['nodes'][c]: out.append(j['nodes'][c]['name'])
            walk(c)
    walk(names[name]); return out
sm=dict(tyres=("FrontTyre","RearTyre"),paint={'Body_SatinBlack':'body','Graphic_White':'accent'},
  wheelFront=kids(sj,'FrontWheel'),wheelRear=kids(sj,'RearWheel'),steer=kids(sj,'Steering'),
  fork=["ForkChrome","ForkChrome.001","ForkUpper","ForkUpper.001"],engine="Crankcase")
body="--[[\n\tImportedModels  (ModuleScript, ReplicatedStorage/Shared)\n\n\tGENERATED by tools/glb_to_lua.py from the two .glb files in assets/models/.\n\tDo not edit by hand. Everything is in the glTF files' own axes and metres:\n\tpart names, colours/materials, which parts steer / spin, and the pivots and\n\taxes of the animated bits (kickstand, fuel tap, key, choke). BikeImport turns\n\tthis plus your imported MeshParts into a rigged, scaled bike.\n]]\n\nlocal V3 = Vector3\nlocal Vector3 = V3\n\nreturn {\n"+gen('aerox50',"aerox50.glb",aerox)+"\n"+gen('supermoto80',"supermoto80.glb",sm)+"\n}\n"
out = os.path.join(HERE, '..', 'src', 'ReplicatedStorage', 'Shared', 'ImportedModels.lua')
open(out, 'w').write(body)
print('wrote', out, len(body), 'bytes')
