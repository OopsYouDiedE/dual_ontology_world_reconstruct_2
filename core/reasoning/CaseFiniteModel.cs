using System.Text.Json;

namespace DuelView.Core;

public sealed record CaseFiniteModelAudit(string Id, string Scope, string Expected, string Actual,
    bool Passed, IReadOnlyList<string> Errors, string TheoryHash = "");

/// <summary>
/// Independently checks a supplied classical, finite, function-free interpretation.
/// This is an authoring witness checker, not model search and not actor inference.
/// Signed negatives mean Boolean complement here only. Unlisted positive atoms are false.
/// A valid witness proves satisfiability in its declared domain; a false assertion target
/// can witness non-entailment. It does not establish uniqueness or physical executability.
/// </summary>
public static class CaseFiniteModel
{
    private sealed class BudgetExceeded : Exception { }

    public static IReadOnlyList<CaseFiniteModelAudit> Audit(CaseTheory theory, JsonElement declaration,
        int maxEvaluations = 1000000)
    {
        if (maxEvaluations < 1) throw new ArgumentOutOfRangeException(nameof(maxEvaluations));
        var results = new List<CaseFiniteModelAudit>();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        try
        {
            Fields(declaration, "checks");
            var checks = RequiredArray(declaration, "checks");
            if (checks.GetArrayLength() == 0) throw new FormatException("At least one model check is required");
            if (checks.GetArrayLength() > 1000)
                return new[] { new CaseFiniteModelAudit("case-models", "", "valid", "incomplete", false,
                    new[] { "Model check count exceeds the audit budget" }) };
            foreach (var check in checks.EnumerateArray())
            {
                var id = "case-model-" + results.Count;
                var scopeId = "";
                var expected = "valid";
                var actual = "invalid";
                var hash = "";
                var errors = new List<string>();
                var expectationValid = false;
                try
                {
                    // Read the expectation before other validation so deliberately malformed
                    // model fixtures may assert rejection, but never assert budget exhaustion.
                    if (check.ValueKind == JsonValueKind.Object && check.TryGetProperty("expect", out var e))
                        expected = e.ValueKind == JsonValueKind.String ? e.GetString()! : "";
                    expectationValid = expected is "valid" or "invalid";
                    if (!expectationValid) throw new FormatException("expect must be valid or invalid");
                    Fields(check, "id", "scope", "domain", "true_atoms", "assertions", "expect");
                    id = Text(check.GetProperty("id"));
                    scopeId = Text(check.GetProperty("scope"));
                    if (!ids.Add(id)) throw new FormatException("Duplicate model check id: " + id);
                    if (theory is null || !theory.Scopes.TryGetValue(scopeId, out var scope))
                        throw new FormatException("Unknown model scope: " + scopeId);
                    var validation = CaseProofChecker.ValidateTheory(scope);
                    if (!validation.Valid) throw new FormatException(string.Join("; ", validation.Errors));
                    hash = CaseTheory.Fingerprint(scope);
                    Check(theory, scope, check, maxEvaluations);
                    actual = "valid";
                }
                catch (BudgetExceeded)
                {
                    actual = "incomplete";
                    errors.Add("Finite model evaluation budget exhausted; no validity or invalidity conclusion");
                }
                catch (Exception ex) when (ex is FormatException or InvalidOperationException or KeyNotFoundException or ArgumentException)
                { errors.Add(ex.Message); }
                results.Add(new(id, scopeId, expected, actual,
                    expectationValid && actual != "incomplete" && actual == expected, errors.AsReadOnly(), hash));
            }
        }
        catch (Exception ex) when (ex is FormatException or InvalidOperationException or KeyNotFoundException or ArgumentException)
        { results.Add(new("case-models", "", "valid", "invalid", false, new[] { ex.Message })); }
        return results.AsReadOnly();
    }

    private static void Check(CaseTheory theory, CaseScope scope, JsonElement check, int budget)
    {
        var remaining = budget;
        void Spend() { if (remaining-- <= 0) throw new BudgetExceeded(); }
        var domain = new List<string>();
        var constants = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in RequiredArray(check, "domain").EnumerateArray())
        {
            Spend();
            var name = Text(entry);
            if (name.StartsWith('?')) throw new FormatException("Domain members must be constants");
            if (!constants.Add(name)) throw new FormatException("Duplicate domain member: " + name);
            domain.Add(name);
        }
        if (domain.Count == 0) throw new FormatException("Finite domain must be nonempty");
        var arities = new Dictionary<string, int>(StringComparer.Ordinal);
        void Register(CaseLiteral literal)
        {
            Spend();
            if (arities.TryGetValue(literal.Predicate, out var arity) && arity != literal.Args.Count)
                throw new FormatException("Inconsistent predicate arity: " + literal.Predicate);
            arities[literal.Predicate] = literal.Args.Count;
            foreach (var term in literal.Args)
            {
                Spend();
                if (!term.StartsWith('?') && !constants.Contains(term))
                    throw new FormatException("Constant outside declared model domain: " + term);
            }
        }
        foreach (var axiom in scope.Axioms) Register(axiom.Literal);
        foreach (var rule in scope.Rules)
        {
            foreach (var premise in rule.Premises) Register(premise);
            Register(rule.Conclusion);
        }
        // A theorem without a checked proof is a goal, not an extra model axiom.
        // Still include the signature/constants of goals and declared candidates.
        foreach (var theorem in scope.Theorems) Register(theorem.Conclusion);
        foreach (var candidate in theory.Candidates.Where(c => c.Scope == scope.Id))
            foreach (var literal in candidate.Requires.Concat(candidate.Excludes)) Register(literal);

        var truths = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in RequiredArray(check, "true_atoms").EnumerateArray())
        {
            Spend();
            var literal = Literal(entry);
            Register(literal);
            if (literal.Negative) throw new FormatException("true_atoms must contain positive atoms only");
            if (!truths.Add(literal.Key)) throw new FormatException("Duplicate true atom: " + literal.Key);
        }
        var assertions = new List<(CaseLiteral Literal, bool Value)>();
        if (check.TryGetProperty("assertions", out _))
            foreach (var entry in RequiredArray(check, "assertions").EnumerateArray())
            {
                Spend();
                Fields(entry, "literal", "value");
                var literal = Literal(entry.GetProperty("literal"));
                Register(literal);
                var value = entry.GetProperty("value");
                if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                    throw new FormatException("Assertion value must be Boolean");
                assertions.Add((literal, value.GetBoolean()));
            }

        bool Holds(CaseLiteral literal, IReadOnlyDictionary<string, string>? bindings = null)
        {
            Spend();
            var grounded = bindings is null ? literal : literal.Substitute(bindings);
            var positive = grounded with { Negative = false };
            var present = truths.Contains(positive.Key);
            return literal.Negative ? !present : present;
        }
        foreach (var axiom in scope.Axioms)
            if (!Holds(axiom.Literal)) throw new FormatException("Model violates axiom: " + axiom.Id);
        foreach (var rule in scope.Rules)
        {
            var variables = rule.Premises.Append(rule.Conclusion).SelectMany(l => l.Args)
                .Where(a => a.StartsWith('?')).Distinct(StringComparer.Ordinal).ToArray();
            var digits = new int[variables.Length];
            var bindings = new Dictionary<string, string>(StringComparer.Ordinal);
            while (true)
            {
                Spend();
                for (var i = 0; i < variables.Length; i++)
                { Spend(); bindings[variables[i]] = domain[digits[i]]; }
                if (rule.Premises.All(p => Holds(p, bindings)) && !Holds(rule.Conclusion, bindings))
                    throw new FormatException("Model violates rule " + rule.Id + " at " + JsonSerializer.Serialize(bindings));
                var position = digits.Length - 1;
                while (position >= 0 && ++digits[position] == domain.Count)
                { digits[position] = 0; position--; }
                if (position < 0) break;
            }
        }
        foreach (var assertion in assertions)
            if (Holds(assertion.Literal) != assertion.Value)
                throw new FormatException("Model assertion does not match interpretation: " + assertion.Literal.Key);
    }

    private static CaseLiteral Literal(JsonElement value)
    {
        Fields(value, "predicate", "args", "negative");
        var predicate = Text(value.GetProperty("predicate"));
        var args = RequiredArray(value, "args").EnumerateArray().Select(Text).ToArray();
        var negative = false;
        if (value.TryGetProperty("negative", out var sign))
        {
            if (sign.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new FormatException("Literal negative must be Boolean");
            negative = sign.GetBoolean();
        }
        var literal = new CaseLiteral(predicate, Array.AsReadOnly(args), negative);
        if (!CaseProofChecker.ValidLiteral(literal, true)) throw new FormatException("Expected well-formed ground literal");
        return literal;
    }

    private static string Text(JsonElement value) => value.ValueKind == JsonValueKind.String &&
        !string.IsNullOrWhiteSpace(value.GetString()) ? value.GetString()! : throw new FormatException("Expected nonempty string");

    private static JsonElement RequiredArray(JsonElement value, string field)
    {
        var array = value.GetProperty(field);
        return array.ValueKind == JsonValueKind.Array ? array : throw new FormatException("Expected array: " + field);
    }

    private static void Fields(JsonElement value, params string[] allowed)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new FormatException("Expected object");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in value.EnumerateObject())
            if (!allowed.Contains(property.Name, StringComparer.Ordinal) || !seen.Add(property.Name))
                throw new FormatException("Unknown or duplicate model field: " + property.Name);
    }
}
