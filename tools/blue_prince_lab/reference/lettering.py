from PIL import Image, ImageFont, ImageDraw
from math import sin,cos,radians,degrees,pi
from mesh import OUT

def lettering():
    # Ink lies on the chapter ring. Only the lettering lives in this texture.
    im=Image.new('RGBA',(1024,1024)); font=ImageFont.load_default(size=31)
    for text,center,r,reverse in [('V I A N N E Y   H A L T E R',89,.966,False),('Deep  Space',256,.964,True)]:
        widths=[font.getlength(c)+1 for c in text]; px=r*1024/2.72; angle=radians(center)+(1 if not reverse else -1)*sum(widths)/2/px
        for char,w in zip(text,widths):
            step=(1 if reverse else -1)*w/px; a=angle+step/2; tile=Image.new('RGBA',(66,66));ImageDraw.Draw(tile).text((33,33),char,font=font,anchor='mm',fill='#2c2a2e');tile=tile.rotate(degrees(a)-(270 if reverse else 90),Image.Resampling.BICUBIC)
            im.alpha_composite(tile,(round(512+px*cos(a)-33),round(512-px*sin(a)-33)));angle+=step
    im.save(OUT/'ChapterInk.png')
