using System.Text.Json;

namespace DuelView.Runtime;

/// <summary>Indexes authored goals by their fields. Scoring previews one owned action
/// law and visits only goals affected by its effects or explicit observation grants.</summary>
internal sealed class SingleStepPolicy
{
    private sealed record Goal(Condition? Proposition, Condition Available, FieldKey? Observe, double Weight);
    private readonly ActorClient actor;
    private readonly Dictionary<string, Rule> predictions = new(StringComparer.Ordinal);
    private readonly Dictionary<FieldKey, HashSet<Goal>> affected = [];

    internal SingleStepPolicy(ActorClient actor)
    {
        this.actor = actor;
        var declaration = actor.Declaration;
        foreach (var adoption in declaration.Get("mind").Get("adoptions").Fields())
            if (adoption.Value.Get("active").Flag(true) && adoption.Value.Get("mode").Text() == "predict")
                predictions.Add(adoption.Name, Rule.Compile(adoption.Name, adoption.Value, actor.Id));
        foreach (var item in declaration.Get("policy").Get("goals").Items())
        {
            var proposition = item.Get("proposition").ValueKind == JsonValueKind.Object ? Condition.Compile(item.Get("proposition"), actor.Id) : null;
            var available = item.Get("available_when").ValueKind == JsonValueKind.Object ? Condition.Compile(item.Get("available_when"), actor.Id) : new Condition.Constant(Truth.True);
            var observe = item.Get("ref").ValueKind == JsonValueKind.Object ? FieldKey.Read(item.Get("ref"), actor.Id) : (FieldKey?)null;
            var weight = item.Get("weight").Number(1);
            if (!double.IsFinite(weight) || weight < 0) throw new InvalidDataException("Invalid authored goal weight.");
            var goal = new Goal(proposition, available, observe, weight);
            foreach (var key in (proposition?.Inputs ?? []).Concat(available.Inputs).Concat(observe is { } target ? [target] : []).Distinct())
            {
                if (!affected.TryGetValue(key, out var set)) affected.Add(key, set = []);
                set.Add(goal);
            }
        }
    }

    internal double Score(ActionCandidate action, double contentTime)
    {
        var writes = new Dictionary<FieldKey, Fact>();
        var relevant = new HashSet<Goal>();
        var lawId = action.Declaration.Get("law").Text();
        if (predictions.TryGetValue(lawId, out var law) && law.Premise.Evaluate(actor.Recall) == Truth.True)
        {
            try { writes = law.Preview(actor.Recall, contentTime); }
            catch (InvalidOperationException) { return double.NegativeInfinity; }
            foreach (var key in writes.Keys) if (affected.TryGetValue(key, out var set)) relevant.UnionWith(set);
        }
        var observed = action.Declaration.Get("grants").Items().Select(x => FieldKey.Read(x, actor.Id)).ToHashSet();
        foreach (var key in observed) if (affected.TryGetValue(key, out var set)) relevant.UnionWith(set);
        Fact? After(FieldKey key) => writes.GetValueOrDefault(key) ?? actor.Recall(key);
        var score = 0.0;
        foreach (var goal in relevant)
        {
            if (goal.Proposition is { } proposition && proposition.Evaluate(actor.Recall) != Truth.True)
            {
                if (goal.Available.Evaluate(actor.Recall) == Truth.True && proposition.Evaluate(After) == Truth.True) score += goal.Weight;
                else if (goal.Available.Evaluate(actor.Recall) != Truth.True && goal.Available.Evaluate(After) == Truth.True) score += goal.Weight;
            }
            if (goal.Observe is { } key && observed.Contains(key) && actor.Recall(key) is not { Known: true, Conflicted: false } && goal.Available.Evaluate(actor.Recall) == Truth.True)
                score += goal.Weight;
        }
        return score;
    }
}
