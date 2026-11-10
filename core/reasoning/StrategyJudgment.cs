using System.Text.Json;
namespace DuelView.Core;
public sealed record CaseStrategyChoice(string Action, bool Ready, double Utility,
    IReadOnlyList<string> Missing, IReadOnlyList<string> Blocked, IReadOnlyList<string> Basis,
    string TheoryHash, IReadOnlyList<string> EvidenceNodes);

public static class StrategyJudgment
{
    public static IReadOnlyList<CaseStrategyChoice> Evaluate(CaseTheory theory, string actor, JsonElement profile,
        string? action = null)
    {
        using var work = BeginEvaluation(theory, actor, profile, action);
        return work.RunToCompletion();
    }

    /// <summary>Creates computation only. A completed judgment neither completes an activity
    /// nor advances simulation time. Advance/AdvanceUntil are single-owner operations.</summary>
    public static CaseStrategyWork BeginEvaluation(CaseTheory theory, string actor, JsonElement profile,
        string? action = null, int maxNodes = 10000, int maxMatches = 1000000)
        => new(theory, actor, profile, action, maxNodes, maxMatches);

    public sealed class CaseStrategyWork : CaseWork<IReadOnlyList<CaseStrategyChoice>>
    {
        private readonly CaseInferenceWork inference;
        private readonly string actor;
        private readonly JsonElement profile;
        private readonly string? action;
        public long Matches => inference.Matches;
        public int NodeCount => inference.NodeCount;

        internal CaseStrategyWork(CaseTheory theory, string actor, JsonElement profile, string? action, int maxNodes, int maxMatches)
        {
            if (actor == "objective" || profile.GetProperty("actor").GetString() != actor)
                throw new InvalidDataException("Strategy must use its own actor scope.");
            this.actor = actor;
            this.profile = profile.Clone();
            this.action = action;
            inference = new CaseInferenceWork(theory.Scopes[actor], maxNodes, maxMatches);
        }

        protected override IEnumerable<int> Execute()
        {
            using (inference)
            {
                while (inference.Status == CaseWorkStatus.Running)
                {
                    inference.AdvanceUntil(1, long.MaxValue);
                    Phase = inference.Phase;
                    yield return 0;
                }
                // This only retrieves a terminal result or rethrows its original failure.
                var proof = inference.RunToCompletion();
                Phase = "index-judgment";
                var facts = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var node in proof.Nodes)
                {
                    facts.Add(node.Conclusion.Key, node.Id);
                    yield return 0;
                }
                Phase = "score-choices";
                IReadOnlyList<CaseStrategyChoice>? result = null;
                foreach (var step in JudgmentSteps(actor, profile, facts, proof.TheoryHash, action, value => result = value)) yield return step;
                Finish(result!);
            }
        }
    }

    /// <summary>Conservative ordinary judgment before any relevant observation requests proof work.</summary>
    public static IReadOnlyList<CaseStrategyChoice> AwaitingEvidence(string actor, JsonElement profile, string version)
        => FromJudgment(actor, profile, new Dictionary<string, string>(StringComparer.Ordinal), version);

    private static IReadOnlyList<CaseStrategyChoice> FromJudgment(string actor, JsonElement profile,
        IReadOnlyDictionary<string, string> facts, string theoryHash, string? action = null)
    {
        IReadOnlyList<CaseStrategyChoice>? result = null;
        foreach (var _ in JudgmentSteps(actor, profile, facts, theoryHash, action, value => result = value)) { }
        return result!;
    }

    private static IEnumerable<int> JudgmentSteps(string actor, JsonElement profile,
        IReadOnlyDictionary<string, string> facts, string theoryHash, string? action,
        Action<IReadOnlyList<CaseStrategyChoice>> complete)
    {
        if (actor == "objective" || profile.GetProperty("actor").GetString() != actor)
            throw new InvalidDataException("Strategy must use its own actor scope.");
        var basis = Strings(profile, "basis");
        if (basis.Length == 0) throw new InvalidDataException("Strategy requires declared provenance.");
        var drives = profile.GetProperty("drives").EnumerateObject().ToDictionary(x => x.Name, x => Finite(x.Value), StringComparer.Ordinal);
        var choices = profile.GetProperty("choices").EnumerateArray().ToArray();
        if (choices.Select(x => x.GetProperty("action").GetString()).Distinct(StringComparer.Ordinal).Count() != choices.Length)
            throw new InvalidDataException("Duplicate strategy action.");
        var selected = choices.Where(x => action is null || x.GetProperty("action").GetString() == action).ToArray();
        yield return 0;
        var results = new List<CaseStrategyChoice>();
        foreach (var choice in selected)
        {
            var declaration = Strings(choice, "basis");
            if (declaration.Length == 0) throw new InvalidDataException("Strategy choice requires declared provenance.");
            var requires = Literals(choice, "requires");
            var prohibits = Literals(choice, "prohibits");
            var missing = requires.Where(x => !facts.ContainsKey(x.Key)).Select(x => x.Key).ToArray();
            var blocked = requires.Where(x => facts.ContainsKey(x.Opposite.Key)).Select(x => x.Opposite.Key)
                .Concat(prohibits.Where(x => facts.ContainsKey(x.Key)).Select(x => x.Key)).Distinct().ToArray();
            double utility = 0;
            foreach (var promotion in choice.GetProperty("promotes").EnumerateObject())
            {
                if (!drives.TryGetValue(promotion.Name, out var weight)) throw new InvalidDataException("Undeclared strategy drive: " + promotion.Name);
                utility += weight * Finite(promotion.Value);
                if (!double.IsFinite(utility)) throw new InvalidDataException("Strategy utility exceeds finite range.");
                yield return 0;
            }
            var evidence = requires.Concat(prohibits).SelectMany(x => new[] { x.Key, x.Opposite.Key })
                .Where(facts.ContainsKey).Select(x => facts[x]).Distinct().ToArray();
            results.Add(new(choice.GetProperty("action").GetString() ?? throw new InvalidDataException("Missing strategy action."),
                missing.Length == 0 && blocked.Length == 0, utility, missing, blocked,
                basis.Concat(declaration).ToArray(), theoryHash, evidence));
            yield return 0;
        }
        complete(results.AsReadOnly());
    }
    private static double Finite(JsonElement value)
    {
        var number = value.GetDouble();
        return double.IsFinite(number) ? number : throw new InvalidDataException("Strategy weights must be finite.");
    }
    private static string[] Strings(JsonElement value, string field) => value.GetProperty(field).EnumerateArray()
        .Select(x => !string.IsNullOrWhiteSpace(x.GetString()) ? x.GetString()! : throw new InvalidDataException("Empty strategy provenance.")).ToArray();
    private static CaseLiteral[] Literals(JsonElement value, string field) => value.GetProperty(field).EnumerateArray().Select(x =>
    {
        var literal = x.Deserialize<CaseLiteral>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException("Invalid strategy literal.");
        if (string.IsNullOrWhiteSpace(literal.Predicate) || literal.Predicate.StartsWith('?') || literal.Args is null ||
            literal.Args.Any(a => string.IsNullOrWhiteSpace(a)) || !literal.Ground)
            throw new InvalidDataException("Strategy conditions must be ground literals.");
        return literal;
    }).ToArray();
}
