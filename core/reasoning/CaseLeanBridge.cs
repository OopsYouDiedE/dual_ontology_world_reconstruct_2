using System.Text;
using System.Text.Json;

namespace DuelView.Core;

/// <summary>
/// Translates a checked signed-Horn goal certificate into the independent natural
/// deduction language consumed by the Lean exporter. Explicit negative evidence
/// gets a separate predicate, never logical negation or False. This preserves
/// non-explosive actor theories even when both signs have proofs.
/// </summary>
public static class CaseLeanBridge
{
    private static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);
    private static string Name(string category, string value) =>
        category + "_" + Convert.ToHexString(StrictUtf8.GetBytes(value)).ToLowerInvariant();

    private static string Atom(CaseLiteral literal) =>
        "(at " + Name(literal.Negative ? "negative" : "positive", literal.Predicate) +
        string.Concat(literal.Args.Select(term => " " + (term.StartsWith('?')
            ? "?" + Name("v", term) : Name("c", term)))) + ")";

    private static string[] Variables(CaseRule rule) => rule.Premises.Append(rule.Conclusion)
        .SelectMany(literal => literal.Args).Where(term => term.StartsWith('?'))
        .Distinct(StringComparer.Ordinal).OrderBy(term => term, StringComparer.Ordinal).ToArray();

    private static string RuleFormula(CaseRule rule)
    {
        var formula = Atom(rule.Conclusion);
        for (var i = rule.Premises.Count - 1; i >= 0; i--)
            formula = "(imp " + Atom(rule.Premises[i]) + " " + formula + ")";
        var variables = Variables(rule);
        for (var i = variables.Length - 1; i >= 0; i--)
            formula = "(all " + Name("v", variables[i]) + " " + formula + ")";
        if (formula.Length > 100000)
            throw new InvalidOperationException("Horn-to-ND rule exceeds the natural deduction source budget");
        return formula;
    }

    /// <summary>
    /// Returns an ND request only after both the Horn goal checker and independent
    /// ND checker accept it. No support, malformed input or budget exhaustion throws.
    /// For a refutation export the opposite signed goal explicitly. Calling this
    /// method does not run Lean; the authoring host must export and compile the result.
    /// </summary>
    public static JsonElement BuildRequest(CaseTheory theory, string scope, CaseLiteral goal)
    {
        ArgumentNullException.ThrowIfNull(theory);
        if (scope is null || !theory.Scopes.TryGetValue(scope, out var source))
            throw new ArgumentException("Unknown Horn scope", nameof(scope));
        var support = theory.Prove(scope, goal).Support
            ?? throw new InvalidOperationException("Requested signed goal has no supporting Horn certificate");
        var certificate = support.Certificate;
        var checkedHorn = theory.CheckGoal(scope, certificate, goal);
        if (!checkedHorn.Valid)
            throw new InvalidOperationException("Horn certificate rejected: " + string.Join("; ", checkedHorn.Errors));

        var facts = source.Axioms.ToDictionary(a => a.Id, StringComparer.Ordinal);
        var rules = source.Rules.ToDictionary(r => r.Id, StringComparer.Ordinal);
        var usedFacts = certificate.Nodes.Where(n => n.Kind == "axiom").Select(n => n.Reference).ToHashSet(StringComparer.Ordinal);
        var usedRules = certificate.Nodes.Where(n => n.Kind == "apply").Select(n => n.Reference).ToHashSet(StringComparer.Ordinal);
        var axioms = new List<object>();
        foreach (var id in usedFacts.OrderBy(x => x, StringComparer.Ordinal))
            axioms.Add(new { id = Name("fact", id), formula = Atom(facts[id].Literal) });
        foreach (var id in usedRules.OrderBy(x => x, StringComparer.Ordinal))
            axioms.Add(new { id = Name("rule", id), formula = RuleFormula(rules[id]) });

        // Local checked lemmas preserve sharing in the Horn DAG. Inlining the
        // parents recursively would make a small shared certificate exponential.
        var theorems = new List<object>();
        var references = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var node in certificate.Nodes)
        {
            if (node.Kind == "axiom")
            {
                references.Add(node.Id, Name("fact", node.Reference));
                continue;
            }
            if (node.Kind == "exact")
            {
                references.Add(node.Id, references[node.Parents[0]]);
                continue;
            }
            if (node.Kind != "apply")
                throw new InvalidOperationException("Unsupported checked Horn certificate node: " + node.Kind);
            var proof = "(use " + Name("rule", node.Reference) + ")";
            foreach (var variable in Variables(rules[node.Reference]))
                proof = "(all_elim " + proof + " " + Name("c", node.Substitution[variable]) + ")";
            foreach (var parent in node.Parents)
                proof = "(apply " + proof + " (use " + references[parent] + "))";
            if (proof.Length > 100000 || axioms.Count + theorems.Count >= 1024)
                throw new InvalidOperationException("Horn-to-ND certificate exceeds the natural deduction budget");
            var lemma = Name("node", node.Id);
            theorems.Add(new { id = lemma, formula = Atom(node.Conclusion), proof });
            references.Add(node.Id, lemma);
        }
        var request = JsonSerializer.SerializeToElement(new
        {
            scope,
            theory_hash = certificate.TheoryHash,
            semantics = "signed_predicates_are_independent",
            axioms,
            theorems,
            goal = Atom(goal),
            proof = "(use " + references[certificate.Nodes[^1].Id] + ")"
        });
        var checkedNd = NaturalDeduction.Check(request);
        if (!checkedNd.Valid)
            throw new InvalidOperationException("Horn-to-ND translation rejected: " + string.Join("; ", checkedNd.Errors));
        var expectedDependencies = usedFacts.Select(id => Name("fact", id))
            .Concat(usedRules.Select(id => Name("rule", id))).ToHashSet(StringComparer.Ordinal);
        if (!expectedDependencies.SetEquals(checkedNd.AxiomsUsed))
            throw new InvalidOperationException("Horn-to-ND translation changed the certificate's axiom dependencies");
        return request;
    }
}
