"""Shared, observation-only policy lane. See docs/design/rule-policy-lane.md."""
import ast
from copy import deepcopy
from hashlib import sha256
from math import isqrt
import operator
import sys

from .fuel import Decision, Exhausted, Meter
from .physics import cos, dist2, sin
from .dsl import WAIT

LANE_ID = 'rule-policy/guarded-python-opcode-v2'
MAX_CONTAINER = 2048
MAX_STATE_NODES = 12000
MAX_INT = (1 << 63) - 1
SOURCE_LIMIT = 128_000

TYPES = {'int': int, 'str': str, 'bool': bool, 'dict': dict, 'list': list, 'tuple': tuple, 'set': set}
FUNCTIONS = TYPES.keys() | set('abs all any cos dist2 enumerate isqrt len match max min next range reversed sin sorted sum zip emit'.split())
METHODS = set('add append clear copy extend get items keys pop removesuffix split setdefault update values'.split())
NODES = set('Module FunctionDef arguments arg Return Assign AugAssign If For While Break Continue Pass Expr Name Load Store Constant List Tuple Set Dict BinOp UnaryOp BoolOp Compare IfExp Call keyword Subscript Slice Starred GeneratorExp ListComp DictComp SetComp comprehension Lambda Add Sub Mult FloorDiv Mod Pow BitAnd BitOr USub UAdd Not And Or Eq NotEq Lt LtE Gt GtE In NotIn Is IsNot'.split())
BIN = {k: getattr(operator, v) for k, v in dict(Add='add', Sub='sub', Mult='mul', FloorDiv='floordiv', Mod='mod', Pow='pow', BitAnd='and_', BitOr='or_').items()}
CMP = {k: getattr(operator, v) for k, v in dict(Eq='eq', NotEq='ne', Lt='lt', LtE='le', Gt='gt', GtE='ge', Is='is_', IsNot='is_not').items()}


class PolicyFault(ValueError):
    pass


def guarded(name, *args):
    return ast.Call(ast.Name('__' + name, ast.Load()), list(args), [])


class Compiler(ast.NodeTransformer):
    """Policy source has no Python object-model access, exception handlers, or imports."""
    def __init__(self, tree):
        self.functions = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
        if 'decide' not in self.functions or len(tree.body) != len(self.functions):
            raise PolicyFault('module must contain unique functions including decide(o, state)')
        for node in tree.body:
            if node.name in FUNCTIONS or node.name in {'WAIT', 'isinstance'} or node.decorator_list or node.returns:
                raise PolicyFault('reserved function name, decorator or annotation')
            if node.name == 'decide' and (len(node.args.args) != 2 or node.args.vararg or node.args.kwarg or node.args.kwonlyargs or node.args.posonlyargs):
                raise PolicyFault('expected decide(o, state)')

    def visit(self, node):
        if type(node).__name__ not in NODES:
            raise PolicyFault(f'unsupported syntax {type(node).__name__} at line {getattr(node,"lineno",0)}')
        return super().visit(node)

    @staticmethod
    def name(value):
        if not value.isascii() or value.startswith('_') and value != '_':
            raise PolicyFault('private or non-ASCII identifier')

    def visit_Name(self, n):
        self.name(n.id)
        if isinstance(n.ctx, ast.Store) and (n.id in FUNCTIONS or n.id in {'isinstance','WAIT'}):
            raise PolicyFault('cannot rebind a lane primitive')
        return n

    def visit_arg(self, n):
        self.name(n.arg)
        if n.annotation or n.arg in FUNCTIONS or n.arg in {'isinstance','WAIT'}:
            raise PolicyFault('annotated or reserved argument')
        return n

    def visit_FunctionDef(self, n):
        self.name(n.name)
        if n.name not in self.functions or n.decorator_list or n.returns:
            raise PolicyFault('invalid function declaration')
        if any(not isinstance(d, ast.Constant) for d in n.args.defaults + [d for d in n.args.kw_defaults if d]):
            raise PolicyFault('function defaults must be scalar constants')
        return self.generic_visit(n)

    def visit_Constant(self, n):
        if not (type(n.value) in {str, int, bool, type(None)} and
                (type(n.value) != str or len(n.value) <= MAX_CONTAINER) and
                (type(n.value) != int or abs(n.value) <= MAX_INT)):
            raise PolicyFault('constant outside scalar domain')
        return n

    def visit_Call(self, n):
        if any(k.arg is None for k in n.keywords):
            raise PolicyFault('keyword unpacking is unavailable')
        args = [self.visit(x) if not isinstance(x, ast.Starred) else
                ast.Starred(guarded('iterate', self.visit(x.value)), x.ctx) for x in n.args]
        kwargs = [self.visit(k) for k in n.keywords]
        if isinstance(n.func, ast.Attribute) and n.func.attr in METHODS:
            return ast.copy_location(ast.Call(ast.Name('__method', ast.Load()),
                [self.visit(n.func.value), ast.Constant(n.func.attr), *args], kwargs), n)
        if not isinstance(n.func, ast.Name) or n.func.id not in self.functions | FUNCTIONS | {'isinstance'}:
            raise PolicyFault(f'call must name a policy function or public primitive at line {n.lineno}')
        return ast.copy_location(ast.Call(n.func, args, kwargs), n)

    def visit_BinOp(self, n):
        return ast.copy_location(guarded('binary', ast.Constant(type(n.op).__name__), self.visit(n.left), self.visit(n.right)), n)

    def visit_Compare(self, n):
        # Thunks preserve short-circuiting and evaluate each middle operand once.
        empty = ast.arguments([], [], None, [], [], None, [])
        return ast.copy_location(guarded('compare', ast.Tuple([ast.Constant(type(v).__name__) for v in n.ops], ast.Load()),
            *[ast.Lambda(empty, self.visit(v)) for v in [n.left, *n.comparators]]), n)

    def visit_Subscript(self, n):
        key = n.slice
        if isinstance(key, ast.Slice):
            key = guarded('slice', *[self.visit(v) if v is not None else ast.Constant(None) for v in (key.lower, key.upper, key.step)])
        else:
            key = self.visit(key)
        if not isinstance(n.ctx, ast.Load):
            raise PolicyFault('use standalone subscript assignment')
        return ast.copy_location(guarded('get', self.visit(n.value), key), n)

    def visit_Assign(self, n):
        if len(n.targets) == 1 and isinstance(n.targets[0], ast.Subscript):
            t = n.targets[0]
            key = t.slice
            if isinstance(key, ast.Slice):
                key = guarded('slice', *[self.visit(v) if v is not None else ast.Constant(None) for v in (key.lower, key.upper, key.step)])
            else:
                key = self.visit(key)
            return ast.copy_location(ast.Expr(guarded('put', self.visit(n.value), self.visit(t.value), key)), n)
        n = self.generic_visit(n)
        unpack = [t for t in n.targets if isinstance(t,(ast.Tuple, ast.List))]
        if unpack:
            if len(n.targets) != 1:
                raise PolicyFault('use standalone unpack assignment')
            n.value = guarded('unpack',n.value,self.unpack_pattern(unpack[0]))
        return n

    def visit_AugAssign(self, n):
        if not isinstance(n.target, ast.Name):
            raise PolicyFault('use plain assignment for subscript updates')
        return self.visit_Assign(ast.copy_location(ast.Assign([n.target],
            ast.BinOp(ast.Name(n.target.id, ast.Load()), n.op, n.value)), n))

    def unpack_pattern(self, target):
        if isinstance(target, (ast.Tuple, ast.List)):
            return ast.Tuple([self.unpack_pattern(x) for x in target.elts], ast.Load())
        if isinstance(target, ast.Starred):
            if not isinstance(target.value, ast.Name):
                raise PolicyFault('starred unpack target must be a name')
            return ast.Constant(True)
        return ast.Constant(None)

    def bind_loop(self, n):
        n = self.generic_visit(n)
        n.iter = guarded('iterate', n.iter, self.unpack_pattern(n.target))
        return n

    visit_For = bind_loop
    visit_comprehension = bind_loop

    def visit_Starred(self,n):
        n = self.generic_visit(n)
        if isinstance(n.ctx,ast.Load):
            n.value = guarded('iterate',n.value)
        return n

    def visit_Dict(self, n):
        if any(k is None for k in n.keys):
            raise PolicyFault('dictionary unpacking is unavailable')
        if all(isinstance(k, ast.Constant) for k in n.keys):
            return self.generic_visit(n)
        return ast.copy_location(guarded('make_dict', ast.Tuple([ast.Tuple([self.visit(k), self.visit(v)], ast.Load())
            for k,v in zip(n.keys,n.values)], ast.Load())), n)

    def visit_Set(self, n):
        return ast.copy_location(guarded('make_set', ast.Tuple([self.visit(v) for v in n.elts], ast.Load())), n)

    def visit_DictComp(self, n):
        g = ast.GeneratorExp(ast.Tuple([n.key, n.value], ast.Load()), n.generators)
        return ast.copy_location(guarded('make_dict', self.visit(g)), n)

    def visit_SetComp(self, n):
        return ast.copy_location(guarded('make_set', self.visit(ast.GeneratorExp(n.elt, n.generators))), n)

    def visit_ListComp(self, n):
        return ast.copy_location(guarded('make_list', self.visit(ast.GeneratorExp(n.elt, n.generators))), n)

    def visit_Lambda(self, n):
        if n.args.defaults or n.args.kw_defaults:
            raise PolicyFault('lambda defaults are unavailable')
        return self.generic_visit(n)


def normalized_source(source):
    return source.replace('\r\n','\n').replace('\r','\n')


class Program:
    def __init__(self, source):
        if not isinstance(source, str) or len(source.encode('utf-8')) > SOURCE_LIMIT:
            raise PolicyFault('source exceeds policy limit')
        source = normalized_source(source)
        self.sha256 = sha256(source.encode('utf-8')).hexdigest()
        self.filename = f'<rule-policy:{self.sha256[:12]}>'
        try:
            tree = ast.parse(source, self.filename)
            if sum(1 for _ in ast.walk(tree)) > 24_000:
                raise PolicyFault('policy exceeds AST size limit')
            self.code = compile(ast.fix_missing_locations(Compiler(tree).visit(tree)), self.filename, 'exec', dont_inherit=True, optimize=0)
        except (SyntaxError, RecursionError, TypeError) as err:
            raise PolicyFault(f'cannot compile policy: {err}') from err

    def start(self):
        return Lane(self)


class Lane:
    def __init__(self, program):
        self.state = {}
        self.program = program
        g = {'__builtins__':{}, 'WAIT':dict(WAIT), 'isinstance':self.is_instance}
        g.update({f'__{name}':getattr(self, name) for name in (
            'binary','compare','get','put','iterate','unpack','method','make_dict','make_set','make_list')})
        g['__slice'] = slice
        g.update({name:getattr(self, 'f_'+name) for name in FUNCTIONS})
        exec(program.code, g, g)
        self.decide = g['decide']
        self.globals = g

    def __call__(self, observation, fuel):
        self.meter = Meter(fuel)
        self.line = 0
        self.depth = 0
        self.rejected = 0
        exhausted = False
        fault = None
        # State is isolated from the referee and from a failed/timed-out commit.
        working_state = deepcopy(self.state)
        old = sys.gettrace()
        sys.settrace(self.trace)
        try:
            self.globals['WAIT'] = dict(WAIT)
            action = self.decide(deepcopy(observation), working_state)
            if action is not None:
                self.f_emit(action)
            self.check_state(working_state)
            self.state = working_state
        except Exhausted:
            exhausted = True
        except (ValueError, TypeError, IndexError, KeyError, ArithmeticError, RuntimeError, NameError, AttributeError) as err:
            fault = {'type':type(err).__name__, 'line':self.line}
        finally:
            sys.settrace(old)
        m = self.meter
        return Decision(m.latest, m.maximum-m.remaining, m.candidates, exhausted, fault, self.line if exhausted else None, self.rejected)

    def trace(self, frame, event, arg):
        if event == 'call':
            if frame.f_code.co_filename != self.program.filename:
                return None
            self.depth += 1
            if self.depth > 64:
                raise PolicyFault('policy call depth exceeded')
            frame.f_trace_opcodes = True
            frame.f_trace_lines = False
        elif event == 'opcode':
            self.line = frame.f_lineno
            self.meter.spend()
        elif event == 'return':
            self.depth -= 1
        return self.trace

    def shape(self, value, *, depth=0, bound=128):
        # Bound recursive hashing/comparison. Charge expanded occurrences even for DAG aliases.
        if bound < 1 or depth > 10:
            raise PolicyFault('compound operand too large')
        self.meter.spend()
        t = type(value)
        if t is str:
            self.meter.spend(len(value)//32)
        if t in (list, tuple, set, dict):
            for key in value:
                bound = self.shape(key, depth=depth+1, bound=bound-1)
                if t is dict:
                    bound = self.shape(value[key], depth=depth+1, bound=bound-1)
        return bound

    def check_state(self, state):
        pending = [(state, 0)]
        # Shared references in state count by occurrence. Depth also rejects cycles.
        nodes = 0
        while pending:
            item, depth = pending.pop()
            nodes += 1
            self.meter.spend()
            t = type(item)
            if depth > 24 or nodes > MAX_STATE_NODES:
                raise PolicyFault('policy memory bound exceeded')
            if t in (list, tuple, set, dict):
                if len(item) > MAX_CONTAINER:
                    raise PolicyFault('policy container bound exceeded')
                pending.extend((v, depth+1) for v in item)
                if t is dict:
                    pending.extend((v, depth+1) for v in item.values())
            elif t not in (type(None), int, bool, str) or (t is str and len(item) > MAX_CONTAINER) or (t is int and abs(item) > MAX_INT):
                raise PolicyFault('only bounded data may persist')

    def key(self, item, depth=0):
        """Validate hash keys and provide a locale/host-independent set ordering."""
        self.meter.spend()
        if depth > 8:
            raise PolicyFault('key nesting exceeds bound')
        t = type(item)
        if t is tuple:
            if len(item) > 16:
                raise PolicyFault('key tuple exceeds bound')
            return (4,tuple(self.key(v,depth+1) for v in item))
        if t is str:
            self.meter.spend(len(item)//32)
            return (3,item)
        if t is int: return (2,item)
        if t is bool: return (1,item)
        if item is None: return (0,0)
        raise PolicyFault('hash keys must be scalar or tuples of keys')

    def binary(self, op, a, b):
        self.meter.spend(2)
        if op in ('FloorDiv','Mod','Pow') and (type(a) is not int or type(b) is not int):
            raise PolicyFault('integer operands required')
        if op in ('BitOr','BitAnd') and type(a) is dict:
            raise PolicyFault('use bounded dict.update')
        if op == 'Pow' and (type(a) is not int or type(b) is not int or not 0 <= b <= 12 or abs(a).bit_length()*b > 96):
            raise PolicyFault('unsafe exponent')
        if op == 'Mult' and (type(a) in (str,list,tuple) or type(b) in (str,list,tuple)):
            seq, n = (a,b) if type(a) in (str,list,tuple) else (b,a)
            if type(n) is not int or len(seq)*max(0,n) > MAX_CONTAINER:
                raise PolicyFault('sequence multiplier out of bounds')
            self.meter.spend(len(seq)*max(0,n)//16)
        if op == 'Add' and type(a) is type(b) and type(a) in (str,list,tuple):
            if len(a)+len(b) > MAX_CONTAINER:
                raise PolicyFault('sequence exceeds size budget')
            self.meter.spend((len(a)+len(b))//16)
        if type(a) is set or type(b) is set:
            self.shape(a, bound=MAX_CONTAINER)
            self.shape(b, bound=MAX_CONTAINER)
        result = BIN[op](a,b)
        if (type(result) is int and abs(result) > MAX_INT) or (type(result) in (dict,set) and len(result) > MAX_CONTAINER):
            raise PolicyFault('arithmetic outside value domain')
        return result

    def compare(self, ops, first, *rest):
        a = first()
        for op, thunk in zip(ops, rest):
            b = thunk()
            if op in ('In','NotIn'):
                if type(b) not in (dict,set,str,list,tuple,range):
                    raise PolicyFault('membership requires a bounded container')
                if type(b) in (dict,set):
                    self.key(a)
                else:
                    self.shape(a)
                if type(b) in (list,tuple):
                    # Charge and bound each item the native membership may compare.
                    for v in b:
                        self.shape(v)
                    self.meter.spend(len(b))
                if type(b) is str:
                    self.meter.spend(len(b)//16)
                ok = a in b
                if op == 'NotIn':
                    ok = not ok
            else:
                if op not in ('Is','IsNot'):
                    self.shape(a)
                    self.shape(b)
                ok = CMP[op](a,b)
            if not ok:
                return False
            a = b
        return True

    def get(self, obj, key):
        self.meter.spend(2)
        if type(obj) is dict:
            self.key(key)
        if type(key) is slice:
            self.meter.spend(len(obj)//16)
        return obj[key]

    def put(self, value, obj, key):
        self.meter.spend(3)
        if type(obj) is dict:
            self.key(key)
            if len(obj) >= MAX_CONTAINER and key not in obj:
                raise PolicyFault('dictionary full')
        if type(key) is slice:
            value = self.make_list(value)
            if len(obj)+len(value) > MAX_CONTAINER:
                raise PolicyFault('slice assignment too large')
            self.meter.spend(len(obj)//16)
        obj[key] = value

    def iterate(self, seq, pattern=None):
        if type(seq) is set:
            # Never expose hash-table iteration order to policies.
            self.meter.spend(len(seq)*max(1,len(seq).bit_length()))
            raw = iter(sorted(seq,key=self.key))
        else:
            raw = self.iter_raw(seq)
        return raw if pattern is None else (self.unpack(item,pattern) for item in raw)

    def unpack(self, seq, pattern):
        if pattern is None or pattern is True:
            return seq
        if type(seq) in (list,tuple) and all(p is None for p in pattern):
            return seq
        values = self.make_list(seq)
        if True not in pattern:
            return tuple(self.unpack(v,p) for v,p in zip(values,pattern)) if len(values)==len(pattern) else values
        star = pattern.index(True)
        suffix = len(pattern)-star-1
        if len(values) < star+suffix:
            return values
        return tuple([self.unpack(v,p) for v,p in zip(values[:star],pattern[:star])] +
                     values[star:len(values)-suffix] +
                     [self.unpack(v,p) for v,p in zip(values[len(values)-suffix:],pattern[star+1:])])

    def iter_raw(self, seq):
        for i, value in enumerate(seq):
            if i >= MAX_CONTAINER:
                raise PolicyFault('iteration exceeds bound')
            self.meter.spend()
            yield value

    def make_dict(self, seq=()):
        out = {}
        if type(seq) is dict:
            seq = seq.items()
        for k,v in self.iterate(seq):
            self.key(k)
            out[k] = v
        return out

    def make_set(self, seq=()):
        out = set()
        for v in self.iterate(seq):
            self.key(v)
            out.add(v)
        return out

    def make_list(self, seq=()):
        return list(self.iterate(seq))

    def method(self, obj, name, *args):
        self.meter.spend(3)
        t = type(obj)
        if t is dict and name in ('keys','items','values','copy','clear'):
            self.meter.spend(len(obj))
            result = getattr(obj,name)(*args)
            return list(result) if name in ('keys','items','values') else result
        if t is dict and name in ('get','pop','setdefault') and args:
            self.key(args[0])
            if name == 'setdefault' and len(obj) >= MAX_CONTAINER and args[0] not in obj:
                raise PolicyFault('dictionary full')
            return getattr(obj,name)(*args)
        if t is dict and name == 'update' and len(args) == 1:
            for key,value in self.make_dict(args[0]).items():
                self.put(value,obj,key)
            return None
        if t in (list,set) and name in ('clear','copy'):
            self.meter.spend(len(obj))
            return getattr(obj,name)(*args)
        if t is list and name == 'pop':
            self.meter.spend(len(obj)//16)
            return obj.pop(*args)
        if (t,name) in ((list,'append'),(set,'add')) and len(args) == 1:
            if len(obj) >= MAX_CONTAINER:
                raise PolicyFault('container full')
            if t is set:
                self.key(args[0])
            return getattr(obj,name)(*args)
        if (t,name) in ((list,'extend'),(set,'update')) and len(args) == 1:
            new = self.make_list(args[0]) if t is list else self.make_set(args[0])
            if len(obj)+len(new) > MAX_CONTAINER:
                raise PolicyFault('container full')
            return getattr(obj,name)(new)
        if t is str and name in ('removesuffix','split'):
            self.meter.spend(len(obj)+1)
            return getattr(obj,name)(*args)
        raise PolicyFault('method unavailable for this receiver')

    def is_instance(self, value, category):
        # The visible type tokens are the corresponding wrapped constructors.
        self.meter.spend()
        if type(category) is tuple:
            return any(self.is_instance(value,item) for item in category)
        t = type(value)
        return t in TYPES.values() and category is self.globals[t.__name__]

    def f_emit(self, action):
        # Compound validation is bounded independently of policy-created object graphs.
        self.shape(action, bound=256)
        self.meter.spend(8)
        accepted = self.meter.emit(action)
        if not accepted:
            self.rejected += 1
        return accepted

    def f_sorted(self, seq, *, key=None, reverse=False):
        return self.order(self.make_list(seq), key=key, reverse=reverse)

    def order(self, values, *, key=None, reverse=False):
        decorated = []
        for i,v in enumerate(values):
            k = key(v) if key is not None else v
            cost = 128-self.shape(k)
            self.meter.spend((cost+1)*max(1,len(values).bit_length()))
            decorated.append((k,i,v))
        decorated.sort(key=lambda x:x[0], reverse=reverse)
        return [p[2] for p in decorated]

    def extreme(self, compare, *values, key=None, **options):
        seq = self.iterate(values[0]) if len(values)==1 else iter(values)
        found = False
        for i in seq:
            k = key(i) if key is not None else i
            self.shape(k)
            if not found or compare(k,best_key):
                best, best_key, found = i, k, True
        if found:
            return best
        if 'default' in options:
            return options['default']
        raise PolicyFault('empty extrema')

    def f_min(self, *values, **kwargs): return self.extreme(operator.lt,*values,**kwargs)
    def f_max(self, *values, **kwargs): return self.extreme(operator.gt,*values,**kwargs)
    def f_range(self, *args):
        r = range(*args)
        if len(r) > MAX_CONTAINER:
            raise PolicyFault('range exceeds size bound')
        return r
    def f_sum(self, seq, start=0):
        for v in self.iterate(seq):
            start = self.binary('Add', start, v)
        return start
    def f_any(self, seq): return any(self.iterate(seq))
    def f_all(self, seq): return all(self.iterate(seq))
    def f_next(self, seq, default=None):
        self.meter.spend()
        return next(seq,default)
    def f_reversed(self, seq):
        self.meter.spend(len(seq)//16)
        return reversed(seq)
    def f_enumerate(self, seq, start=0): return enumerate(self.iterate(seq),start)
    def f_zip(self, *args): return zip(*(self.iterate(v) for v in args))
    def f_list(self, seq=()): return self.make_list(seq)
    def f_tuple(self, seq=()): return tuple(self.iterate(seq))
    def f_dict(self, seq=()): return self.make_dict(seq)
    def f_set(self, seq=()): return self.make_set(seq)
    def f_str(self, value=''):
        if type(value) not in (str,int,bool,type(None)):
            raise PolicyFault('str accepts scalars only')
        return str(value)
    def f_int(self, value=0):
        if type(value) not in (str,int,bool) or (type(value) is str and len(value)>20):
            raise PolicyFault('int accepts bounded scalars only')
        result = int(value)
        if abs(result) > MAX_INT:
            raise PolicyFault('integer out of bounds')
        return result
    def f_match(self, pattern, action):
        return all(self.compare(('Eq',),lambda:action.get(k),lambda:v) for k,v in self.iterate(pattern.items()))
    f_abs = staticmethod(abs)
    f_len = staticmethod(len)
    f_bool = staticmethod(bool)
    f_isqrt = staticmethod(isqrt)
    f_sin = staticmethod(sin)
    f_cos = staticmethod(cos)
    def f_dist2(self, a,b):
        if type(a) not in (tuple,list) or type(b) not in (tuple,list) or any(type(x) is not int for x in (a[0],a[1],b[0],b[1])):
            raise PolicyFault('dist2 requires integer vectors')
        value = dist2(a,b)
        if value > MAX_INT:
            raise PolicyFault('distance outside value domain')
        return value
