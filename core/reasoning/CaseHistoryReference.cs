using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DuelView.Core;

/// <summary>Explicit, verified objective imports. Actor scopes receive no implicit historical knowledge.</summary>
public static class CaseHistoryReference
{
    public static CaseTheory Apply(CaseTheory theory, JsonElement data, Func<string, JsonElement> resolve)
    {
        if (!data.TryGetProperty("case_history_reference", out var reference)) return theory;
        var caseId = reference.GetProperty("case_id").GetString() ?? throw new FormatException("Missing referenced history");
        var history = resolve(caseId).GetProperty("case_history");
        // Old saves may contain an informational reference without import declarations.
        if (!reference.TryGetProperty("imports", out var imports))
        {
            if (!reference.TryGetProperty("exports", out var exports)) return theory;
            if (exports.GetString() != "final") throw new FormatException("Unknown history export selection");
            imports = history.GetProperty("required_final_facts");
        }
        if (reference.GetProperty("scope").GetString() != "objective" || !theory.Scopes.ContainsKey("objective"))
            throw new FormatException("History imports require an explicit objective scope");
        var checkedHistory = CaseHistory.Check(history);
        if (!checkedHistory.Valid) throw new FormatException("Referenced history failed verification: " + caseId + "; " +
            string.Join("; ", checkedHistory.Issues.Take(12).Select(issue => issue.Event + " [" + issue.Kind + "] " + issue.Detail)) +
            (checkedHistory.Issues.Count > 12 ? "; additional issues: " + (checkedHistory.Issues.Count - 12) : ""));
        var established = checkedHistory.FinalFacts.ToHashSet(StringComparer.Ordinal);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(history.GetRawText())));
        var facts = new List<CaseAxiom>();
        foreach (var mapping in imports.EnumerateArray())
        {
            var fact = mapping.GetString() ?? throw new FormatException("History import must name a fact");
            if (!established.Contains(fact)) throw new FormatException("History does not establish imported fact: " + fact);
            facts.Add(new("history_" + fact, new CaseLiteral("history_fact", new[] { caseId, fact }), "verified-history:" + caseId + ":" + hash + ":" + fact));
        }
        return theory.WithEvidence("objective", facts);
    }
}
