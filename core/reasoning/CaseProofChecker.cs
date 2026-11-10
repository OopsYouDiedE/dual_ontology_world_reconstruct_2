namespace DuelView.Core;

/// <summary>The small trusted checker does not invoke proof search. All edges point to earlier nodes.</summary>
public static class CaseProofChecker
{
    public static CaseCheckResult Check(CaseScope theory, CaseProof proof)
    {
        CaseCheckResult? result = null;
        foreach (var _ in CheckSteps(theory, proof, value => result = value)) { }
        return result!;
    }

    // The synchronous and sliced callers consume the same independent checker.
    internal static IEnumerable<int> CheckSteps(CaseScope theory, CaseProof proof, Action<CaseCheckResult> complete)
    {
        var errors = new List<string>();
        CaseCheckResult? theoryCheck = null;
        foreach (var step in ValidateTheorySteps(theory, value => theoryCheck = value)) yield return step;
        if (!theoryCheck!.Valid) { complete(theoryCheck); yield break; }
        if (proof is null || proof.Nodes is null) { complete(new CaseCheckResult(false, new[] { "Missing proof or nodes" })); yield break; }
        if (proof.Nodes.Count > 10000) { complete(new CaseCheckResult(false, new[] { "Proof node budget exceeded" })); yield break; }
        if (proof.Scope != theory.Id) errors.Add("Proof scope differs from theory");
        string? fingerprint = null;
        foreach (var step in CaseWorkFingerprint.Steps(theory, value => fingerprint = value)) yield return step;
        if (proof.TheoryHash != fingerprint) errors.Add("Proof belongs to a different theory version");
        var nodes = new Dictionary<string, CaseProofNode>(StringComparer.Ordinal);
        var axioms = new Dictionary<string, CaseAxiom>(StringComparer.Ordinal);
        var rules = new Dictionary<string, CaseRule>(StringComparer.Ordinal);
        foreach (var axiom in theory.Axioms) { axioms.Add(axiom.Id, axiom); yield return 0; }
        foreach (var rule in theory.Rules) { rules.Add(rule.Id, rule); yield return 0; }
        foreach (var node in proof.Nodes)
        {
            yield return 0;
            // Certificates can arrive from a JSON client rather than the DV elaborator.
            // Malformed nodes must be rejected, never dereferenced as trusted objects.
            if (node is null || node.Conclusion is null || node.Conclusion.Args is null || node.Parents is null || node.Substitution is null || node.Reference is null ||
                string.IsNullOrWhiteSpace(node.Conclusion.Predicate) || node.Conclusion.Predicate.StartsWith('?') ||
                node.Conclusion.Args.Any(string.IsNullOrWhiteSpace) || node.Parents.Any(string.IsNullOrWhiteSpace))
            { errors.Add("Malformed proof node"); continue; }
            if (string.IsNullOrWhiteSpace(node.Id) || nodes.ContainsKey(node.Id)) { errors.Add("Duplicate or empty proof node: " + node.Id); continue; }
            var valid = node.Conclusion.Ground;
            if (node.Kind == "axiom")
                valid &= node.Parents.Count == 0 && node.Substitution.Count == 0 && axioms.TryGetValue(node.Reference, out var a) && a.Literal.Key == node.Conclusion.Key;
            else if (node.Kind == "apply" && rules.TryGetValue(node.Reference, out var rule))
            {
                var variables = rule.Premises.Append(rule.Conclusion).SelectMany(l => l.Args).Where(a => a.StartsWith('?')).ToHashSet(StringComparer.Ordinal);
                valid &= variables.SetEquals(node.Substitution.Keys) && node.Substitution.Values.All(v => !string.IsNullOrWhiteSpace(v) && !v.StartsWith('?'));
                valid &= rule.Premises.Count == node.Parents.Count && rule.Conclusion.Substitute(node.Substitution).Key == node.Conclusion.Key;
                if (rule.Premises.Count == node.Parents.Count)
                    for (var i = 0; i < rule.Premises.Count; i++)
                    {
                        valid &= nodes.TryGetValue(node.Parents[i], out var parent) && parent.Conclusion.Key == rule.Premises[i].Substitute(node.Substitution).Key;
                        yield return 0;
                    }
            }
            else if (node.Kind == "exact")
                valid &= node.Reference.Length == 0 && node.Substitution.Count == 0 && node.Parents.Count == 1 && nodes.TryGetValue(node.Parents[0], out var parent) && parent.Conclusion.Key == node.Conclusion.Key;
            else valid = false;
            if (!valid) errors.Add("Invalid proof node: " + node.Id);
            else nodes.Add(node.Id, node);
        }
        complete(new CaseCheckResult(errors.Count == 0, errors.AsReadOnly()));
    }

    /// <summary>A valid derivation alone does not assert a particular goal. Goal certificates
    /// must end in the requested atom; an empty or unrelated derivation never proves it.</summary>
    public static CaseCheckResult CheckGoal(CaseScope theory, CaseProof proof, CaseLiteral goal)
    {
        var check = Check(theory, proof);
        if (!check.Valid) return check;
        if (!ValidLiteral(goal, true)) return new(false, new[] { "Goal must be a well-formed ground literal" });
        return proof.Nodes.Count > 0 && proof.Nodes[^1].Conclusion.Key == goal.Key
            ? check : new(false, new[] { "Proof does not conclude the requested goal" });
    }

    // Public records can be created without the DV loader. The trusted boundary checks
    // the theory as well as its certificate, instead of trusting constructor provenance.
    public static CaseCheckResult ValidateTheory(CaseScope theory)
    {
        CaseCheckResult? result = null;
        foreach (var _ in ValidateTheorySteps(theory, value => result = value)) { }
        return result!;
    }

    internal static IEnumerable<int> ValidateTheorySteps(CaseScope theory, Action<CaseCheckResult> complete)
    {
        var errors = new List<string>();
        if (theory is null || string.IsNullOrWhiteSpace(theory.Id) || theory.Axioms is null || theory.Rules is null || theory.Theorems is null)
        { complete(new(false, new[] { "Missing or malformed theory" })); yield break; }
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var arities = new Dictionary<string, int>(StringComparer.Ordinal);
        bool Declaration(string id) => !string.IsNullOrWhiteSpace(id) && ids.Add(id);
        bool Atom(CaseLiteral literal, bool ground)
        {
            if (!ValidLiteral(literal, ground)) return false;
            if (arities.TryGetValue(literal.Predicate, out var arity)) return arity == literal.Args.Count;
            arities.Add(literal.Predicate, literal.Args.Count); return true;
        }
        foreach (var a in theory.Axioms)
        {
            if (a is null || !Declaration(a.Id) || string.IsNullOrWhiteSpace(a.Source) || !Atom(a.Literal, true))
                errors.Add("Malformed or duplicate axiom");
            yield return 0;
        }
        foreach (var r in theory.Rules)
        {
            yield return 0;
            if (r is null || !Declaration(r.Id) || string.IsNullOrWhiteSpace(r.Source) || r.Premises is null ||
                r.Premises.Count > 64 || !Atom(r.Conclusion, false) || r.Premises.Any(p => !Atom(p, false)))
            { errors.Add("Malformed or duplicate rule"); continue; }
            var bound = r.Premises.SelectMany(p => p.Args).Where(a => a.StartsWith('?')).ToHashSet(StringComparer.Ordinal);
            if (r.Conclusion.Args.Any(a => a.StartsWith('?') && !bound.Contains(a))) errors.Add("Unsafe rule: " + r.Id);
        }
        foreach (var t in theory.Theorems)
        {
            if (t is null || !Declaration(t.Id) || !Atom(t.Conclusion, true)) errors.Add("Malformed or duplicate theorem");
            yield return 0;
        }
        complete(new(errors.Count == 0, errors.AsReadOnly()));
    }

    public static bool ValidLiteral(CaseLiteral literal, bool ground) => literal is not null &&
        !string.IsNullOrWhiteSpace(literal.Predicate) && !literal.Predicate.StartsWith('?') && literal.Args is not null &&
        literal.Args.All(a => !string.IsNullOrWhiteSpace(a) && a != "?" && (!ground || !a.StartsWith('?')));
}

/// <summary>Untrusted bounded proof search. Its result must pass the independent checker.</summary>
internal static class CaseInference
{
    internal static CaseProof Infer(CaseScope scope, int maxNodes, int maxMatches)
    {
        using var work = new CaseInferenceWork(scope, maxNodes, maxMatches);
        return work.RunToCompletion();
    }
}
