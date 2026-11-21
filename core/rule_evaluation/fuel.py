"""Fuel meter, legal anytime output and an isolated data-only contestant VM."""
from dataclasses import dataclass
import sys

from .dsl import WAIT, compound

STANDARD_FUEL = 60_000
ENTRY_FUEL = 300_000
WAIT_PACKET = compound(WAIT)


class Exhausted(BaseException):
    pass


@dataclass
class Decision:
    actions: list
    fuel: int
    candidates: int
    exhausted: bool


class Meter:
    def __init__(self, fuel):
        self.maximum = self.remaining = fuel
        self.latest = WAIT_PACKET
        self.candidates = 0

    def spend(self, charge=1):
        if self.remaining < charge:
            self.remaining = 0
            raise Exhausted()
        self.remaining -= charge

    def emit(self, candidate):
        try:
            latest = compound(candidate)
        except (TypeError, ValueError, KeyError):
            return False
        self.latest = latest
        self.candidates += 1
        return True

    def run(self, produce):
        exhausted = False
        try:
            produce(self)
        except Exhausted:
            exhausted = True
        return Decision(self.latest, self.maximum - self.remaining, self.candidates, exhausted)


class TrustedPython:
    """In-repo reference code only. CPython bytecode fuel; no wall-clock cutoff.

    CPython version is part of the policy runtime fingerprint, since opcodes are
    versioned. Contestants without trusted source use the data-only VM instead.
    """
    def __init__(self, policy):
        self.policy = policy

    def __call__(self, observation, fuel):
        def produce(meter):
            def trace(frame, event, arg):
                if event == "call":
                    frame.f_trace_opcodes = True
                    frame.f_trace_lines = False
                elif event == "opcode":
                    meter.spend()
                return trace
            old = sys.gettrace()
            sys.settrace(trace)
            try:
                self.policy.decide(observation, meter.emit)
            finally:
                sys.settrace(old)
        return Meter(fuel).run(produce)


class PolicyVM:
    """Deterministic, data-only contestant runtime with 32 persistent registers.

    Static validation checks the instruction schema before any decision. Each
    instruction, path component, emitted action, and constructed node has a
    bounded charge. Registers can retain read-only observation values; the VM
    has no mutating container or host-side I/O instruction.
    """
    SIGNATURES = {"load":"rp", "const":"rc", "copy":"rr", "get":"rrr", "length":"rr",
                  "lt":"rrr", "eq":"rrr", "add":"rrr", "sub":"rrr", "mul":"rrr", "mod":"rrr",
                  "and":"rrr", "or":"rrr", "not":"rr", "jump":"j", "if":"rj", "emit":"r",
                  "object":"ro", "array":"ra", "stop":""}

    @staticmethod
    def key(v):
        return (type(v) is str and len(v) <= 100) or (type(v) is int and 0 <= v < 65536)

    @staticmethod
    def reg_index(v):
        return type(v) is int and 0 <= v < 32

    @staticmethod
    def bounded(value, meter=None):
        remaining = 128
        pending = [(value,0)]
        while pending:
            v,depth = pending.pop()
            remaining -= 1
            if meter is not None: meter.spend()
            if remaining < 0 or depth > 6: return False
            t = type(v)
            if v is None or t is bool: continue
            if t is int and -2**63 <= v < 2**63: continue
            if t is str and len(v) <= 1024: continue
            if t is list and len(v) <= 32:
                pending.extend((x,depth+1) for x in v)
                continue
            if t is dict and len(v) <= 32 and all(isinstance(k,str) and len(k)<=100 for k in v):
                pending.extend((x,depth+1) for x in v.values())
                continue
            return False
        return True

    def __init__(self, code):
        from copy import deepcopy
        if not isinstance(code, list) or not 1 <= len(code) <= 1024:
            raise ValueError("expected 1..1024 instructions")
        for i, line in enumerate(code):
            if not isinstance(line,list) or not line or not isinstance(line[0],str) or line[0] not in self.SIGNATURES:
                raise ValueError(f"unknown VM instruction at {i}")
            signature = self.SIGNATURES[line[0]]
            if len(line) != len(signature)+1:
                raise ValueError(f"wrong VM operand count at {i}")
            for kind,v in zip(signature,line[1:]):
                good = False
                if kind == "r": good = self.reg_index(v)
                elif kind == "j": good = type(v) is int and 0 <= v < len(code)
                elif kind == "c": good = self.bounded(v)
                elif kind == "p": good = isinstance(v,list) and len(v) <= 10 and all(self.key(k) for k in v)
                elif kind == "a": good = isinstance(v,list) and len(v) <= 16 and all(self.reg_index(k) for k in v)
                elif kind == "o":
                    good = isinstance(v,list) and len(v) <= 16 and all(isinstance(pair,list) and len(pair)==2
                        and isinstance(pair[0],str) and self.key(pair[0]) and self.reg_index(pair[1]) for pair in v)
                if not good: raise ValueError(f"invalid VM operand {kind} at {i}")
        self.code = deepcopy(code)
        self.reg = [None] * 32

    @staticmethod
    def get(value,key):
        if isinstance(value,dict) and isinstance(key,str): return value.get(key)
        if isinstance(value,list) and type(key) is int and 0 <= key < len(value): return value[key]
        return None

    @staticmethod
    def binary(op,a,b):
        if op == "eq": return type(a) in {bool,str,int,type(None)} and type(a) is type(b) and a==b
        if op == "and": return a is True and b is True
        if op == "or": return a is True or b is True
        if type(a) is not int or type(b) is not int: return None
        if op == "lt": return a < b
        if op == "mod": return a % b if b else None
        result = a+b if op=="add" else a-b if op=="sub" else a*b
        return max(-(1<<63),min((1<<63)-1,result))

    def __call__(self, observation, fuel):
        def produce(meter):
            r,pc = self.reg,0
            while pc < len(self.code):
                meter.spend()
                op,*args = self.code[pc]
                pc += 1
                if op == "stop": break
                if op == "jump":
                    pc = args[0]
                    continue
                if op == "if":
                    if r[args[0]] is True: pc = args[1]
                    continue
                if op == "emit":
                    meter.spend(8)
                    meter.emit(r[args[0]])
                    continue
                dst,*v = args
                if op == "const": value = v[0]
                elif op == "copy": value = r[v[0]]
                elif op == "get": value = self.get(r[v[0]],r[v[1]])
                elif op == "length": value = len(r[v[0]]) if type(r[v[0]]) in {str,list,dict} else None
                elif op == "not": value = r[v[0]] is not True
                elif op == "load":
                    value = observation
                    for key in v[0]:
                        meter.spend()
                        value = self.get(value,key)
                elif op == "object":
                    value = {k:r[j] for k,j in v[0]}
                    if not self.bounded(value,meter): value = None
                elif op == "array":
                    value = [r[j] for j in v[0]]
                    if not self.bounded(value,meter): value = None
                else: value = self.binary(op,r[v[0]],r[v[1]])
                r[dst] = value
        return Meter(fuel).run(produce)
