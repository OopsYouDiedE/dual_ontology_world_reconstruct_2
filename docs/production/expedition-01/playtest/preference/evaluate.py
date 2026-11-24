"""Fit and validate a three-outcome preference model from human judgments only."""
import argparse
import csv
from dataclasses import dataclass
import json
import math
import re
import sys
from pathlib import Path

OUTCOMES = ('A', 'B', 'tie')
FIELDS = ('evaluator_id', 'trial_id', 'layout_a', 'layout_b', 'choice', 'source')


@dataclass(frozen=True)
class Vote:
    evaluator: str
    family: str
    dx: tuple
    choice: int


def load(layout_file, label_file):
    with label_file.open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        if not rows:
            raise ValueError('no human labels; no scores emitted')
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError('unexpected label header')
    registry = json.loads(layout_file.read_text(encoding='utf-8'))
    names, layouts = registry['features'], registry['layouts']
    if not isinstance(names, list) or not 1 <= len(names) <= 16 or any(
            not isinstance(n, str) or not n for n in names) or len(set(names)) != len(names):
        raise ValueError('expected 1–16 unique named features')
    for spec in layouts.values():
        x, family = spec['x'], spec['family']
        if not isinstance(family, str) or not family.strip() or not isinstance(x, list) or len(x) != len(names) or any(
                type(v) not in (int, float) or not -1 <= v <= 1 for v in x):
            raise ValueError('each layout needs a family and finite features in [-1, 1]')
    votes, seen, trials = [], set(), {}
    for line, row in enumerate(rows, 2):
        if None in row or any(v is None for v in row.values()) or row['source'] != 'human':
            raise ValueError(f'row {line}: expected one human judgment; no scores emitted')
        evaluator, trial, a, b, choice, _ = (row[k] for k in FIELDS)
        if not re.fullmatch(r'p_[0-9a-f]{16}', evaluator) or not re.fullmatch(r'[\w.-]+', trial):
            raise ValueError(f'row {line}: expected opaque evaluator token and trial ID')
        if a == b or a not in layouts or b not in layouts or choice not in OUTCOMES:
            raise ValueError(f'row {line}: invalid layouts or choice')
        pair = tuple(sorted((a, b)))
        if trials.setdefault(trial, pair) != pair or (evaluator, trial) in seen:
            raise ValueError(f'row {line}: reused evaluator/trial or inconsistent trial pair')
        seen.add((evaluator, trial))
        first, second = layouts[a], layouts[b]
        if first['family'] != second['family']:
            raise ValueError(f'row {line}: both layouts must belong to the same structure family')
        votes.append(Vote(evaluator, first['family'], tuple(x-y for x, y in zip(first['x'], second['x'])),
                          OUTCOMES.index(choice)))
    return names, votes


def log_probs(params, dx):
    d = .5 * sum(w*x for w, x in zip(params[:-1], dx))
    logits = (d, -d, params[-1])
    top = max(logits)
    normalizer = top + math.log(sum(math.exp(v-top) for v in logits))
    return tuple(v-normalizer for v in logits)


def fit(votes, width, *, l2=.1, baseline=False):
    # Bounded inputs give a global smoothness bound of width+1+l2.
    theta = [0.] * (width+1)
    rate = 1 / ((0 if baseline else width) + 1 + l2)
    for step in range(10000):
        grad = [0.] * len(theta)
        for vote in votes:
            pa, pb, pt = map(math.exp, log_probs(theta, vote.dx))
            if not baseline:
                factor = .5 * (pa-pb-(vote.choice == 0)+(vote.choice == 1))
                for j, x in enumerate(vote.dx):
                    grad[j] += factor*x
            grad[-1] += pt-(vote.choice == 2)
        grad = [g/len(votes)+l2*w for g, w in zip(grad, theta)]
        if max(map(abs, grad)) < 1e-8:
            return theta
        theta = [w-rate*g for w, g in zip(theta, grad)]
    raise ValueError('fit did not converge')


def folds(votes, axis):
    for key in sorted({getattr(v, axis) for v in votes}):
        yield ([v for v in votes if getattr(v, axis) != key],
               [v for v in votes if getattr(v, axis) == key])


def evaluate(votes, width):
    if not votes:
        raise ValueError('no human labels; no scores emitted')
    axes = ('evaluator', 'family')
    for axis in axes:
        if len({getattr(v, axis) for v in votes}) < 2:
            raise ValueError(f'need at least two {axis} groups for holdout; no scores emitted')
    cv = {}
    for axis in axes:
        results = []
        for train, test in folds(votes, axis):
            model, base = fit(train, width), fit(train, width, baseline=True)
            n = len(test)
            results.append(dict(train_n=len(train), test_n=n,
                                log_loss=-sum(log_probs(model, v.dx)[v.choice] for v in test)/n,
                                baseline_log_loss=-sum(log_probs(base, v.dx)[v.choice] for v in test)/n))
        cv[axis] = dict(folds=results, **{f'macro_{k}': sum(r[k] for r in results)/len(results)
                                         for k in ('log_loss', 'baseline_log_loss')})
    theta = fit(votes, width)
    return dict(n=len(votes), counts={name: sum(v.choice == i for v in votes)
                                    for i, name in enumerate(OUTCOMES)}, cv=cv,
                final_fit=dict(weights=theta[:-1], log_tie=theta[-1], l2=.1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--layouts', type=Path, required=True)
    parser.add_argument('--labels', type=Path, required=True)
    args = parser.parse_args()
    try:
        names, votes = load(args.layouts, args.labels)
        report = evaluate(votes, len(names))
    except (OSError, ValueError, KeyError, TypeError, AttributeError, csv.Error) as exc:
        print(f'Refused: {exc}', file=sys.stderr)
        return 2
    print(json.dumps(dict(source='human (collector-attested)', features=names, **report), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
