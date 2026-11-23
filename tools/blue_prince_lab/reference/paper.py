"""Generate resolution-independent drafting instruments, illustrated floor plans and paper ephemera."""
from pathlib import Path
import random,math,json
from mesh import OUT
from desks import CRTS
D=OUT/'interface';D.mkdir(parents=True,exist_ok=True)
r=random.Random(733)
def svg(name,w,h,lines): (D/(name+'.svg')).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'+''.join(lines)+'</svg>',encoding='utf8')
def rect(x,y,w,h,c,stroke='none',s=1):return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{c}" stroke="{stroke}" stroke-width="{s}"/>'
def path(d,c,t='none',w=1):return f'<path d="{d}" fill="{c}" stroke="{t}" stroke-width="{w}" stroke-linejoin="round"/>'
def line(x,y,X,Y,c,s=1):return path(f'M{x} {y}L{X} {Y}','none',c,s)
def ellipse(x,y,a,b,c):return f'<ellipse cx="{x}" cy="{y}" rx="{a}" ry="{b}" fill="{c}"/>'
def cards():
 for idx,name in enumerate(['Bedroom','Storeroom','Hallway']):
    colors=[['#7c6a90','#524556','#b197aa','#39313f'],['#296c92','#28374d','#4d5a69','#192435'],['#c58229','#846031','#ba8850','#53412d']][idx];rim,wall,floor,dark=colors
    a=[rect(0,0,260,260,rim,'#10171e',4),rect(23,21,214,218,dark,'#151921',2),rect(48,46,164,168,floor)];
    for i in range(15):
        y=46+i*12;a.append(line(47,y,213,y,dark,.7));
        for k in range(4):
            x=49+((k*47+i*17)%162);a.append(line(x,y,x,y+11,dark,.6))
    for shape in ['M23 21H237L211 47H49Z','M23 22L49 47V213L23 238Z','M237 22L211 47V213L237 238Z','M23 238L49 212H211L237 238Z']:a.append(path(shape,wall,'#25232b',2))
    for i in range(9):
        x=30+i*24;a.append(line(x,24,50+(x-24)*.76,45,dark,1));a.append(line(24,32+i*22,48,53+i*17,dark,1))
    def box(x,y,w,h,col,lip=4):a.extend([rect(x+3,y+4,w,h,'#292630'),rect(x,y,w,h,col,'#292532',1.6),rect(x+2,y+2,w-4,lip,'#ffffff33')]);
    if idx==0:
        box(69,39,52,67,'#695360');box(70,48,50,47,'#ac8898');box(74,43,42,15,'#d4bdc1');box(135,41,42,23,'#634852');box(49,136,22,61,'#66545d');box(96,114,69,74,'#8b677d');a.append(rect(101,119,59,64,'none','#bc9caa',2));box(171,177,24,26,'#634956');a.append(ellipse(179,177,8,7,'#ddc49b'))
    if idx==1:
        for x,y,w,h in [(45,49,27,151),(158,51,46,47),(143,158,60,42),(80,45,49,22)]:
            box(x,y,w,h,'#354253');
            for k in range(0,h-4,13):a.append(rect(x+2,y+k+1,w-4,3,'#65707a'))
        for i in range(11):
            x,y=r.choice([75,85,147,165])+r.randrange(10),r.randrange(82,193);box(x,y,18,17,'#685749');a.append(line(x+1,y+2,x+17,y+15,'#413937',2))
    if idx==2:
        for x in [49,171]:
            box(x,44,39,64,'#8a6838');box(x,152,39,61,'#946d42');
            for j in [60,185]:a.extend([ellipse(x+18,j+2,9,7,'#645235'),ellipse(x+18,j,6,6,'#f2cd84')]);
        a.extend([rect(99,45,63,170,'#ac854b'),line(103,45,103,213,'#d0a868',2),line(157,45,157,213,'#d0a868',2)])
    for k in range(230):
        x,y=r.uniform(47,208),r.uniform(47,209);a.append(line(x,y,x+r.uniform(1,6),y-.7,'#c8b8ab',.29))
    a.extend([path('M109 260L111 232L116 214H145L151 236L151 260Z','#12141b'),line(0,0,24,22,'#171824',2),line(260,0,236,22,'#171824',2)])
    svg(name,260,260,a)

def instruments():
 a=[rect(0,0,1280,243,'#1a669a','#b7c7d1',3)]
 for k in range(160):
    x=k*8;a.append(line(x,2,x,241,'#3785b2' if k%5 else '#5991b0',.5 if k%5 else 1))
 for k in range(30):a.append(line(2,k*8,1278,k*8,'#3785b2' if k%5 else '#6099b7',.65))
 for i in range(240):
    x,y=r.uniform(0,1280),r.uniform(1,240);a.append(line(x,y,x+r.uniform(2,22),y+.25,'#6599b2',.45))
 svg('Board',1280,243,a)
 a=[path('M0 1H177V32H31V284H0Z','#7fada8','#283d43',2)];
 for j in range(35):a.append(line(j*5,1,j*5,12 if j%5==0 else 7,'#dae5db',.8))
 for j in range(56):a.append(line(1,j*5,13 if j%5==0 else 7,j*5,'#d9e4da',.8))
 svg('Rule',178,285,a)
 a=[path('M0 0H205L0 337ZM32 35V218L146 35Z','#709f99','#233b41',3).replace('<path ','<path fill-rule="evenodd" ')];
 for j in range(40):a.append(line(j*5,1,j*5,11 if j%5==0 else 6,'#d3dfd5',.8))
 svg('Square',208,340,a)

def symbols():
 svg('Key',32,32,[path('M6 28L19 15M8 25l-3-3M12 21l-3-3','none','#81a7c8',3),path('M18 8Q20 2 26 4Q33 6 28 13Q25 18 20 15Q16 13 18 8Z','none','#aac8dc',2.8)])
 svg('Gem',32,32,[path('M2 10L9 5H24L31 10 17 26Z','#704c6b','#e7bad3',1.5),path('M2 10H31M9 5L12 10 17 26 22 10 24 5M12 10L17 5 22 10','none','#e9c4d8',1.4)])
 svg('Coin',32,32,[ellipse(19,19,11,10,'#635436'),ellipse(16,15,11,10,'#d0b678'),ellipse(16,15,8,7,'#8e764b'),ellipse(16,15,6.5,5.5,'#c4a96e'),path('M16 11l2 3 2 1-2 1-2 3-1-2-2-2 2-2Z','#e5c888')])

def generate():
 r.seed(733); symbols(); cards();instruments();(D/'cabinets.json').write_text(json.dumps(CRTS))

if __name__=='__main__': generate()
