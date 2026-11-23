"""Build contact sheets from repository images and shaded OBJ geometry."""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

BITMAP = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif', '.ico'}


def mesh_view(path, angle, size=(246, 195)):
    vertices, faces = [], []
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        words = line.split()
        if words and words[0] == 'v':
            vertices.append(tuple(map(float, words[1:4])))
        elif words and words[0] == 'f':
            ids = [int(x.split('/')[0]) for x in words[1:]]
            faces.append([i-1 if i > 0 else len(vertices)+i for i in ids])
    if not vertices:
        raise ValueError('OBJ has no vertices')
    c, s = math.cos(angle), math.sin(angle)
    tilt = .29
    points = [(c*x+s*z, y*math.cos(tilt)-(-s*x+c*z)*math.sin(tilt),
               y*math.sin(tilt)+(-s*x+c*z)*math.cos(tilt)) for x,y,z in vertices]
    xs, ys, _ = zip(*points)
    cx, cy = (min(xs)+max(xs))/2, (min(ys)+max(ys))/2
    w, h = size
    scale = min((w-14)/max(1e-6,max(xs)-min(xs)), (h-14)/max(1e-6,max(ys)-min(ys)))
    canvas = Image.new('RGB', size, '#e0e5db')
    draw = ImageDraw.Draw(canvas)
    for face in sorted((f for f in faces if len(f)>=3), key=lambda f: sum(points[i][2] for i in f)/len(f)):
        ps = [points[i] for i in face]
        a,b,c = ps[:3]
        u,v = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
        n = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        length = math.sqrt(sum(x*x for x in n)) or 1
        shade = max(0,(-.4*n[0]+.65*n[1]+.64*n[2])/length)
        draw.polygon([(w/2+(x-cx)*scale,h/2-(y-cy)*scale) for x,y,z in ps],
                     fill=tuple(int(i*(.48+.52*shade)) for i in (220,191,142)))
    return canvas


def write_sheets(data, root, out):
    gallery = []
    for group, test in [('obj', lambda p:p.suffix.lower()=='.obj'),
                        ('images', lambda p:p.suffix.lower() in BITMAP)]:
        files = [f for f in data['files'] if f['kind']=='file' and test(Path(f['path']))]
        for start in range(0,len(files),12):
            batch = files[start:start+12]
            name = f'{group}-{start//12+1:02}.jpg'
            cell_w, cell_h = (270,230) if group=='obj' else (390,252)
            sheet = Image.new('RGB',(cell_w*3,cell_h*math.ceil(len(batch)/3)), '#f6f3e8')
            draw = ImageDraw.Draw(sheet)
            cards=[]
            for i,f in enumerate(batch):
                x,y=(i%3)*cell_w,(i//3)*cell_h
                p = root / f['path']
                f['media']={'sheet':name,'card':i+1}
                try:
                    if group=='obj':
                        half=(cell_w-26)//2
                        for j,angle in enumerate((.42,2.25)):
                            sheet.paste(mesh_view(p,angle,(half,cell_h-38)),(x+8+j*(half+6),y+8))
                    else:
                        with Image.open(p) as raw:
                            img=ImageOps.exif_transpose(raw).convert('RGBA')
                            img.thumbnail((cell_w-16,cell_h-36))
                            sheet.paste(img,(x+(cell_w-img.width)//2,y+8),img)
                except (OSError,ValueError,IndexError) as ex:
                    f['issues'].append(f'Preview: {ex}')
                    draw.text((x+8,y+16),'Preview unavailable', fill='#89381c')
                label = f'{i+1:02}  {p.name}'
                draw.text((x+8,y+cell_h-24),label,fill='#233332')
                cards.append(f['path'])
            sheet.save(out/name,quality=89,optimize=True)
            gallery.append({'group':group,'sheet':name,'paths':cards})
    return gallery
