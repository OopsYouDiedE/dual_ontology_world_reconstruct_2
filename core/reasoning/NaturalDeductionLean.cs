using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DuelView.Core;

public static partial class NaturalDeduction
{
    /// <summary>
    /// Authoring-only export of an actually checked DV proof to Lean 4 terms. This does not run Lean.
    /// DV premises become explicit theorem parameters, never Lean axiom or sorry declarations.
    /// The caller is responsible for selecting an authorized theory and writing only generated output.
    /// </summary>
    public static string ExportLean(JsonElement request, string moduleName)
    {
        Identifier(moduleName);
        return new LeanExporter().Export(request, moduleName);
    }

    private sealed class LeanExporter
    {
        private readonly Dictionary<string, Syntax> roots = new(StringComparer.Ordinal);
        private readonly Dictionary<Syntax, Formula> inferred = new(ReferenceEqualityComparer.Instance);
        private readonly SortedDictionary<string, int> predicates = new(StringComparer.Ordinal);
        private readonly SortedSet<string> constants = new(StringComparer.Ordinal);
        private readonly SortedSet<string> freeVariables = new(StringComparer.Ordinal);
        private static string Name(string category, string source) => category + "_" + Convert.ToHexString(Encoding.UTF8.GetBytes(source)).ToLowerInvariant();
        private static HashSet<string> Bound(HashSet<string> current, string variable) => new(current, StringComparer.Ordinal) { variable };
        private string TermText(Term term, HashSet<string> bound)
        {
            if (!term.Variable) { constants.Add(term.Name); return Name("c", term.Name); }
            if (!bound.Contains(term.Name)) freeVariables.Add(term.Name);
            return Name("v", term.Name);
        }
        private string FormulaText(Formula formula, HashSet<string> bound)
        {
            switch (formula.Kind)
            {
                case "atom":
                    predicates[formula.Name] = formula.Terms!.Length;
                    return "(" + Name("p", formula.Name) + string.Concat(formula.Terms.Select(t => " " + TermText(t, bound))) + ")";
                case "false": return "False";
                case "eq": return "(" + TermText(formula.Terms![0], bound) + " = " + TermText(formula.Terms[1], bound) + ")";
                case "all": case "exists":
                    return "(" + (formula.Kind == "all" ? "∀" : "∃") + " (" + Name("v", formula.Name) + " : D), "
                        + FormulaText(formula.Left!, Bound(bound, formula.Name)) + ")";
                case "and": case "or": case "imp":
                    var connective = formula.Kind switch { "and" => " ∧ ", "or" => " ∨ ", _ => " → " };
                    return "(" + FormulaText(formula.Left!, bound) + connective + FormulaText(formula.Right!, bound) + ")";
                default: throw new FormatException("Unsupported checked Lean formula: " + formula.Kind);
            }
        }
        private string ProofText(Syntax syntax, HashSet<string> bound)
        {
            // These are the exact AST objects visited by Kernel.Infer, with its computed node types.
            var result = inferred[syntax];
            var op = syntax.Children[0].Symbol();
            string P(int index) => ProofText(syntax.Arg(index), bound);
            string F(int index) => FormulaText(ReadFormula(syntax.Arg(index)), bound);
            string T(int index) => TermText(ReadTerm(syntax.Arg(index)), bound);
            string H(int index) => Name("h", syntax.Arg(index).Symbol());
            string body;
            switch (op)
            {
                case "use": body = H(0); break;
                case "intro": body = "(fun (" + H(0) + " : " + F(1) + ") => " + P(2) + ")"; break;
                case "apply": body = "(" + P(0) + " " + P(1) + ")"; break;
                case "pair": body = "(And.intro " + P(0) + " " + P(1) + ")"; break;
                case "fst": body = "(And.left " + P(0) + ")"; break;
                case "snd": body = "(And.right " + P(0) + ")"; break;
                case "left": body = "(Or.inl " + P(0) + ")"; break;
                case "right": body = "(Or.inr " + P(1) + ")"; break;
                case "cases":
                    var disjunction = inferred[syntax.Arg(0)];
                    body = "(Or.elim " + P(0)
                        + " (fun (" + H(1) + " : " + FormulaText(disjunction.Left!, bound) + ") => " + P(2) + ")"
                        + " (fun (" + H(3) + " : " + FormulaText(disjunction.Right!, bound) + ") => " + P(4) + "))";
                    break;
                case "absurd": body = "(False.elim " + P(0) + ")"; break;
                case "all_intro":
                    var variable = syntax.Arg(0).Symbol();
                    body = "(fun (" + Name("v", variable) + " : D) => " + ProofText(syntax.Arg(1), Bound(bound, variable)) + ")";
                    break;
                case "all_elim": body = "(" + P(0) + " " + T(1) + ")"; break;
                case "exists_intro": body = "(Exists.intro " + T(2) + " " + P(3) + ")"; break;
                case "exists_elim":
                    var existential = inferred[syntax.Arg(0)];
                    var eigen = syntax.Arg(1).Symbol(); var branchBound = Bound(bound, eigen);
                    var premise = existential.Left!.Substitute(existential.Name, new(eigen, true));
                    body = "(Exists.elim " + P(0) + " (fun (" + Name("v", eigen) + " : D) (" + H(2) + " : "
                        + FormulaText(premise, branchBound) + ") => " + ProofText(syntax.Arg(3), branchBound) + "))";
                    break;
                case "refl": body = "(Eq.refl " + T(0) + ")"; break;
                case "symm": body = "(Eq.symm " + P(0) + ")"; break;
                case "trans": body = "(Eq.trans " + P(0) + " " + P(1) + ")"; break;
                case "rewrite":
                    var equality = inferred[syntax.Arg(0)]; var hole = syntax.Arg(1).Symbol();
                    var motive = "(fun (" + Name("v", hole) + " : D) => " + FormulaText(ReadFormula(syntax.Arg(2)), Bound(bound, hole)) + ")";
                    body = "(@Eq.subst D " + motive + " " + TermText(equality.Terms![0], bound) + " "
                        + TermText(equality.Terms[1], bound) + " " + P(0) + " " + P(3) + ")";
                    break;
                default: throw new FormatException("Unsupported checked Lean proof constructor: " + op);
            }
            return "(show " + FormulaText(result, bound) + " from " + body + ")";
        }

        public string Export(JsonElement request, string moduleName)
        {
            _ = new Kernel((id, syntax) => roots.Add(id, syntax), (syntax, formula) => inferred.Add(syntax, formula)).Check(request);
            var empty = new HashSet<string>(StringComparer.Ordinal);
            var assumptions = new List<(string Id, string Formula)>();
            if (request.TryGetProperty("axioms", out var axioms))
                foreach (var axiom in axioms.EnumerateArray())
                    assumptions.Add((Text(axiom, "id"), FormulaText(ParseFormula(Text(axiom, "formula")), empty)));
            var lemmas = new StringBuilder();
            if (request.TryGetProperty("theorems", out var theorems))
                foreach (var theorem in theorems.EnumerateArray())
                {
                    var id = Text(theorem, "id");
                    lemmas.Append("  let ").Append(Name("h", id)).Append(" : ")
                        .Append(FormulaText(ParseFormula(Text(theorem, "formula")), empty)).Append(" :=\n    ")
                        .Append(ProofText(roots[id], empty)).Append("\n");
                }
            var goal = FormulaText(ParseFormula(Text(request, "goal")), empty);
            var proof = ProofText(roots["$goal"], empty);
            var module = Name("DvLean", moduleName);
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(request.GetRawText()))).ToLowerInvariant();
            var output = new StringBuilder("-- Generated from DV by the C# NaturalDeduction exporter. Do not edit.\n");
            output.Append("-- Request SHA256: ").Append(hash).Append('\n');
            output.Append("-- Source module: ").Append(moduleName).Append('\n');
            output.Append("-- DV premises are theorem parameters; the following theorem proves a conditional result.\n");
            output.Append("import Init\nset_option autoImplicit false\nset_option linter.unusedVariables false\n");
            output.Append("namespace ").Append(module).Append("\n\n");
            foreach (var p in predicates) output.Append("-- ").Append(Name("p", p.Key)).Append(" = predicate ").Append(p.Key).Append('\n');
            foreach (var c in constants) output.Append("-- ").Append(Name("c", c)).Append(" = constant ").Append(c).Append('\n');
            foreach (var a in assumptions) output.Append("-- ").Append(Name("h", a.Id)).Append(" = DV premise ").Append(a.Id).Append('\n');
            output.Append("theorem checked (D : Type)\n");
            foreach (var p in predicates)
                output.Append("    (").Append(Name("p", p.Key)).Append(" : ").Append(string.Concat(Enumerable.Repeat("D → ", p.Value))).Append("Prop)\n");
            foreach (var c in constants) output.Append("    (").Append(Name("c", c)).Append(" : D)\n");
            foreach (var v in freeVariables) output.Append("    (").Append(Name("v", v)).Append(" : D)\n");
            foreach (var a in assumptions) output.Append("    (").Append(Name("h", a.Id)).Append(" : ").Append(a.Formula).Append(")\n");
            output.Append("    : ").Append(goal).Append(" :=\n").Append(lemmas).Append("  ").Append(proof).Append("\n\n");
            output.Append("#print axioms checked\nend ").Append(module).Append('\n');
            return output.ToString();
        }
    }
}
