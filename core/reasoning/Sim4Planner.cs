using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DuelView.Core;

/// <summary>Bounded need-based interaction queue search over an actor's declared predictions.
/// This mechanism neither reads nor commits an objective world.</summary>
public static class Sim4Planner
{
    public sealed record Candidate(string Id, double Seconds, IReadOnlyDictionary<string, double> Effects,
        IReadOnlyList<string> Requires, IReadOnlyList<string> Prohibits,
        IReadOnlyList<string> Adds, IReadOnlyList<string> Removes, bool InitiallyAvailable = true);
    public sealed record Input(string Actor, string Version,
        IReadOnlyDictionary<string, double> Needs, IReadOnlyDictionary<string, double> Weights,
        IReadOnlyDictionary<string, double> DecayPerSecond, double TimeCost,
        IReadOnlyList<string> Knowledge, IReadOnlyList<Candidate> Candidates);
    public sealed record Settings(int Depth = 3, int BeamWidth = 32, int ExpansionBudget = 4096);
    public sealed record Step(string Action, double Seconds, double Utility,
        IReadOnlyDictionary<string, double> PredictedNeeds, bool RequiresReevaluation);
    public sealed record Plan(string Actor, string Version, string InputHash, Settings Settings,
        IReadOnlyList<Step> Queue, double Utility, int Expansions, int ReachedDepth,
        bool BudgetReached, bool BeamPruned, IReadOnlyDictionary<string, double> FirstActionScores);
    public sealed record Verification(bool Valid, IReadOnlyList<string> Errors);
    public sealed record AuditItem(string Id, string Expected, string Actual, bool Passed);

    public static IEnumerable<AuditItem> Audit(JsonElement corpus)
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        foreach (var check in corpus.GetProperty("checks").EnumerateArray())
        {
            var id = check.GetProperty("id").GetString()!;
            var input = check.GetProperty("input").Deserialize<Input>(options) ?? throw new FormatException("Missing planner input");
            var settings = check.GetProperty("settings").Deserialize<Settings>(options) ?? new();
            var plan = Build(input, settings);
            var expected = check.GetProperty("expect_queue").EnumerateArray().Select(x => x.GetString()!).ToArray();
            var actual = plan.Queue.Select(x => x.Action).ToArray();
            yield return new(id + ":queue", string.Join(",", expected), string.Join(",", actual), expected.SequenceEqual(actual));
            var verification = Verify(input, plan);
            yield return new(id + ":certificate", "valid", verification.Valid ? "valid" : string.Join(",", verification.Errors), verification.Valid);
            var forged = plan with { Utility = plan.Utility + 1 };
            var rejected = !Verify(input, forged).Valid;
            yield return new(id + ":forged-total", "rejected", rejected ? "rejected" : "accepted", rejected);
        }
    }
    private sealed record Branch(Dictionary<string, double> Needs, HashSet<string> Known,
        HashSet<string> Used, List<Step> Steps, double Utility);

    public static Plan Build(Input input, Settings? settings = null)
    {
        settings ??= new(); Validate(input, settings);
        var candidates = input.Candidates.OrderBy(x => x.Id, StringComparer.Ordinal).ToArray();
        var initial = new Branch(Copy(input.Needs), input.Knowledge.ToHashSet(StringComparer.Ordinal), new(StringComparer.Ordinal), [], 0);
        var frontier = new List<Branch> { initial }; var terminals = new List<Branch>();
        var expansions = 0; var reached = 0; var budgetReached = false; var pruned = false;
        var firstScores = new Dictionary<string, double>(StringComparer.Ordinal);
        for (var depth = 0; depth < settings.Depth; depth++)
        {
            var next = new List<Branch>();
            foreach (var branch in frontier)
            {
                var expanded = false;
                foreach (var candidate in candidates)
                {
                    if (branch.Used.Contains(candidate.Id) || depth == 0 && !candidate.InitiallyAvailable || !Available(branch.Known, candidate)) continue;
                    if (expansions >= settings.ExpansionBudget) { budgetReached = true; break; }
                    expansions++; expanded = true;
                    var child = Advance(input, branch, candidate);
                    next.Add(child); reached = Math.Max(reached, child.Steps.Count);
                }
                if (!expanded && branch.Steps.Count > 0) terminals.Add(branch);
            }
            if (next.Count == 0) break;
            // Stopping a queue is always permitted; planning farther ahead must not
            // force a harmful final interaction solely to fill the requested horizon.
            terminals.AddRange(next);
            pruned |= next.Count > settings.BeamWidth;
            frontier = next.OrderByDescending(x => x.Utility).ThenBy(x => PathKey(x.Steps), StringComparer.Ordinal).Take(settings.BeamWidth).ToList();
            if (depth == settings.Depth - 1 || budgetReached) { terminals.AddRange(frontier); break; }
        }
        foreach (var terminal in terminals)
        {
            var first = terminal.Steps[0].Action;
            if (!firstScores.TryGetValue(first, out var prior) || terminal.Utility > prior) firstScores[first] = terminal.Utility;
        }
        var best = terminals.Append(initial).OrderByDescending(x => x.Utility).ThenBy(x => x.Steps.Count)
            .ThenBy(x => PathKey(x.Steps), StringComparer.Ordinal).First();
        var result = new Plan(input.Actor, input.Version, Fingerprint(input), settings, best.Steps.ToArray(), best.Utility,
            expansions, reached, budgetReached, pruned, firstScores);
        var verified = Verify(input, result);
        if (!verified.Valid) throw new InvalidOperationException("Planner produced an invalid queue: " + string.Join("; ", verified.Errors));
        return result;
    }

    /// <summary>Checks the returned path independently of the search frontier and stored scores.
    /// It proves admissibility and arithmetic in the declared model, not global optimality.</summary>
    public static Verification Verify(Input input, Plan plan)
    {
        Validate(input, plan.Settings);
        var errors = new List<string>();
        if (plan.Actor != input.Actor || plan.Version != input.Version || plan.InputHash != Fingerprint(input)) errors.Add("stale-input");
        if (plan.Queue.Count > plan.Settings.Depth) errors.Add("depth");
        var candidates = input.Candidates.ToDictionary(x => x.Id, StringComparer.Ordinal);
        var needs = Copy(input.Needs); var known = input.Knowledge.ToHashSet(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal); double total = 0;
        for (var index = 0; index < plan.Queue.Count; index++)
        {
            var step = plan.Queue[index];
            if (!candidates.TryGetValue(step.Action, out var action)) { errors.Add("unknown-action:" + step.Action); continue; }
            if (!seen.Add(action.Id)) errors.Add("loop:" + action.Id);
            if (index == 0 && !action.InitiallyAvailable || action.Requires.Any(x => !known.Contains(x)) || action.Prohibits.Any(known.Contains)) errors.Add("condition:" + action.Id);
            double utility = -action.Seconds * input.TimeCost;
            foreach (var key in needs.Keys.ToArray())
            {
                var before = needs[key];
                var decayed = Math.Clamp(before - input.DecayPerSecond.GetValueOrDefault(key) * action.Seconds, 0, 100);
                var after = Math.Clamp(decayed + action.Effects.GetValueOrDefault(key), 0, 100);
                utility += input.Weights[key] * ((after - after * after / 200) - (before - before * before / 200));
                needs[key] = after;
            }
            if (!Close(utility, step.Utility) || !Close(action.Seconds, step.Seconds)) errors.Add("score:" + action.Id);
            if (step.PredictedNeeds.Count != needs.Count || needs.Any(x => !step.PredictedNeeds.TryGetValue(x.Key, out var value) || !Close(x.Value, value))) errors.Add("needs:" + action.Id);
            if (step.RequiresReevaluation != (index > 0)) errors.Add("reevaluation:" + action.Id);
            known.ExceptWith(action.Removes); known.UnionWith(action.Adds); total += utility;
        }
        if (!Close(total, plan.Utility)) errors.Add("total");
        return new(errors.Count == 0, errors);
    }

    private static Branch Advance(Input input, Branch branch, Candidate action)
    {
        var needs = Copy(branch.Needs); var delta = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var key in needs.Keys.ToArray())
        {
            var after = Math.Clamp(Math.Clamp(needs[key] - input.DecayPerSecond.GetValueOrDefault(key) * action.Seconds, 0, 100) + action.Effects.GetValueOrDefault(key), 0, 100);
            delta[key] = after - needs[key]; needs[key] = after;
        }
        var score = AutonomyDriveSolver.Score(branch.Needs, input.Weights, delta, action.Seconds, input.TimeCost);
        var known = new HashSet<string>(branch.Known, StringComparer.Ordinal); known.ExceptWith(action.Removes); known.UnionWith(action.Adds);
        var used = new HashSet<string>(branch.Used, StringComparer.Ordinal) { action.Id };
        var steps = new List<Step>(branch.Steps) { new(action.Id, action.Seconds, score, needs, branch.Steps.Count > 0) };
        return new(needs, known, used, steps, branch.Utility + score);
    }
    private static bool Available(HashSet<string> known, Candidate action) => action.Requires.All(known.Contains) && !action.Prohibits.Any(known.Contains);
    private static Dictionary<string, double> Copy(IReadOnlyDictionary<string, double> values) => values.ToDictionary(x => x.Key, x => x.Value, StringComparer.Ordinal);
    private static bool Close(double a, double b) => double.IsFinite(a) && double.IsFinite(b) && Math.Abs(a - b) <= 1e-8 * Math.Max(1, Math.Max(Math.Abs(a), Math.Abs(b)));
    private static string PathKey(IEnumerable<Step> steps) => string.Join("\0", steps.Select(x => x.Action));
    public static string Fingerprint(Input input)
    {
        object Numbers(IReadOnlyDictionary<string, double> values) => values.OrderBy(x => x.Key, StringComparer.Ordinal).ToArray();
        var canonical = new { input.Actor, input.Version, needs = Numbers(input.Needs), weights = Numbers(input.Weights), decay = Numbers(input.DecayPerSecond), input.TimeCost,
            knowledge = input.Knowledge.Order(StringComparer.Ordinal).ToArray(), candidates = input.Candidates.OrderBy(x => x.Id, StringComparer.Ordinal).Select(x => new
            { x.Id, x.Seconds, effects = Numbers(x.Effects), requires = x.Requires.Order(StringComparer.Ordinal).ToArray(), prohibits = x.Prohibits.Order(StringComparer.Ordinal).ToArray(),
                adds = x.Adds.Order(StringComparer.Ordinal).ToArray(), removes = x.Removes.Order(StringComparer.Ordinal).ToArray(), x.InitiallyAvailable }).ToArray() };
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(canonical))));
    }
    private static void Validate(Input input, Settings settings)
    {
        if (settings.Depth is < 2 or > 8 || settings.BeamWidth is < 1 or > 128 || settings.ExpansionBudget is < 1 or > 100000) throw new ArgumentOutOfRangeException(nameof(settings));
        if (input.Candidates.Count > 1024 || input.Candidates.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != input.Candidates.Count) throw new ArgumentException("Candidate identities/budget");
        if (!double.IsFinite(input.TimeCost) || input.TimeCost < 0) throw new ArgumentException("Time cost");
        foreach (var (key, value) in input.Needs)
            if (!double.IsFinite(value) || value < 0 || value > 100 || !input.Weights.TryGetValue(key, out var weight) || !double.IsFinite(weight) || weight < 0) throw new ArgumentException("Need profile: " + key);
        foreach (var (key, value) in input.DecayPerSecond)
            if (!input.Needs.ContainsKey(key) || !double.IsFinite(value) || value < 0) throw new ArgumentException("Need decay: " + key);
        foreach (var action in input.Candidates)
        {
            if (string.IsNullOrWhiteSpace(action.Id) || !double.IsFinite(action.Seconds) || action.Seconds <= 0) throw new ArgumentException("Action identity/duration");
            foreach (var (key, value) in action.Effects)
                if (!input.Needs.ContainsKey(key) || !double.IsFinite(value)) throw new ArgumentException("Prediction refers to invalid need: " + key);
            if (action.Adds.Intersect(action.Removes, StringComparer.Ordinal).Any()) throw new ArgumentException("Conflicting predicted propositions");
        }
    }
}
