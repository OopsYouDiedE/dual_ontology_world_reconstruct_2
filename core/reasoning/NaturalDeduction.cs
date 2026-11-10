using System.Text.Json;

namespace DuelView.Core;

public sealed record NaturalDeductionResult(bool Valid, string? Conclusion, IReadOnlyList<string> Errors,
    IReadOnlyList<string> AxiomsUsed);
public sealed record NaturalDeductionAuditItem(string Id, string Scope, string Expected, string Actual, bool Passed);

/// <summary>A bounded intuitionistic first-order proof-term checker, independent of signed Horn reasoning.</summary>
public static partial class NaturalDeduction
{
    public static NaturalDeductionResult Check(JsonElement request)
    {
        try { return new Kernel().Check(request); }
        catch (Exception ex) when (ex is FormatException or InvalidOperationException or KeyNotFoundException or ArgumentException)
        { return new(false, null, new[] { ex.Message }, Array.Empty<string>()); }
    }

    public static IReadOnlyList<NaturalDeductionAuditItem> Audit(JsonElement audit)
    {
        var results = new List<NaturalDeductionAuditItem>();
        foreach (var check in audit.GetProperty("checks").EnumerateArray())
        {
            var expected = Text(check, "expect");
            if (expected is not ("valid" or "invalid")) throw new FormatException("Invalid natural deduction audit expectation.");
            var result = Check(check);
            var actual = result.Valid ? "valid" : "invalid";
            var id = Text(check, "id");
            var scope = check.TryGetProperty("scope", out var scopeValue) ? scopeValue.GetString()! : "objective";
            results.Add(new(id, scope, expected, actual, expected == actual));
            if (check.TryGetProperty("expect_conclusion", out var conclusion))
            {
                var expectedConclusion = conclusion.GetString()!;
                results.Add(new(id + ":conclusion", scope, expectedConclusion, result.Conclusion ?? "missing",
                    result.Valid && expectedConclusion == result.Conclusion));
            }
            if (check.TryGetProperty("expect_axioms", out var dependencies))
            {
                var expectedDependencies = string.Join(",", dependencies.EnumerateArray().Select(x => x.GetString()!).OrderBy(x => x, StringComparer.Ordinal));
                var actualDependencies = string.Join(",", result.AxiomsUsed);
                results.Add(new(id + ":axioms", scope, expectedDependencies, actualDependencies,
                    result.Valid && expectedDependencies == actualDependencies));
            }
        }
        return results.AsReadOnly();
    }

    private static string Text(JsonElement value, string key) => value.GetProperty(key).GetString()
        ?? throw new FormatException("Expected text: " + key);
    private static void Require(bool condition, string message)
    { if (!condition) throw new FormatException(message); }

    // Terms are variables (?x) or rigid constants. There are no function symbols, unification metavariables or sorts.
    private sealed record Term(string Name, bool Variable)
    {
        public override string ToString() => Variable ? "?" + Name : Name;
    }

    private sealed record Formula(string Kind, string Name = "", Formula? Left = null, Formula? Right = null,
        Term[]? Terms = null)
    {
        public IEnumerable<string> Free()
        {
            if (Terms is not null) foreach (var t in Terms) if (t.Variable) yield return t.Name;
            if (Left is not null) foreach (var v in Left.Free()) if (Kind is not ("all" or "exists") || v != Name) yield return v;
            if (Right is not null) foreach (var v in Right.Free()) yield return v;
        }
        public IEnumerable<string> Variables()
        {
            if (Kind is "all" or "exists") yield return Name;
            if (Terms is not null) foreach (var t in Terms) if (t.Variable) yield return t.Name;
            if (Left is not null) foreach (var v in Left.Variables()) yield return v;
            if (Right is not null) foreach (var v in Right.Variables()) yield return v;
        }
        public Formula Substitute(string variable, Term replacement)
        {
            if (Kind is "all" or "exists")
            {
                if (Name == variable) return this;
                var body = Left!;
                var binder = Name;
                if (replacement.Variable && replacement.Name == binder && body.Free().Contains(variable))
                {
                    var used = body.Variables().Append(variable).Append(replacement.Name).ToHashSet(StringComparer.Ordinal);
                    var fresh = "fresh";
                    while (used.Contains(fresh)) fresh += "_";
                    body = body.Substitute(binder, new(fresh, true));
                    binder = fresh;
                }
                return this with { Name = binder, Left = body.Substitute(variable, replacement) };
            }
            return this with
            {
                Terms = Terms?.Select(t => t.Variable && t.Name == variable ? replacement : t).ToArray(),
                Left = Left?.Substitute(variable, replacement), Right = Right?.Substitute(variable, replacement)
            };
        }
        public string Render() => Kind switch
        {
            "atom" => "(at " + Name + (Terms!.Length == 0 ? "" : " " + string.Join(" ", Terms.Select(t => t.ToString()))) + ")",
            "false" => "false",
            "eq" => "(eq " + string.Join(" ", Terms!.Select(t => t.ToString())) + ")",
            "all" or "exists" => "(" + Kind + " " + Name + " " + Left!.Render() + ")",
            _ => "(" + Kind + " " + Left!.Render() + " " + Right!.Render() + ")"
        };
        public int Size() => 1 + (Terms?.Length ?? 0) + (Left?.Size() ?? 0) + (Right?.Size() ?? 0);
    }

    // Alpha equivalence compares lexical binder indices, never spelling substitution or a lossy serialized key.
    private static bool Same(Formula a, Formula b) => Same(a, b, new(), new());
    private static bool Same(Formula a, Formula b, List<string> leftBinders, List<string> rightBinders)
    {
        if (a.Kind != b.Kind || (a.Kind == "atom" && a.Name != b.Name)) return false;
        if (a.Terms is not null)
        {
            if (b.Terms is null || a.Terms.Length != b.Terms.Length) return false;
            for (var i = 0; i < a.Terms.Length; i++)
            {
                var x = a.Terms[i]; var y = b.Terms[i];
                if (x.Variable != y.Variable) return false;
                if (!x.Variable) { if (x.Name != y.Name) return false; continue; }
                var xi = leftBinders.LastIndexOf(x.Name); var yi = rightBinders.LastIndexOf(y.Name);
                if (xi != yi || (xi < 0 && x.Name != y.Name)) return false;
            }
        }
        var binding = a.Kind is "all" or "exists";
        if (binding) { leftBinders.Add(a.Name); rightBinders.Add(b.Name); }
        var equal = (a.Left is null || (b.Left is not null && Same(a.Left, b.Left, leftBinders, rightBinders)))
            && (a.Right is null || (b.Right is not null && Same(a.Right, b.Right, leftBinders, rightBinders)));
        if (binding) { leftBinders.RemoveAt(leftBinders.Count - 1); rightBinders.RemoveAt(rightBinders.Count - 1); }
        return equal;
    }

    private sealed record Syntax(string? Atom, Syntax[] Children)
    {
        public string Symbol() => Atom ?? throw new FormatException("Expected a symbol.");
        public Syntax Arg(int index) => Children[index + 1];
        public string Operator(int arity)
        {
            Require(Atom is null && Children.Length == arity + 1, "Invalid proof or formula arity.");
            return Children[0].Symbol();
        }
    }

    private sealed class Reader(string text)
    {
        private int position, nodes;
        public Syntax Read()
        {
            Require(text.Length <= 100_000, "Natural deduction source length budget exceeded.");
            var result = ReadNode(0); Space();
            Require(position == text.Length, "Trailing natural deduction syntax.");
            return result;
        }
        private void Space() { while (position < text.Length && char.IsWhiteSpace(text[position])) position++; }
        private Syntax ReadNode(int depth)
        {
            Require(depth <= 96 && ++nodes <= 8192, "Natural deduction syntax budget exceeded.");
            Space(); Require(position < text.Length, "Unexpected end of natural deduction syntax.");
            if (text[position] == '(')
            {
                position++; var children = new List<Syntax>();
                while (true)
                {
                    Space(); Require(position < text.Length, "Unclosed natural deduction expression.");
                    if (text[position] == ')') { position++; break; }
                    children.Add(ReadNode(depth + 1));
                }
                Require(children.Count > 0, "Empty natural deduction expression.");
                return new(null, children.ToArray());
            }
            var start = position;
            while (position < text.Length && !char.IsWhiteSpace(text[position]) && text[position] is not ('(' or ')')) position++;
            Require(position > start, "Unexpected closing parenthesis.");
            return new(text[start..position], Array.Empty<Syntax>());
        }
    }

    private static string Identifier(string value)
    {
        Require(value.Length is > 0 and <= 128 && (char.IsLetter(value[0]) || value[0] == '_')
            && value.All(c => char.IsLetterOrDigit(c) || c is '_' or '.' or '-'), "Invalid natural deduction identifier: " + value);
        Require(value != "sorry", "sorry is forbidden.");
        return value;
    }
    private static Term ReadTerm(Syntax syntax)
    {
        var value = syntax.Symbol();
        return value.StartsWith('?') ? new(Identifier(value[1..]), true) : new(Identifier(value), false);
    }
    private static Formula ReadFormula(Syntax syntax)
    {
        if (syntax.Atom is not null)
            return syntax.Atom == "false" ? new("false") : new("atom", Identifier(syntax.Atom), Terms: Array.Empty<Term>());
        var op = syntax.Children[0].Symbol();
        switch (op)
        {
            case "at":
                Require(syntax.Children.Length >= 2, "at needs a predicate name.");
                return new("atom", Identifier(syntax.Arg(0).Symbol()), Terms: syntax.Children.Skip(2).Select(ReadTerm).ToArray());
            case "and": case "or": case "imp":
                syntax.Operator(2); return new(op, Left: ReadFormula(syntax.Arg(0)), Right: ReadFormula(syntax.Arg(1)));
            case "all": case "exists":
                syntax.Operator(2); return new(op, Identifier(syntax.Arg(0).Symbol()), ReadFormula(syntax.Arg(1)));
            case "eq":
                syntax.Operator(2); return new(op, Terms: new[] { ReadTerm(syntax.Arg(0)), ReadTerm(syntax.Arg(1)) });
            default: throw new FormatException("Unknown formula constructor: " + op);
        }
    }
    private static Formula ParseFormula(string text) => ReadFormula(new Reader(text).Read());

    private sealed record Global(Formula Formula, string[] Dependencies);
    private sealed class Kernel(Action<string, Syntax>? onProof = null, Action<Syntax, Formula>? onInferred = null)
    {
        private readonly Dictionary<string, Global> globals = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> predicates = new(StringComparer.Ordinal);
        private readonly HashSet<string> used = new(StringComparer.Ordinal);
        private int steps;
        private Syntax Proof(string text, string id)
        {
            var syntax = new Reader(text).Read();
            onProof?.Invoke(id, syntax);
            return syntax;
        }
        private Formula WellFormed(Formula formula)
        {
            Require(formula.Size() <= 8192, "Natural deduction formula size budget exceeded.");
            void Visit(Formula f)
            {
                if (f.Kind == "atom")
                {
                    if (predicates.TryGetValue(f.Name, out var arity)) Require(arity == f.Terms!.Length, "Predicate arity changed: " + f.Name);
                    else predicates.Add(f.Name, f.Terms!.Length);
                }
                if (f.Left is not null) Visit(f.Left);
                if (f.Right is not null) Visit(f.Right);
            }
            Visit(formula); return formula;
        }
        private Formula Formula(Syntax syntax) => WellFormed(ReadFormula(syntax));
        private Formula Closed(string text)
        {
            var formula = WellFormed(ParseFormula(text));
            Require(!formula.Free().Any(), "Axioms, theorem statements and final goals must be closed.");
            return formula;
        }
        public NaturalDeductionResult Check(JsonElement request)
        {
            if (request.TryGetProperty("axioms", out var axioms))
                foreach (var axiom in axioms.EnumerateArray())
                {
                    Require(globals.Count < 1024, "Natural deduction declaration budget exceeded.");
                    var id = Identifier(Text(axiom, "id"));
                    Require(globals.TryAdd(id, new(Closed(Text(axiom, "formula")), new[] { id })), "Duplicate global proof name: " + id);
                }
            if (request.TryGetProperty("theorems", out var theorems))
                foreach (var theorem in theorems.EnumerateArray())
                {
                    Require(globals.Count < 1024, "Natural deduction declaration budget exceeded.");
                    var id = Identifier(Text(theorem, "id"));
                    Require(!globals.ContainsKey(id), "Duplicate global proof name: " + id);
                    var target = Closed(Text(theorem, "formula")); used.Clear();
                    var proved = Infer(Proof(Text(theorem, "proof"), id), new(StringComparer.Ordinal), new(StringComparer.Ordinal), 0);
                    Require(Same(target, proved), "Theorem proof does not establish its statement: " + id);
                    globals.Add(id, new(target, used.OrderBy(x => x, StringComparer.Ordinal).ToArray()));
                }
            var goal = Closed(Text(request, "goal")); used.Clear();
            var conclusion = Infer(Proof(Text(request, "proof"), "$goal"), new(StringComparer.Ordinal), new(StringComparer.Ordinal), 0);
            Require(Same(goal, conclusion), "Proof conclusion differs from requested goal.");
            return new(true, conclusion.Render(), Array.Empty<string>(), used.OrderBy(x => x, StringComparer.Ordinal).ToArray());
        }

        private Formula Infer(Syntax syntax, Dictionary<string, Formula> context, HashSet<string> eigenvariables, int depth)
        {
            Require(depth <= 96 && ++steps <= 32768, "Natural deduction proof budget exceeded.");
            Require(syntax.Atom is null, "Proof terms must name a constructor, not a bare symbol.");
            var op = syntax.Children[0].Symbol();
            Formula Sub(int i) => Infer(syntax.Arg(i), context, eigenvariables, depth + 1);
            Formula Branch(string id, Formula assumption, Syntax body, string? eigen = null)
            {
                Identifier(id);
                Require(!context.ContainsKey(id) && !globals.ContainsKey(id), "Assumption shadows a proof name: " + id);
                var local = new Dictionary<string, Formula>(context, StringComparer.Ordinal) { [id] = assumption };
                var variables = new HashSet<string>(eigenvariables, StringComparer.Ordinal);
                if (eigen is not null) variables.Add(eigen);
                return Infer(body, local, variables, depth + 1);
            }
            void Fresh(string variable)
            {
                Identifier(variable);
                Require(!eigenvariables.Contains(variable) && !context.Values.Any(f => f.Free().Contains(variable)),
                    "Eigenvariable is not fresh in the open context: " + variable);
            }
            Formula result;
            switch (op)
            {
                case "use":
                    syntax.Operator(1); var name = Identifier(syntax.Arg(0).Symbol());
                    if (context.TryGetValue(name, out var local)) result = local;
                    else if (globals.TryGetValue(name, out var global)) { used.UnionWith(global.Dependencies); result = global.Formula; }
                    else throw new FormatException("Unbound proof reference: " + name);
                    break;
                case "intro":
                    syntax.Operator(3); var premise = Formula(syntax.Arg(1));
                    result = new("imp", Left: premise, Right: Branch(syntax.Arg(0).Symbol(), premise, syntax.Arg(2))); break;
                case "apply":
                    syntax.Operator(2); var implication = Sub(0); var argument = Sub(1);
                    Require(implication.Kind == "imp" && Same(implication.Left!, argument), "Implication elimination premise mismatch.");
                    result = implication.Right!; break;
                case "pair":
                    syntax.Operator(2); result = new("and", Left: Sub(0), Right: Sub(1)); break;
                case "fst": case "snd":
                    syntax.Operator(1); var conjunction = Sub(0);
                    Require(conjunction.Kind == "and", "Conjunction elimination requires and.");
                    result = op == "fst" ? conjunction.Left! : conjunction.Right!; break;
                case "left":
                    syntax.Operator(2); result = new("or", Left: Sub(0), Right: Formula(syntax.Arg(1))); break;
                case "right":
                    syntax.Operator(2); result = new("or", Left: Formula(syntax.Arg(0)), Right: Sub(1)); break;
                case "cases":
                    syntax.Operator(5); var disjunction = Sub(0);
                    Require(disjunction.Kind == "or", "Disjunction elimination requires or.");
                    var first = Branch(syntax.Arg(1).Symbol(), disjunction.Left!, syntax.Arg(2));
                    var second = Branch(syntax.Arg(3).Symbol(), disjunction.Right!, syntax.Arg(4));
                    Require(Same(first, second), "Both disjunction branches must prove the same conclusion."); result = first; break;
                case "absurd":
                    syntax.Operator(2); Require(Sub(0).Kind == "false", "False elimination requires a proof of false.");
                    result = Formula(syntax.Arg(1)); break;
                case "all_intro":
                    syntax.Operator(2); var variable = syntax.Arg(0).Symbol(); Fresh(variable);
                    var extended = new HashSet<string>(eigenvariables, StringComparer.Ordinal) { variable };
                    result = new("all", variable, Infer(syntax.Arg(1), context, extended, depth + 1)); break;
                case "all_elim":
                    syntax.Operator(2); var universal = Sub(0);
                    Require(universal.Kind == "all", "Universal elimination requires all.");
                    result = universal.Left!.Substitute(universal.Name, ReadTerm(syntax.Arg(1))); break;
                case "exists_intro":
                    syntax.Operator(4); var binder = Identifier(syntax.Arg(0).Symbol()); var template = Formula(syntax.Arg(1));
                    var witness = ReadTerm(syntax.Arg(2)); var witnessProof = Sub(3);
                    Require(Same(template.Substitute(binder, witness), witnessProof), "Existential witness proof mismatch.");
                    result = new("exists", binder, template); break;
                case "exists_elim":
                    syntax.Operator(4); var existential = Sub(0);
                    Require(existential.Kind == "exists", "Existential elimination requires exists.");
                    var eigen = syntax.Arg(1).Symbol(); Fresh(eigen);
                    Require(!existential.Free().Contains(eigen), "Existential eigenvariable occurs in the existential premise.");
                    result = Branch(syntax.Arg(2).Symbol(), existential.Left!.Substitute(existential.Name, new(eigen, true)), syntax.Arg(3), eigen);
                    Require(!result.Free().Contains(eigen), "Existential eigenvariable escapes into the conclusion."); break;
                case "refl":
                    syntax.Operator(1); var term = ReadTerm(syntax.Arg(0)); result = new("eq", Terms: new[] { term, term }); break;
                case "symm":
                    syntax.Operator(1); var equality = Sub(0); Require(equality.Kind == "eq", "Symmetry requires equality.");
                    result = new("eq", Terms: new[] { equality.Terms![1], equality.Terms[0] }); break;
                case "trans":
                    syntax.Operator(2); var one = Sub(0); var two = Sub(1);
                    Require(one.Kind == "eq" && two.Kind == "eq" && one.Terms![1] == two.Terms![0], "Equality transitivity middle term mismatch.");
                    result = new("eq", Terms: new[] { one.Terms![0], two.Terms![1] }); break;
                case "rewrite":
                    syntax.Operator(4); var eq = Sub(0); Require(eq.Kind == "eq", "Rewrite requires equality.");
                    var hole = Identifier(syntax.Arg(1).Symbol()); var motive = Formula(syntax.Arg(2)); var original = Sub(3);
                    Require(Same(motive.Substitute(hole, eq.Terms![0]), original), "Equality rewrite source proof mismatch.");
                    result = motive.Substitute(hole, eq.Terms[1]); break;
                default: throw new FormatException("Unknown proof constructor (sorry is forbidden): " + op);
            }
            result = WellFormed(result);
            onInferred?.Invoke(syntax, result);
            return result;
        }
    }
}
