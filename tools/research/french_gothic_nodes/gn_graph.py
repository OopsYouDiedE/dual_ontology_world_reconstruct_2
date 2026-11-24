import bpy

F, I, B, G = ['NodeSocket'+x for x in ('Float','Int','Bool','Geometry')]


class Graph:
    def __init__(self, name, specs):
        self.tree = bpy.data.node_groups.new(name, 'GeometryNodeTree')
        for key, kind, default, lo, hi in specs:
            s = self.tree.interface.new_socket(name=key, in_out='INPUT', socket_type=kind)
            if default is not None: s.default_value = default
            if lo is not None: s.min_value, s.max_value = lo, hi
        self.tree.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type=G)
        self.i = self.node('NodeGroupInput').outputs

    def node(self, typ, **props):
        n = self.tree.nodes.new(typ)
        for k, v in props.items(): setattr(n, k, v)
        return n

    def put(self, n, key, val):
        if isinstance(val, bpy.types.NodeSocket): self.tree.links.new(val, n.inputs[key])
        else: n.inputs[key].default_value = val

    def op(self, typ, args, **props):
        n = self.node(typ, **props)
        for k, v in args: self.put(n,k,v)
        return n.outputs[0]

    def math(self, op, a, b): return self.op('ShaderNodeMath', [(0,a),(1,b)], operation=op)
    def xyz(self,x,y,z): return self.op('ShaderNodeCombineXYZ',list(enumerate([x,y,z])))
    def move(self,g,t): return self.op('GeometryNodeTransform',[('Geometry',g),('Translation',t)])
    def join(self,*parts): return self.op('GeometryNodeJoinGeometry',[(0,p) for p in parts])
    def end(self, result):
        n = self.node('NodeGroupOutput'); self.put(n,0,result)
        # Arrange by dependency depth; keep independent branches readable.
        levels = {}
        def level(n):
            if n.name not in levels:
                levels[n.name] = 1+max((level(l.from_node) for s in n.inputs for l in s.links), default=-1)
            return levels[n.name]
        rows = {}
        for n in self.tree.nodes:
            col = level(n); n.location = (250*col, rows.get(col,0)); n.width = 200
            rows[col] = n.location.y-105-26*(len(n.inputs)+len(n.outputs))
        return self.tree


def num(k,d,lo,hi,kind=F): return k,kind,d,lo,hi

def toggle(k): return k,B,True,None,None
