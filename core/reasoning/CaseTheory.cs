using DuelView.Dv;
using System.Collections.ObjectModel;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DuelView.Core;

/// <summary>A signed atom. Negation is explicit evidence, never failure to prove.</summary>
public sealed record CaseLiteral(string Predicate, IReadOnlyList<string> Args, bool Negative = false)
{
    [JsonIgnore] public string Key => JsonSerializer.Serialize(new { Predicate, Args, Negative });
    [JsonIgnore] public bool Ground => Args.All(a => !a.StartsWith('?'));
    [JsonIgnore] public CaseLiteral Opposite => this with { Negative = !Negative };
    public CaseLiteral Substitute(IReadOnlyDictionary<string, string> bindings) =>
        this with { Args = Array.AsReadOnly(Args.Select(a => a.StartsWith('?') && bindings.TryGetValue(a, out var v) ? v : a).ToArray()) };
}
public sealed record CaseAxiom(string Id, CaseLiteral Literal, string Source);
public sealed record CaseRule(string Id, IReadOnlyList<CaseLiteral> Premises, CaseLiteral Conclusion, string Source);
public sealed record CaseTheorem(string Id, CaseLiteral Conclusion, CaseProof? Proof = null);
public sealed record CaseScope(string Id, IReadOnlyList<CaseAxiom> Axioms, IReadOnlyList<CaseRule> Rules, IReadOnlyList<CaseTheorem> Theorems);
public sealed record CaseCandidate(string Id, string Scope, IReadOnlyList<CaseLiteral> Requires, IReadOnlyList<CaseLiteral> Excludes);
public sealed record CaseProofNode(string Id, string Kind, CaseLiteral Conclusion, string Reference,
    IReadOnlyList<string> Parents, IReadOnlyDictionary<string, string> Substitution);
public sealed record CaseProof(string Scope, IReadOnlyList<CaseProofNode> Nodes, string TheoryHash = "");
public sealed record CaseCheckResult(bool Valid, IReadOnlyList<string> Errors);
public sealed record CaseCandidateReview(string Id, string Status, IReadOnlyList<CaseLiteral> Missing,
    IReadOnlyList<CaseLiteral> Refutations, IReadOnlyList<CaseLiteral> Conflicts);
public sealed record CaseGoalProof(CaseProof Certificate, IReadOnlyList<string> Axioms, IReadOnlyList<string> Rules);
public sealed record CaseGoalResult(string Scope, CaseLiteral Goal, string Status, CaseGoalProof? Support, CaseGoalProof? Refutation);

/// <summary>Finite, function-free signed Horn logic, not dependent type theory or full Lean.
/// Each scope is a separate theory: objective evidence is never imported into actor knowledge implicitly.</summary>
public sealed class CaseTheory
{
    public IReadOnlyDictionary<string, CaseScope> Scopes { get; }
    public IReadOnlyList<CaseCandidate> Candidates { get; }
    private CaseTheory(Dictionary<string, CaseScope> scopes, List<CaseCandidate> candidates)
    { Scopes = new ReadOnlyDictionary<string, CaseScope>(scopes); Candidates = candidates.AsReadOnly(); }

    public static CaseTheory Load(string path) => Parse(File.ReadAllText(path));
    public static CaseTheory Parse(string source)
    {
        return FromData(DvScriptReader.Parse(source).GetProperty("data").GetProperty("case_theory"));
    }
    public static CaseTheory FromData(JsonElement root)
    {
        if (root.TryGetProperty("script", out var script))
        {
            if (root.TryGetProperty("scopes", out _)) throw new FormatException("Use either script or scopes, not both");
            root = CaseProofScript.Elaborate(script.GetString() ?? "", root);
        }
        var scopes = new Dictionary<string, CaseScope>(StringComparer.Ordinal);
        foreach (var s in root.GetProperty("scopes").EnumerateArray())
        {
            var id = Text(s, "id");
            var axioms = Array(s, "axioms").Select(a => new CaseAxiom(Text(a, "id"), Literal(a.GetProperty("literal"), true), Text(a, "source"))).ToArray();
            var rules = Array(s, "rules").Select(r => new CaseRule(Text(r, "id"), System.Array.AsReadOnly(Array(r, "premises").Select(x => Literal(x, false)).ToArray()), Literal(r.GetProperty("conclusion"), false), Text(r, "source"))).ToArray();
            var theorems = Array(s, "theorems").Select(t => new CaseTheorem(Text(t, "id"), Literal(t.GetProperty("conclusion"), true))).ToArray();
            Unique(axioms.Select(a => a.Id).Concat(rules.Select(r => r.Id)).Concat(theorems.Select(t => t.Id)), "declaration");
            foreach (var rule in rules)
            {
                if (rule.Premises.Count > 64) throw new FormatException("Rule premise budget exceeded: " + rule.Id);
                var bound = rule.Premises.SelectMany(p => p.Args).Where(a => a.StartsWith('?')).ToHashSet(StringComparer.Ordinal);
                if (rule.Conclusion.Args.Any(a => a.StartsWith('?') && !bound.Contains(a))) throw new FormatException("Unsafe rule: " + rule.Id);
            }
            var scope = new CaseScope(id, System.Array.AsReadOnly(axioms), System.Array.AsReadOnly(rules), System.Array.AsReadOnly(theorems));
            var theoryCheck = CaseProofChecker.ValidateTheory(scope);
            if (!theoryCheck.Valid) throw new FormatException(string.Join("; ", theoryCheck.Errors));
            var theoremData = Array(s, "theorems").ToArray();
            for (var i = 0; i < theorems.Length; i++)
            {
                if (!theoremData[i].TryGetProperty("proof", out var proofData)) continue;
                var nodesData = proofData.ValueKind == JsonValueKind.Array ? proofData : proofData.GetProperty("nodes");
                var nodes = nodesData.EnumerateArray().Select(n => new CaseProofNode(Text(n, "id"), Text(n, "kind"), Literal(n.GetProperty("conclusion"), true),
                    n.TryGetProperty("reference", out var reference) ? reference.GetString() ?? "" : "",
                    System.Array.AsReadOnly(Array(n, "parents").Select(p => p.GetString() ?? "").ToArray()),
                    new ReadOnlyDictionary<string, string>(n.TryGetProperty("substitution", out var substitution) ? substitution.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString() ?? "", StringComparer.Ordinal) : new Dictionary<string, string>()))).ToArray();
                var proof = new CaseProof(id, System.Array.AsReadOnly(nodes), Fingerprint(scope));
                var check = CaseProofChecker.CheckGoal(scope, proof, theorems[i].Conclusion);
                if (!check.Valid)
                    throw new FormatException("Invalid theorem proof: " + theorems[i].Id + "; " + string.Join("; ", check.Errors));
                theorems[i] = theorems[i] with { Proof = proof };
            }
            if (!scopes.TryAdd(id, scope)) throw new FormatException("Duplicate scope: " + id);
        }
        var candidates = Array(root, "candidates").Select(c => new CaseCandidate(Text(c, "id"), Text(c, "scope"), System.Array.AsReadOnly(Array(c, "requires").Select(x => Literal(x, true)).ToArray()), System.Array.AsReadOnly(Array(c, "excludes").Select(x => Literal(x, true)).ToArray()))).ToList();
        Unique(candidates.Select(c => c.Id), "candidate");
        foreach (var c in candidates)
            if (!scopes.ContainsKey(c.Scope) || c.Requires.Count == 0) throw new FormatException("Candidate needs a known scope and explicit required evidence: " + c.Id);
        return new CaseTheory(scopes, candidates);
    }
    public static CaseTheory ParseScript(string script) => FromData(CaseProofScript.Elaborate(script));
    private static IEnumerable<JsonElement> Array(JsonElement e, string name) => e.TryGetProperty(name, out var a) ? a.EnumerateArray().ToArray() : System.Array.Empty<JsonElement>();
    private static string Text(JsonElement e, string name)
    {
        var value = e.GetProperty(name).GetString();
        return !string.IsNullOrWhiteSpace(value) ? value : throw new FormatException("Empty " + name);
    }
    private static CaseLiteral Literal(JsonElement e, bool ground)
    {
        foreach (var field in e.EnumerateObject())
            if (field.Name is not ("predicate" or "args" or "negative")) throw new FormatException("Unknown literal field: " + field.Name);
        var p = Text(e, "predicate");
        if (p.StartsWith('?')) throw new FormatException("Variable predicates are not supported");
        var args = Array(e, "args").Select(a => a.GetString() ?? throw new FormatException("Atom arguments must be strings")).ToArray();
        if (args.Any(a => string.IsNullOrWhiteSpace(a) || a == "?")) throw new FormatException("Empty atom argument");
        var result = new CaseLiteral(p, System.Array.AsReadOnly(args), e.TryGetProperty("negative", out var n) && n.GetBoolean());
        if (ground && !result.Ground) throw new FormatException("Expected ground literal");
        return result;
    }
    private static void Unique(IEnumerable<string> ids, string kind)
    { var seen = new HashSet<string>(StringComparer.Ordinal); foreach (var id in ids) if (!seen.Add(id)) throw new FormatException("Duplicate " + kind + ": " + id); }

    public CaseProof Infer(string scope, int maxNodes = 10000, int maxMatches = 1000000)
        => CaseInference.Infer(Scopes[scope], maxNodes, maxMatches);
    public CaseCheckResult Check(string scope, CaseProof proof) => CaseProofChecker.Check(Scopes[scope], proof);
    public CaseCheckResult CheckGoal(string scope, CaseProof proof, CaseLiteral goal) => CaseProofChecker.CheckGoal(Scopes[scope], proof, goal);

    /// <summary>Searches both signs and returns independently checkable, goal-rooted proof
    /// slices. Missing evidence remains unknown; contradiction never proves unrelated goals.</summary>
    public CaseGoalResult Prove(string scope, CaseLiteral goal, int maxNodes = 10000, int maxMatches = 1000000)
    {
        if (!CaseProofChecker.ValidLiteral(goal, true)) throw new ArgumentException("Goal must be a well-formed ground literal", nameof(goal));
        goal = goal with { Args = System.Array.AsReadOnly(goal.Args.ToArray()) };
        var closure = Infer(scope, maxNodes, maxMatches);
        var support = Slice(Scopes[scope], closure, goal);
        var refutation = Slice(Scopes[scope], closure, goal.Opposite);
        var status = support is not null && refutation is not null ? "conflicted" : support is not null ? "proved" : refutation is not null ? "refuted" : "unknown";
        return new(scope, goal, status, support, refutation);
    }

    private static CaseGoalProof? Slice(CaseScope scope, CaseProof closure, CaseLiteral goal)
    {
        var root = closure.Nodes.FirstOrDefault(n => n.Conclusion.Key == goal.Key);
        if (root is null) return null;
        var byId = closure.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var needed = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Stack<string>(); pending.Push(root.Id);
        while (pending.Count > 0)
        {
            var id = pending.Pop();
            if (!needed.Add(id)) continue;
            foreach (var parent in byId[id].Parents) pending.Push(parent);
        }
        var nodes = closure.Nodes.Where(n => needed.Contains(n.Id)).ToArray();
        var certificate = closure with { Nodes = System.Array.AsReadOnly(nodes) };
        var check = CaseProofChecker.CheckGoal(scope, certificate, goal);
        if (!check.Valid) throw new InvalidOperationException("Goal proof rejected: " + string.Join("; ", check.Errors));
        return new(certificate, System.Array.AsReadOnly(nodes.Where(n => n.Kind == "axiom").Select(n => n.Reference).Distinct(StringComparer.Ordinal).ToArray()),
            System.Array.AsReadOnly(nodes.Where(n => n.Kind == "apply").Select(n => n.Reference).Distinct(StringComparer.Ordinal).ToArray()));
    }

    public CaseTheory WithEvidence(string scope, IEnumerable<CaseAxiom> evidence)
    {
        var original = Scopes[scope];
        var added = evidence.Select(a => a with { Literal = a.Literal with { Args = System.Array.AsReadOnly(a.Literal.Args.ToArray()) } }).ToArray();
        foreach (var a in added)
            if (string.IsNullOrWhiteSpace(a.Id) || string.IsNullOrWhiteSpace(a.Source) || string.IsNullOrWhiteSpace(a.Literal.Predicate) || a.Literal.Predicate.StartsWith('?') || !a.Literal.Ground || a.Literal.Args.Any(string.IsNullOrWhiteSpace))
                throw new ArgumentException("Evidence must be a named ground axiom with a source");
        var axioms = original.Axioms.Concat(added).ToArray();
        Unique(axioms.Select(a => a.Id).Concat(original.Rules.Select(r => r.Id)).Concat(original.Theorems.Select(t => t.Id)), "declaration");
        var scopes = Scopes.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
        scopes[scope] = original with { Axioms = System.Array.AsReadOnly(axioms) };
        var check = CaseProofChecker.ValidateTheory(scopes[scope]);
        if (!check.Valid) throw new ArgumentException(string.Join("; ", check.Errors), nameof(evidence));
        return new CaseTheory(scopes, Candidates.ToList());
    }

    /// <summary>Retains authored inference rules and goals while requiring runtime
    /// evidence in place of a design scope's assumed observations.</summary>
    public CaseTheory WithoutAssumptions(string scope)
    {
        var scopes=Scopes.ToDictionary(p=>p.Key,p=>p.Value,StringComparer.Ordinal);
        var original=scopes[scope];
        scopes[scope]=original with {Axioms=System.Array.Empty<CaseAxiom>()};
        return new CaseTheory(scopes,Candidates.ToList());
    }

    public static string Fingerprint(CaseScope scope) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { scope.Id, scope.Axioms, scope.Rules }))));

    public CaseDesignReview EvaluateDesign(string scope)
    {
        var proof = Infer(scope);
        var facts = proof.Nodes.Select(n => n.Conclusion.Key).ToHashSet(StringComparer.Ordinal);
        var candidates = AuditCandidates(scope, proof);
        var supported = candidates.Where(c => c.Status == "supported").ToArray();
        var uniqueWithinDeclaredCandidates = supported.Length == 1 && candidates.All(c => c.Id == supported[0].Id || c.Status == "refuted");
        var goals = Scopes[scope].Theorems.Select(t => new CaseGoalReview(t.Id, facts.Contains(t.Conclusion.Key), facts.Contains(t.Conclusion.Opposite.Key))).ToArray();
        var removals = new List<CaseClueReview>();
        foreach (var axiom in Scopes[scope].Axioms)
        {
            var scopes = Scopes.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
            scopes[scope] = scopes[scope] with { Axioms = System.Array.AsReadOnly(scopes[scope].Axioms.Where(a => a.Id != axiom.Id).ToArray()) };
            var reduced = new CaseTheory(scopes, Candidates.ToList());
            var reducedFacts = reduced.Infer(scope).Nodes.Select(n => n.Conclusion.Key).ToHashSet(StringComparer.Ordinal);
            removals.Add(new CaseClueReview(axiom.Id, Scopes[scope].Theorems.Where(t => facts.Contains(t.Conclusion.Key) && !reducedFacts.Contains(t.Conclusion.Key)).Select(t => t.Id).ToArray(), reduced.AuditCandidates(scope)));
        }
        return new CaseDesignReview("declared_finite_candidates_only", uniqueWithinDeclaredCandidates, goals, candidates, removals, proof);
    }

    public IReadOnlyList<CaseCandidateReview> AuditCandidates(string scope, CaseProof? proof = null)
    {
        proof ??= Infer(scope);
        var check = Check(scope, proof);
        if (!check.Valid) throw new InvalidOperationException(string.Join("; ", check.Errors));
        // An incomplete caller-supplied proof cannot support a design exclusion claim.
        var closure = Infer(scope);
        var facts = closure.Nodes.Select(n => n.Conclusion.Key).ToHashSet(StringComparer.Ordinal);
        return Candidates.Where(c => c.Scope == scope).Select(c =>
        {
            var missing = c.Requires.Concat(c.Excludes.Select(p => p.Opposite)).Where(p => !facts.Contains(p.Key)).ToArray();
            var refutations = c.Requires.Select(p => p.Opposite).Concat(c.Excludes).Where(p => facts.Contains(p.Key)).ToArray();
            var conflicts = c.Requires.Concat(c.Excludes).Where(p => facts.Contains(p.Key) && facts.Contains(p.Opposite.Key)).ToArray();
            var status = conflicts.Length > 0 ? "conflicted" : refutations.Length > 0 ? "refuted" : missing.Length > 0 ? "unresolved" : "supported";
            return new CaseCandidateReview(c.Id, status, missing, refutations, conflicts);
        }).ToArray();
    }
}

public sealed record CaseGoalReview(string Id, bool Provable, bool OppositeProvable);
public sealed record CaseClueReview(string RemovedAxiom, IReadOnlyList<string> GoalsNoLongerProvable, IReadOnlyList<CaseCandidateReview> Candidates);
public sealed record CaseDesignReview(string Coverage, bool UniqueWithinDeclaredCandidates, IReadOnlyList<CaseGoalReview> Goals,
    IReadOnlyList<CaseCandidateReview> Candidates, IReadOnlyList<CaseClueReview> ClueRemoval, CaseProof Proof);
