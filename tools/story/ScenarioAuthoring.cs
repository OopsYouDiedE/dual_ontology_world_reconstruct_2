using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using DuelView.Core;
using DuelView.Dv;
using DuelView.Runtime;

/// <summary>Author inspection through the production parser. Never advances a world.</summary>
internal static class ScenarioAuthoring
{
    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, MaxDepth = 256
    };

    public static int Run(string[] args)
    {
        if (args.Length is < 3 or > 4)
            throw new ArgumentException("--story-authoring-view <project-content.dv> <.runtime/output.json> [project-overlay-directory]");
        var root = Path.GetFullPath(Environment.CurrentDirectory);
        var rootPrefix = root + Path.DirectorySeparatorChar;
        string ProjectPath(string value)
        {
            var path = Path.GetFullPath(value.StartsWith("res://", StringComparison.Ordinal) ? value[6..] : value, root);
            if (!path.StartsWith(rootPrefix, StringComparison.Ordinal))
                throw new InvalidDataException("Author inspection only reads this project's source files.");
            return path;
        }
        var entry = "res://" + Path.GetRelativePath(root, ProjectPath(args[1])).Replace('\\', '/');
        var output = ProjectPath(args[2]);
        if (!output.StartsWith(Path.Combine(root, ".runtime") + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new InvalidDataException("Generated author inspection belongs under .runtime.");
        var overlay = args.Length == 4 ? ProjectPath(args[3]) : null;
        if (overlay is not null && !Directory.Exists(overlay)) throw new DirectoryNotFoundException(overlay);
        var inputs = new SortedDictionary<string, object>(StringComparer.Ordinal);
        var texts = new Dictionary<string, string>(StringComparer.Ordinal);
        string Read(string resource)
        {
            if (texts.TryGetValue(resource, out var previous)) return previous;
            var path = ProjectPath(resource);
            if (overlay is not null)
            {
                var staged = Path.Combine(overlay, Path.GetRelativePath(root, path));
                if (File.Exists(staged)) path = staged;
            }
            var bytes = File.ReadAllBytes(path);
            var text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
            inputs[resource] = new
            {
                actual_path = Path.GetRelativePath(root, path).Replace('\\', '/'),
                bytes = bytes.Length, sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()
            };
            texts.Add(resource, text);
            return text;
        }
        var snapshot = CharacterContentRevisions.Capture(entry, Read);
        var content = snapshot.Definition.Declaration;
        var primary = content.TryGetProperty("deduction", out var deduction) && deduction.ValueKind == JsonValueKind.Object
            ? Read(deduction.GetProperty("source").GetString()!) : null;
        var session = snapshot.Definition.Create(primary);
        if (content.TryGetProperty("deductions", out var deductions))
            foreach (var item in deductions.EnumerateArray()) session.ConfigureDeduction(Read(item.GetProperty("source").GetString()!), item);
        if (content.TryGetProperty("strategy_activities", out var strategies))
            foreach (var item in strategies.EnumerateArray()) session.ConfigureStrategy(Read(item.GetProperty("source").GetString()!), item);
        var authorProofs = new List<object>();
        foreach (var actor in content.GetProperty("actors").EnumerateArray())
        foreach (var action in actor.GetProperty("actions").EnumerateArray())
        {
            if (!action.TryGetProperty("deduction", out var theoryData) || theoryData.ValueKind != JsonValueKind.Object) continue;
            var subject = actor.GetProperty("id").GetString()!;
            CaseLiteral Literal(string value) => new("case_fact", new[] { value.StartsWith("not:", StringComparison.Ordinal) ? value[4..] : value }, value.StartsWith("not:", StringComparison.Ordinal));
            object Atom(string value)
            {
                var literal = Literal(value); return new { predicate = literal.Predicate, args = literal.Args, negative = literal.Negative };
            }
            var goal = Literal(theoryData.GetProperty("conclusion").GetString()!);
            var theory = CaseTheory.FromData(JsonSerializer.SerializeToElement(new { scopes = new[] { new
            {
                id = subject, axioms = Array.Empty<object>(),
                rules = theoryData.GetProperty("rules").EnumerateArray().Select(rule => new
                {
                    id = rule.GetProperty("id").GetString(),
                    premises = rule.GetProperty("all").EnumerateArray().Select(item => Atom(item.GetString()!)).ToArray(),
                    conclusion = Atom(rule.GetProperty("then").GetString()!), source = rule.TryGetProperty("label", out var label) ? label.GetString() : rule.GetProperty("id").GetString()
                }).ToArray(),
                theorems = new[] { new { id = "author_goal", conclusion = Atom(theoryData.GetProperty("conclusion").GetString()!) } }
            } } }));
            // Hypothetical author premises are only proof-design checks. They never enter session memory.
            var hypotheses = theoryData.GetProperty("evidence").EnumerateArray().Select(item =>
                new CaseAxiom(item.GetProperty("id").GetString()!, Literal(item.GetProperty("id").GetString()!), "author-declared-premise")).ToArray();
            var all = theory.WithEvidence(subject, hypotheses);
            var result = all.Prove(subject, goal, 2048, 100000);
            var empty = theory.Prove(subject, goal, 2048, 100000);
            var checkedProof = result.Support is null ? null : all.CheckGoal(subject, result.Support.Certificate, goal);
            authorProofs.Add(new
            {
                action = action.GetProperty("id").GetString(),
                scope = "hypothetical_author_premises_only", all_premises_status = result.Status,
                empty_premises_status = empty.Status, checked_certificate = checkedProof,
                used_rules = result.Support?.Rules, used_premises = result.Support?.Axioms,
                removed_premises = hypotheses.Select(removed => new
                {
                    id = removed.Id, status = theory.WithEvidence(subject, hypotheses.Where(item => item.Id != removed.Id)).Prove(subject, goal, 2048, 100000).Status
                }).ToArray()
            });
        }
        // Parse presentation through the same DV parser, not a second shorthand reader.
        JsonElement presentation = default;
        if (content.TryGetProperty("presentation", out var presentationSpec) && presentationSpec.TryGetProperty("source", out var presentationSource))
            presentation = DvDocument.Parse(Read(presentationSource.GetString()!))
                .Definition("data", presentationSpec.GetProperty("definition").GetString()!).GetProperty("value").Clone();
        var document = new
        {
            schema = "story-authoring-view-v1", entry_path = entry,
            content_hash = snapshot.Definition.Hash, source_fingerprint = snapshot.Revision.Fingerprint,
            parser = "DuelView.Dv.DvDocument + DuelView.Runtime.CharacterSessionDefinition",
            initialization = "validated_without_stepping", gameplay_accepted = false,
            source_files = inputs, declaration = content,
            author_proofs = authorProofs,
            presentation = presentation.ValueKind == JsonValueKind.Undefined ? (object?)null : presentation
        };
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.WriteAllText(output, JsonSerializer.Serialize(document, Json) + "\n", new UTF8Encoding(false));
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            output = Path.GetRelativePath(root, output).Replace('\\', '/'),
            sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(output))).ToLowerInvariant(),
            document.content_hash, document.source_fingerprint, document.initialization, document.gameplay_accepted
        }, Json));
        return 0;
    }
}
