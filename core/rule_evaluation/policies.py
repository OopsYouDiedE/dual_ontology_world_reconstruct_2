"""Authoring adapter for the existing reference policy; output enters the same lane."""
import ast
from pathlib import Path

from .sandbox import Program

REFLEX = '''\
def decide(o, state):
    q = o['self']['yaw']
    for hit in o['rays'][9:18]:
        if not isinstance(hit, dict):
            continue
        eid = hit['entity_id']
        if hit['hit_distance'] > 1700 or (eid == state.get('last') and o['last_result'] == 'OK'):
            continue
        ops = o['equipment'].get(eid, {}).get('operations', {})
        if eid == 'exit' or ops:
            state['last'] = eid
            return {'type':'Interact','target_entity_id':eid,'op_type':'traverse' if eid == 'exit' else list(ops)[0]}
    if o['self']['contacts'] or o['room_tick'] % 200 == 180:
        return {'type':'RotateYaw', 'delta_angle':90}
    return {'type':'Move','dir_vec':[sin(q)//1000,cos(q)//1000],'speed_ratio':70,'duration_ticks':20}
'''


class Flatten(ast.NodeTransformer):
    def __init__(self, methods):
        self.methods = methods
        self.unpack_index = 0

    def visit_Assign(self, node):
        if len(node.targets)==1 and isinstance(node.targets[0],ast.Tuple) and any(isinstance(t,(ast.Attribute,ast.Subscript)) for t in node.targets[0].elts):
            targets = node.targets[0].elts
            self.unpack_index += 1
            names = [f'reftmp{self.unpack_index}part{i}' for i in range(len(targets))]
            unpack = ast.Assign([ast.Tuple([ast.Name(s,ast.Store()) for s in names], ast.Store())], node.value)
            stores = [ast.Assign([t],ast.Name(s,ast.Load())) for t,s in zip(targets,names)]
            return [self.generic_visit(ast.copy_location(row,node)) for row in [unpack,*stores]]
        return self.generic_visit(node)

    def visit_Attribute(self, node):
        if isinstance(node.value, ast.Name) and node.value.id == 'self':
            return ast.copy_location(ast.Subscript(ast.Name('self', ast.Load()), ast.Constant(node.attr), node.ctx), node)
        return self.generic_visit(node)

    def visit_AugAssign(self, node):
        if isinstance(node.target, ast.Attribute) and isinstance(node.target.value, ast.Name) and node.target.value.id == 'self':
            src = ast.Attribute(node.target.value, node.target.attr, ast.Load())
            return self.visit(ast.Assign([node.target],ast.BinOp(src,node.op,node.value)))
        return self.generic_visit(node)

    def visit_Call(self, node):
        f = node.func
        if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == 'self' and f.attr in self.methods:
            args = ([] if self.methods[f.attr] else [ast.Name('self',ast.Load())]) + node.args
            return self.generic_visit(ast.Call(ast.Name('ref_'+f.attr,ast.Load()),args,node.keywords))
        if isinstance(f, ast.Name) and f.id == 'publish':
            node.func = ast.Name('emit',ast.Load())
        if isinstance(f, ast.Name) and f.id == 'round':
            value = node.args[0] if len(node.args)==1 else None
            if isinstance(value,ast.BinOp) and isinstance(value.op,ast.Div) and isinstance(value.right,ast.Constant) and value.right.value==100:
                return self.generic_visit(ast.Call(ast.Name('round100',ast.Load()),[value.left],[]))
            raise ValueError('reference must use deterministic bounded integer rounding')
        return self.generic_visit(node)


def reference_source(*, persuasion=True, phase_memory=True):
    module = ast.parse(Path(__file__).with_name('solver.py').read_text(encoding='utf-8-sig'))
    cls = next(n for n in module.body if isinstance(n,ast.ClassDef) and n.name=='TargetSolver')
    methods = {n.name:bool(n.decorator_list) for n in cls.body if isinstance(n,ast.FunctionDef) and n.name!='__init__'}
    flat = Flatten(methods)
    helpers = [n for n in module.body if isinstance(n,ast.FunctionDef)]
    for node in cls.body:
        if not isinstance(node, ast.FunctionDef) or node.name not in methods:
            continue
        node.name = 'ref_'+node.name
        node.decorator_list = []
        if node.name == 'ref_decide':
            assert node.args.args[-1].arg == 'publish'
            node.args.args.pop()
        helpers.append(flat.visit(node))
    entry = f'''

def round100(n):
    return (n+50-int(n//100%2==0))//100


def decide(o, state):
    if not state:
        state['level'] = None
        state['persuasion'] = {bool(persuasion)}
        state['phase_memory'] = {bool(phase_memory)}
    return ref_decide(state,o)
'''
    return ast.unparse(ast.fix_missing_locations(ast.Module(helpers,[])))+entry


def reference_program(**variant):
    return Program(reference_source(**variant))
