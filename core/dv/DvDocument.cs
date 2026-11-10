using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DuelView.Dv;

/// <summary>A declaration document. Parsing never creates a session or advances a world.</summary>
public sealed class DvDocument
{
    public const string Schema = "dv-script-v1";
    public JsonElement Root { get; }
    public string Source { get; }
    public string Hash { get; }

    private DvDocument(JsonElement root)
    {
        Root = root;
        var source = new StringBuilder("schema ").Append(JsonSerializer.Serialize(Schema)).AppendLine(";");
        foreach (var category in root.EnumerateObject())
        {
            if (category.Name == "schema") continue;
            var keyword = category.Name switch
            {
                "data" => "data", "items" => "item", "rules" => "rule", "characters" => "character",
                "layouts" => "layout", "narratives" => "narrative", "profiles" => "profile",
                _ => throw new InvalidDataException("Unsupported content category: " + category.Name)
            };
            foreach (var declaration in category.Value.EnumerateObject())
                source.Append(keyword).Append(' ').Append(JsonSerializer.Serialize(declaration.Name)).Append(' ')
                    .Append(declaration.Value.GetRawText()).AppendLine(";");
        }
        Source = source.ToString();
        Hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Source))).ToLowerInvariant();
    }

    public static DvDocument Parse(string source) => ParseBundle([source]);

    public static DvDocument ParseBundle(IEnumerable<string> sources)
    {
        ArgumentNullException.ThrowIfNull(sources);
        var categories = new Dictionary<string, Dictionary<string, JsonElement>>(StringComparer.Ordinal);
        var count = 0;
        foreach (var source in sources)
        {
            var root = DvScriptReader.Parse(source);
            if (root.GetProperty("schema").GetString() != Schema)
                throw new InvalidDataException("Unsupported content schema");
            count++;
            foreach (var category in root.EnumerateObject())
            {
                if (category.Name == "schema") continue;
                if (!categories.TryGetValue(category.Name, out var declarations))
                    categories.Add(category.Name, declarations = new(StringComparer.Ordinal));
                foreach (var declaration in category.Value.EnumerateObject())
                    if (!declarations.TryAdd(declaration.Name, declaration.Value.Clone()))
                        throw new InvalidDataException("Duplicate content identity: " + category.Name + "/" + declaration.Name);
            }
        }
        if (count == 0) throw new InvalidDataException("A DV document needs at least one source.");
        var combined = new Dictionary<string, object>(StringComparer.Ordinal) { ["schema"] = Schema };
        foreach (var category in categories) combined.Add(category.Key, category.Value);
        return new DvDocument(JsonSerializer.SerializeToElement(combined,new JsonSerializerOptions { MaxDepth=256 }));
    }

    public JsonElement Definition(string category, string identity)
    {
        if (!Root.TryGetProperty(category, out var definitions) || !definitions.TryGetProperty(identity, out var value))
            throw new InvalidDataException("Missing content definition: " + category + "/" + identity);
        return value;
    }
}
