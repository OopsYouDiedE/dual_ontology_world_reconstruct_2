"""Bounded propositional entailment for public desk/handbook interlock proofs."""
from itertools import product

from .physics import canonical


def entails(premises, conclusion):
    atoms = set()

    def collect(expr):
        if expr[0] in ('and','or','not'):
            for child in expr[1:]:
                collect(child)
        elif expr[0] not in ('true','false'):
            atoms.add(canonical(expr))

    for term in (*premises, conclusion):
        collect(term)
    if len(atoms) > 12:
        raise ValueError('document proof exceeds propositional atom budget')
    atoms = sorted(atoms)

    def test(expr, data):
        tag = expr[0]
        if tag == 'and': return all(test(x,data) for x in expr[1:])
        if tag == 'or': return any(test(x,data) for x in expr[1:])
        if tag == 'not': return not test(expr[1],data)
        if tag in ('true','false'): return tag == 'true'
        return data[canonical(expr)]

    reachable = False
    for assignment in product((False,True),repeat=len(atoms)):
        data = dict(zip(atoms,assignment))
        if all(test(x,data) for x in premises):
            reachable = True
            if not test(conclusion,data):
                return False
    return reachable   # require a nonvacuous proof


def desk_contract(lead, assignment, guard, positive, bypass):
    """The assigned team's shared window permits transfer and rules out bypass.

    This is deliberately conservative: atoms are independent. World generation
    separately exercises the certified operation and actual safety window.
    """
    return (entails([positive],guard) and entails([guard],['not',lead]) and
            entails([guard],['not',bypass]) and entails([assignment,guard],['not',lead]))
