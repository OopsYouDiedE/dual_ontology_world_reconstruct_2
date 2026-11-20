from outside import landscape_modules,outside
from inside import chapel,attic
from watch import watch
from desks import security,darkroom,lobby
from paper import generate

if __name__=='__main__':
    landscape_modules(); outside(False); outside(True); chapel(); attic(); watch()
    from lettering import lettering; lettering()
    security(); darkroom(); lobby(); generate()
