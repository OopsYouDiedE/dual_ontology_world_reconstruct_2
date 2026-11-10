using System.Text;
using System.Text.Json;

namespace DuelView.Runtime;

internal sealed record GoalPlanningGoal(string Id, Condition Target, double Weight);
internal sealed record GoalPlanningAction(string Id, Condition Precondition, IReadOnlyList<Effect> Effects,
    double Cost, double UncertaintyCost = 0, double FailurePenalty = 0);
internal sealed record GoalPlanningRequest(IReadOnlyDictionary<FieldKey, Fact> KnownFacts,
    IReadOnlyList<GoalPlanningGoal> Goals, IReadOnlyList<GoalPlanningAction> Actions,
    IReadOnlySet<string> FirstStepAllowed, int MaxDepth = 6, int MaxExpanded = 512, int BeamWidth = 20);
internal sealed record GoalPlanningResult(string? FirstAction, IReadOnlyList<string> ActionSequence,
    IReadOnlyList<string> ReachedGoals, double Utility, double Cost, int Expanded, string Status, string Algorithm);

/// <summary>
/// Bounded planning over the actor's explicit action models and own knowledge.
/// A prediction never writes into a live world or an actor's memory. Uncertain
/// outcomes, including another person's agreement, remain predictions to test.
/// </summary>
internal static class GoalPlanning
{
    private sealed record Node(Dictionary<FieldKey, Fact> State, string[] Path,
        double Cost, double Gain, string[] Reached, string Signature)
    {
        internal double Utility => Gain - Cost;
    }

    internal static GoalPlanningResult Solve(GoalPlanningRequest request, string algorithm)
    {
        if (algorithm is not ("best_first" or "beam"))
            throw new ArgumentException("Unknown goal planning algorithm: " + algorithm);
        if (request.MaxDepth is < 1 or > 12 || request.MaxExpanded is < 1 or > 8192 || request.BeamWidth is < 1 or > 128)
            throw new ArgumentException("Goal planning budgets are outside the supported bounds.");
        if (request.Actions.Count > 256 || request.Goals.Count > 32 ||
            request.Actions.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != request.Actions.Count ||
            request.Goals.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != request.Goals.Count)
            throw new ArgumentException("Invalid or excessive goal planning declarations.");
        foreach (var goal in request.Goals)
            if (string.IsNullOrWhiteSpace(goal.Id) || !double.IsFinite(goal.Weight) || goal.Weight <= 0)
                throw new ArgumentException("A planning goal requires a positive finite weight.");
        foreach (var action in request.Actions)
            if (string.IsNullOrWhiteSpace(action.Id) || !FiniteCost(action.Cost) ||
                !FiniteCost(action.UncertaintyCost) || !FiniteCost(action.FailurePenalty))
                throw new ArgumentException("A planning action has an invalid cost.");

        var keys = request.Goals.SelectMany(g => g.Target.Inputs)
            .Concat(request.Actions.SelectMany(a => a.Precondition.Inputs))
            .Concat(request.Actions.SelectMany(a => a.Effects.Select(e => e.Key)))
            .Distinct().OrderBy(k => k.Object, StringComparer.Ordinal)
            .ThenBy(k => k.Facet, StringComparer.Ordinal).ThenBy(k => k.Field, StringComparer.Ordinal).ToArray();
        var initial = new Dictionary<FieldKey, Fact>();
        foreach (var key in keys)
            if (request.KnownFacts.TryGetValue(key, out var fact)) initial[key] = fact;
        Fact? InitialRead(FieldKey key) => initial.GetValueOrDefault(key);
        var initiallyReached = request.Goals.Where(g => g.Target.Evaluate(InitialRead) == Truth.True)
            .Select(g => g.Id).ToHashSet(StringComparer.Ordinal);
        var initialWeight = request.Goals.Where(g => initiallyReached.Contains(g.Id)).Sum(g => g.Weight);
        if (request.Goals.Count == 0 || initiallyReached.Count == request.Goals.Count)
            return new(null, [], initiallyReached.Order(StringComparer.Ordinal).ToArray(), 0, 0, 0, "already_satisfied", algorithm);

        // Regression only removes operators with no possible relevance to these
        // goals; it does not invent facts or an undiscovered operator.
        var relevant = request.Goals.SelectMany(g => g.Target.Inputs).ToHashSet();
        for (var level = 0; level < request.MaxDepth; ++level)
        {
            var before = relevant.Count;
            foreach (var action in request.Actions)
                if (action.Effects.Any(e => relevant.Contains(e.Key)))
                    relevant.UnionWith(action.Precondition.Inputs);
            if (relevant.Count == before) break;
        }
        var operators = request.Actions.Where(a => a.Effects.Any(e => relevant.Contains(e.Key)))
            .OrderBy(a => a.Id, StringComparer.Ordinal).ToArray();
        var start = new Node(initial, [], 0, 0, initiallyReached.Order(StringComparer.Ordinal).ToArray(), Signature(initial, keys));
        Node? best = null;
        var expanded = 0;
        var limited = false;
        var bestCosts = new Dictionary<(string Signature, int Depth), double> { [(start.Signature, 0)] = 0 };

        IEnumerable<Node> Successors(Node node)
        {
            if (node.Path.Length >= request.MaxDepth) yield break;
            Fact? Read(FieldKey key) => node.State.GetValueOrDefault(key);
            foreach (var action in operators)
            {
                if (node.Path.Length == 0 && !request.FirstStepAllowed.Contains(action.Id)) continue;
                if (action.Precondition.Evaluate(Read) != Truth.True) continue;
                var state = new Dictionary<FieldKey, Fact>(node.State);
                var valid = true;
                foreach (var effect in action.Effects)
                {
                    try
                    {
                        state[effect.Key] = effect.Resolve(k => state.GetValueOrDefault(k), 0, 1);
                    }
                    catch (InvalidOperationException)
                    {
                        // An increment without a known uncontested quantity is
                        // not a permitted mental shortcut to an invented stock.
                        valid = false;
                        break;
                    }
                }
                if (!valid) continue;
                var signature = Signature(state, keys);
                if (signature == node.Signature) continue;
                var cost = node.Cost + Math.Max(0.001, action.Cost) + action.UncertaintyCost + action.FailurePenalty;
                var stateKey = (signature, node.Path.Length + 1);
                if (bestCosts.TryGetValue(stateKey, out var prior) && prior <= cost + 1e-9) continue;
                bestCosts[stateKey] = cost;
                Fact? NextRead(FieldKey key) => state.GetValueOrDefault(key);
                var reached = request.Goals.Where(g => g.Target.Evaluate(NextRead) == Truth.True).ToArray();
                var next = new Node(state, [.. node.Path, action.Id], cost,
                    reached.Sum(g => g.Weight) - initialWeight,
                    reached.Select(g => g.Id).ToArray(), signature);
                if (next.Utility > 0 && Better(next, best)) best = next;
                yield return next;
            }
        }

        if (algorithm == "best_first")
        {
            // Uniform cost expansion is a useful independent comparison to the
            // depth-limited beam; bounded execution makes no optimality claim.
            var queue = new PriorityQueue<Node, (double Cost, int Length, long Order)>();
            long order = 0;
            queue.Enqueue(start, (0, 0, order++));
            while (queue.TryDequeue(out var node, out _))
            {
                if (bestCosts.GetValueOrDefault((node.Signature, node.Path.Length), double.PositiveInfinity) < node.Cost - 1e-9) continue;
                if (expanded >= request.MaxExpanded) { limited = true; break; }
                ++expanded;
                foreach (var child in Successors(node))
                    if (child.Path.Length < request.MaxDepth)
                        queue.Enqueue(child, (child.Cost, child.Path.Length, order++));
            }
        }
        else
        {
            var frontier = new List<Node> { start };
            for (var depth = 0; depth < request.MaxDepth && frontier.Count > 0; ++depth)
            {
                var next = new List<Node>();
                foreach (var node in frontier)
                {
                    if (expanded >= request.MaxExpanded) { limited = true; break; }
                    ++expanded;
                    next.AddRange(Successors(node));
                }
                if (limited) break;
                // Reached utility is the principal beam signal. Stable ordering
                // makes a comparison reproducible for the same known inputs.
                frontier = next.OrderByDescending(n => n.Utility).ThenBy(n => n.Cost)
                    .ThenBy(n => string.Join('\u001f', n.Path), StringComparer.Ordinal)
                    .Take(request.BeamWidth).ToList();
            }
        }

        if (best is null)
            return new(null, [], [], 0, 0, expanded, limited ? "budget_exhausted" : "no_plan", algorithm);
        var status = best.Reached.Length == request.Goals.Count ? "predicted_goals" : "partial_plan";
        if (limited) status = "budget_limited_" + status;
        return new(best.Path[0], best.Path, best.Reached, best.Utility, best.Cost, expanded, status, algorithm);
    }

    private static bool FiniteCost(double value) => double.IsFinite(value) && value >= 0;
    private static bool Better(Node candidate, Node? current) => current is null ||
        candidate.Utility > current.Utility + 1e-9 ||
        Math.Abs(candidate.Utility - current.Utility) < 1e-9 && candidate.Cost < current.Cost - 1e-9;

    private static string Signature(IReadOnlyDictionary<FieldKey, Fact> state, IReadOnlyList<FieldKey> keys)
    {
        var text = new StringBuilder(keys.Count * 16);
        foreach (var key in keys)
        {
            if (!state.TryGetValue(key, out var fact)) { text.Append("?;"); continue; }
            text.Append(fact.Known ? 'K' : 'U').Append(fact.Conflicted ? 'C' : 'S').Append(':');
            if (fact.Value.ValueKind != JsonValueKind.Undefined)
            {
                var raw = fact.Value.GetRawText();
                text.Append(raw.Length).Append(':').Append(raw);
            }
            text.Append(';');
        }
        return text.ToString();
    }
}
