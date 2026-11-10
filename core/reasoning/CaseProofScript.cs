using System.Text.Json;
using System.Text.RegularExpressions;

namespace DuelView.Core;

/// <summary>Elaborates a small Lean-inspired proof language into checker input.
/// This is not a DV parser or an implementation of Lean's type theory.</summary>
public sealed class CaseProofScript
{
    private readonly List<string> tokens = new();
    private int at;
    private readonly List<object> scopes = new();
    private readonly Dictionary<string, CaseAxiom> axioms = new(StringComparer.Ordinal);
    private readonly Dictionary<string, CaseRule> rules = new(StringComparer.Ordinal);
    private readonly Dictionary<string, CaseProof> lemmas = new(StringComparer.Ordinal);
    private readonly HashSet<string> declarations = new(StringComparer.Ordinal);
    private string scope = "";

    private CaseProofScript(string source)
    {
        if (source.Length > 1_000_000) throw new FormatException("Case script exceeds source budget");
        var pattern = new Regex(@"\G(?:\s+|--[^\r\n]*|(?<token>:=|->|→|∧|¬|[{}(),:;=&]|[?]?[\p{L}\p{N}_](?:[\p{L}\p{N}_.?/]|-(?!>))*))", RegexOptions.CultureInvariant);
        var offset = 0;
        while (offset < source.Length)
        {
            var match = pattern.Match(source, offset);
            if (!match.Success) throw new FormatException("Invalid case script character at offset " + offset);
            if (match.Groups["token"].Success) tokens.Add(match.Groups["token"].Value);
            offset += match.Length;
        }
        if (tokens.Count > 100_000) throw new FormatException("Case script exceeds token budget");
    }

    public static JsonElement Elaborate(string script, JsonElement? metadata = null)
    {
        var parser = new CaseProofScript(script);
        parser.Read();
        var result = new Dictionary<string, object> { ["scopes"] = parser.scopes };
        if (metadata is { } m && m.TryGetProperty("candidates", out var candidates)) result["candidates"] = candidates.Clone();
        return JsonSerializer.SerializeToElement(result);
    }

    private string Peek => at < tokens.Count ? tokens[at] : "<eof>";
    private bool Take(string token) { if (Peek != token) return false; at++; return true; }
    private void Need(string token) { if (!Take(token)) throw Error("Expected '" + token + "'"); }
    private FormatException Error(string message) => new(message + " at token " + at + " ('" + Peek + "')");
    private string Name()
    {
        var value = Peek;
        if (value == "<eof>" || !Regex.IsMatch(value, @"^[?]?[\p{L}\p{N}_][\p{L}\p{N}_.?/-]*$")) throw Error("Expected name");
        at++; return value;
    }
    private CaseLiteral Literal()
    {
        var negative = Take("not") || Take("¬");
        var predicate = Name();
        var args = new List<string>();
        if (Take("("))
        {
            if (!Take(")"))
            {
                do { args.Add(Name()); } while (Take(","));
                Need(")");
            }
        }
        return new CaseLiteral(predicate, args.AsReadOnly(), negative);
    }
    private void Read()
    {
        var scopeIds = new HashSet<string>(StringComparer.Ordinal);
        while (Peek != "<eof>")
        {
            Need("scope"); scope = Name();
            if (!scopeIds.Add(scope)) throw Error("Duplicate scope");
            var braced = Take("{");
            axioms.Clear(); rules.Clear(); lemmas.Clear(); declarations.Clear();
            var theoremRecords = new List<object>();
            while (Peek != (braced ? "}" : "end"))
            {
                var kind = Name();
                if (kind != "axiom" && kind != "theorem" && kind != "query") throw Error("Expected axiom, theorem or query");
                var id = Name();
                if (!declarations.Add(id)) throw Error("Duplicate declaration: " + id);
                Need(":");
                var first = Literal();
                if (kind == "axiom")
                {
                    var premises = new List<CaseLiteral> { first };
                    while (Take("&") || Take("∧")) premises.Add(Literal());
                    if (Take("->") || Take("→"))
                    {
                        var conclusion = Literal();
                        // Curried implications are elaborated to a conjunction of premises.
                        while (Take("->") || Take("→")) { premises.Add(conclusion); conclusion = Literal(); }
                        rules.Add(id, new CaseRule(id, premises.AsReadOnly(), conclusion, "script:" + scope + ":" + id));
                    }
                    else
                    {
                        if (premises.Count != 1 || !first.Ground) throw Error("Fact axiom must be one ground literal");
                        axioms.Add(id, new CaseAxiom(id, first, "script:" + scope + ":" + id));
                    }
                    Need(";");
                }
                else if (kind == "query")
                {
                    if (!first.Ground) throw Error("Query goal must be ground");
                    Need(";");
                    // A query declares a question, never an accepted premise or lemma.
                    theoremRecords.Add(new { id, conclusion = Atom(first) });
                }
                else
                {
                    if (!first.Ground) throw Error("Theorem goal must be ground");
                    Need(":="); Need("by");
                    var proofBraced = Take("{");
                    var nodes = new List<CaseProofNode>();
                    Prove(first, nodes, 0);
                    if (proofBraced) Need("}");
                    Take(";");
                    var context = new CaseScope(scope, axioms.Values.ToArray(), rules.Values.ToArray(), System.Array.Empty<CaseTheorem>());
                    var proof = new CaseProof(scope, nodes.AsReadOnly(), CaseTheory.Fingerprint(context));
                    var checkedProof = CaseProofChecker.CheckGoal(context, proof, first);
                    if (!checkedProof.Valid) throw Error("Elaborated proof rejected: " + string.Join("; ", checkedProof.Errors));
                    lemmas.Add(id, proof);
                    theoremRecords.Add(new { id, conclusion = Atom(first), proof = nodes.Select(Node).ToArray() });
                }
            }
            at++; Take(";");
            scopes.Add(new
            {
                id = scope,
                axioms = axioms.Values.Select(a => new { id = a.Id, literal = Atom(a.Literal), source = a.Source }).ToArray(),
                rules = rules.Values.Select(r => new { id = r.Id, premises = r.Premises.Select(Atom).ToArray(), conclusion = Atom(r.Conclusion), source = r.Source }).ToArray(),
                theorems = theoremRecords
            });
        }
        if (scopes.Count == 0) throw Error("Expected at least one scope");
    }

    private string Prove(CaseLiteral goal, List<CaseProofNode> nodes, int depth, IReadOnlyDictionary<string, string>? inherited = null)
    {
        if (depth > 256 || nodes.Count >= 10000) throw Error("Proof elaboration budget exhausted");
        var locals = inherited is null ? new Dictionary<string, string>(StringComparer.Ordinal)
            : inherited.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
        // Each subproof owns its local declarations. A local lemma is available only
        // after its proof finishes, and cannot escape into a sibling or later theorem.
        while (Take("have"))
        {
            var name = Name();
            if (declarations.Contains(name) || locals.ContainsKey(name)) throw Error("Duplicate local declaration: " + name);
            Need(":"); var claim = Literal();
            if (!claim.Ground) throw Error("Local lemma must be ground");
            Need(":="); Need("by"); Need("{");
            var proved = Prove(claim, nodes, depth + 1, locals);
            Need("}"); Take(";");
            locals.Add(name, proved);
        }
        var tactic = Name();
        var reference = Name();
        var bindings = new Dictionary<string, string>(StringComparer.Ordinal);
        if (Take("("))
        {
            if (!Take(")"))
            {
                do
                {
                    var variable = Name(); Need("="); var value = Name();
                    if (!variable.StartsWith('?') || value.StartsWith('?') || !bindings.TryAdd(variable, value)) throw Error("Invalid explicit rule binding");
                } while (Take(","));
                Need(")");
            }
        }
        Need(";");
        string Add(string kind, string target, IReadOnlyList<string> parents, IReadOnlyDictionary<string, string> substitution)
        {
            if (nodes.Count >= 10000) throw Error("Proof node budget exhausted");
            var id = "s" + nodes.Count;
            nodes.Add(new CaseProofNode(id, kind, goal, target, parents, substitution));
            return id;
        }
        if (tactic == "exact")
        {
            if (bindings.Count != 0) throw Error("exact does not accept bindings");
            if (locals.TryGetValue(reference, out var local))
            {
                if (nodes.Single(n => n.Id == local).Conclusion.Key != goal.Key) throw Error("exact local lemma does not match goal");
                return Add("exact", "", new[] { local }, bindings);
            }
            if (axioms.TryGetValue(reference, out var axiom))
            {
                if (axiom.Literal.Key != goal.Key) throw Error("exact axiom does not match goal");
                return Add("axiom", reference, System.Array.Empty<string>(), bindings);
            }
            if (lemmas.TryGetValue(reference, out var lemma))
            {
                if (lemma.Nodes[^1].Conclusion.Key != goal.Key) throw Error("exact theorem does not match goal");
                var remap = new Dictionary<string, string>(StringComparer.Ordinal);
                foreach (var node in lemma.Nodes)
                {
                    if (nodes.Count >= 10000) throw Error("Proof node budget exhausted");
                    var id = "s" + nodes.Count;
                    remap.Add(node.Id, id);
                    nodes.Add(node with { Id = id, Parents = node.Parents.Select(p => remap[p]).ToArray() });
                }
                return Add("exact", "", new[] { remap[lemma.Nodes[^1].Id] }, bindings);
            }
            throw Error("Unknown local axiom or prior theorem: " + reference);
        }
        if (tactic != "apply" || !rules.TryGetValue(reference, out var rule)) throw Error("Expected apply with a local rule");
        var variables = rule.Premises.Append(rule.Conclusion).SelectMany(l => l.Args).Where(a => a.StartsWith('?')).ToHashSet(StringComparer.Ordinal);
        if (bindings.Keys.Any(k => !variables.Contains(k))) throw Error("Unknown rule variable");
        if (rule.Conclusion.Predicate != goal.Predicate || rule.Conclusion.Negative != goal.Negative || rule.Conclusion.Args.Count != goal.Args.Count) throw Error("Rule conclusion does not match goal");
        for (var i = 0; i < goal.Args.Count; i++)
        {
            var term = rule.Conclusion.Args[i]; var value = goal.Args[i];
            if (term.StartsWith('?'))
            {
                if (bindings.TryGetValue(term, out var previous) && previous != value) throw Error("Inconsistent rule binding");
                bindings[term] = value;
            }
            else if (term != value) throw Error("Rule conclusion does not match goal");
        }
        if (!variables.SetEquals(bindings.Keys)) throw Error("Premise-only variables require explicit bindings, e.g. apply rule(?x=a)");
        var parents = rule.Premises.Select(p => Prove(p.Substitute(bindings), nodes, depth + 1, locals)).ToArray();
        return Add("apply", reference, parents, bindings);
    }

    private static object Atom(CaseLiteral literal) => new { predicate = literal.Predicate, args = literal.Args, negative = literal.Negative };
    private static object Node(CaseProofNode node) => new { id = node.Id, kind = node.Kind, conclusion = Atom(node.Conclusion), reference = node.Reference, parents = node.Parents, substitution = node.Substitution };
}
