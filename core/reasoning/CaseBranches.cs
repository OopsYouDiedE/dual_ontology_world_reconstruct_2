using System.Text.Json;

namespace DuelView.Core;

/// <summary>Checks declared counterfactual coverage and conditional reaction proofs.
/// A successful audit does not turn scenario assumptions into world facts.</summary>
public static class CaseBranches
{
    public sealed record Check(string Event, string Branch, string Kind, string Id, string Expected, string Actual)
    {
        public bool Passed => Expected == Actual;
    }

    public static IReadOnlyList<Check> Audit(CaseTheory theory, JsonElement declaration)
    {
        var checks = new List<Check>();
        var eventIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var ev in declaration.GetProperty("events").EnumerateArray())
        {
            var eventId = Text(ev, "id");
            if (!eventIds.Add(eventId)) throw new InvalidDataException("Duplicate branch event: " + eventId);
            var required = ev.GetProperty("decisions").EnumerateArray().Select(x => x.GetString()!).ToArray();
            if (required.Length == 0 || required.Any(string.IsNullOrWhiteSpace) || required.Distinct().Count() != required.Length)
                throw new InvalidDataException("Decision classes must be nonempty and unique.");
            var dimensions = ev.GetProperty("reaction_dimensions").EnumerateArray().Select(x => x.GetString()!).ToArray();
            if (dimensions.Length == 0 || dimensions.Any(string.IsNullOrWhiteSpace) || dimensions.Distinct().Count() != dimensions.Length)
                throw new InvalidDataException("Reaction dimensions must be nonempty and unique.");
            var covered = new HashSet<string>(StringComparer.Ordinal);
            var branchIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var branch in ev.GetProperty("branches").EnumerateArray())
            {
                var id = Text(branch, "id");
                if (!branchIds.Add(id)) throw new InvalidDataException("Duplicate branch: " + id);
                var decision = Text(branch, "decision");
                if (!required.Contains(decision)) throw new InvalidDataException("Undeclared decision: " + decision);
                covered.Add(decision);
                // An explicitly inapplicable class is recorded with its reason;
                // it is never silently dropped from the coverage denominator.
                if (branch.TryGetProperty("inapplicable", out var reason))
                {
                    checks.Add(new(eventId, id, "applicability", decision, "explained", string.IsNullOrWhiteSpace(reason.GetString()) ? "missing" : "explained"));
                    continue;
                }
                if (!branch.GetProperty("counterfactual").GetBoolean())
                    throw new InvalidDataException("Branch audit requires explicitly counterfactual premises.");
                var scopeId = Text(branch, "scope");
                var scope = theory.Scopes[scopeId];
                if (branch.GetProperty("expect").EnumerateObject().Count() == 0 ||
                    branch.GetProperty("reactions").GetArrayLength() == 0)
                    throw new InvalidDataException("Executable branch needs outcomes and reactions: " + id);
                var proof = theory.Infer(scopeId);
                var certificate = CaseProofChecker.Check(scope, proof);
                if (!certificate.Valid) throw new InvalidDataException("Invalid branch certificate: " + id);
                var facts = proof.Nodes.Select(n => n.Conclusion.Key).ToHashSet(StringComparer.Ordinal);
                foreach (var goal in branch.GetProperty("expect").EnumerateObject())
                {
                    var literal = scope.Theorems.Single(t => t.Id == goal.Name).Conclusion;
                    var positive = facts.Contains(literal.Key); var negative = facts.Contains(literal.Opposite.Key);
                    var actual = positive && negative ? "conflicted" : positive ? "proved" : negative ? "refuted" : "unknown";
                    checks.Add(new(eventId, id, "outcome", goal.Name, goal.Value.GetString()!, actual));
                }
                foreach (var reaction in branch.GetProperty("reactions").EnumerateArray())
                {
                    var actor = Text(reaction, "actor");
                    var rule = scope.Rules.Single(r => r.Id == Text(reaction, "rule"));
                    var expectedProof = Expectation(reaction, "expect_proof");
                    var expectedBasis = reaction.TryGetProperty("expect_basis", out var basisExpectations)
                        ? basisExpectations.EnumerateObject().ToDictionary(p => p.Name, p => ExpectedProofState(p.Value), StringComparer.Ordinal)
                        : new Dictionary<string, string>(StringComparer.Ordinal);
                    if (expectedBasis.Keys.Any(name => !dimensions.Contains(name)))
                        throw new InvalidDataException("Unknown reaction basis expectation dimension: " + id);
                    var bindings = reaction.TryGetProperty("substitution", out var substitution)
                        ? substitution.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString() ?? "", StringComparer.Ordinal)
                        : new Dictionary<string, string>(StringComparer.Ordinal);
                    var variables = rule.Premises.Append(rule.Conclusion).SelectMany(p => p.Args).Where(a => a.StartsWith('?')).ToHashSet(StringComparer.Ordinal);
                    if (!variables.SetEquals(bindings.Keys) || bindings.Values.Any(v => string.IsNullOrWhiteSpace(v) || v.StartsWith('?')))
                        throw new InvalidDataException("Reaction must supply exactly the rule's ground variable bindings: " + id);
                    var instantiated = rule.Premises.Select(p => p.Substitute(bindings)).ToArray();
                    var conclusion = rule.Conclusion.Substitute(bindings);
                    var premises = instantiated.Select(p => p.Key).ToHashSet(StringComparer.Ordinal);
                    var byLiteral = proof.Nodes.ToDictionary(n => n.Conclusion.Key, StringComparer.Ordinal);
                    // A rule declaration is not proof that its prerequisites hold. Construct
                    // its actual application even if search found the conclusion by another rule.
                    var parents = instantiated.Where(p => byLiteral.ContainsKey(p.Key)).Select(p => byLiteral[p.Key].Id).ToArray();
                    var applied = new CaseProofNode("reaction-check", "apply", conclusion, rule.Id, parents, bindings);
                    var reactionProof = proof with { Nodes = proof.Nodes.Append(applied).ToArray() };
                    var proved = parents.Length == instantiated.Length;
                    if (proved)
                    {
                        var checkedReaction = CaseProofChecker.CheckGoal(scope, reactionProof, conclusion);
                        if (!checkedReaction.Valid)
                            throw new InvalidDataException("Reaction certificate rejected; no unprovability conclusion is available: " + string.Join("; ", checkedReaction.Errors));
                    }
                    // A negative fixture must explicitly expect missing support. This checks
                    // applicability of this rule instance; branch outcomes separately check its
                    // conclusion across the complete theory. Unproved is not explicit negation.
                    checks.Add(new(eventId, id, "reaction-proof", actor + ":" + rule.Id, expectedProof, proved ? "proved" : "unproved"));
                    checks.Add(new(eventId, id, "reaction-actor", actor, "bound", conclusion.Args.Contains(actor) ? "bound" : "missing"));
                    foreach (var name in dimensions)
                    {
                        var specified = reaction.GetProperty("basis").TryGetProperty(name, out var literal);
                        var atom = specified ? literal.Deserialize<CaseLiteral>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) : null;
                        var declared = atom is not null && CaseProofChecker.ValidLiteral(atom, true) && premises.Contains(atom.Key);
                        checks.Add(new(eventId, id, "reaction-premise", actor + ":" + name, "declared", declared ? "declared" : "missing"));
                        var expectedEvidence = expectedBasis.TryGetValue(name, out var expectation) ? expectation : "proved";
                        checks.Add(new(eventId, id, "reaction-evidence", actor + ":" + name, expectedEvidence, declared && facts.Contains(atom!.Key) ? "proved" : "unproved"));
                    }
                }
            }
            foreach (var decision in required)
                checks.Add(new(eventId, "coverage", "decision", decision, "covered", covered.Contains(decision) ? "covered" : "missing"));
        }
        return checks.AsReadOnly();
    }

    private static string Text(JsonElement value, string key) =>
        value.GetProperty(key).GetString() is { Length: > 0 } text ? text : throw new InvalidDataException("Missing " + key);

    private static string Expectation(JsonElement value, string key) =>
        value.TryGetProperty(key, out var expected) ? ExpectedProofState(expected) : "proved";

    private static string ExpectedProofState(JsonElement value) => value.GetString() is "proved" or "unproved" ? value.GetString()!
        : throw new InvalidDataException("Reaction proof expectation must be proved or unproved.");
}
