using System.Text;
using System.Text.Json;
using DuelView.Dv;

namespace DuelView.Runtime;

/// <summary>
/// Authored input for the replacement runtime. It preserves both chapters' declarations
/// without constructing DvSession, executing campaign installers, or restoring saved state.
/// This is content loading only; template lowering and gameplay execution are separate work.
/// </summary>
public sealed class RuntimeContent
{
    public DvDocument Document { get; }
    public JsonElement Manifest { get; }
    public string Hash => Document.Hash;
    public IReadOnlyDictionary<string, DvDocument> Histories { get; private set; } = new Dictionary<string, DvDocument>();

    private RuntimeContent(DvDocument document, string manifestIdentity)
    {
        Document = document;
        Manifest = document.Definition("data", manifestIdentity).GetProperty("value");
        if (!Manifest.GetProperty("version").TryGetInt32(out var version) || version != 1)
            throw new InvalidDataException("Unsupported campaign pack version.");
        var declared = new HashSet<string>(StringComparer.Ordinal);
        foreach (var definition in Manifest.GetProperty("definitions").EnumerateArray())
        {
            var id = definition.GetString();
            if (string.IsNullOrWhiteSpace(id) || !declared.Add(id))
                throw new InvalidDataException("Invalid or duplicate campaign definition.");
            _ = Data(id);
        }
        if (declared.Count == 0 || declared.Count == 1 && declared.Contains(manifestIdentity))
            throw new InvalidDataException("Campaign pack contains no content definitions.");
        foreach (var entry in document.Root.GetProperty("data").EnumerateObject())
            if (entry.Name != manifestIdentity && !declared.Contains(entry.Name))
                throw new InvalidDataException("Campaign data is absent from its manifest: " + entry.Name);
        _ = Data(Manifest.GetProperty("spatial_definition").GetString()
            ?? throw new InvalidDataException("Missing spatial definition identity."));
    }

    public static RuntimeContent Parse(IEnumerable<string> sources, string manifestIdentity) =>
        new(DvDocument.ParseBundle(sources), manifestIdentity);

    public static RuntimeContent LoadPublished(string directory, string manifestIdentity)
    {
        var root = Path.GetFullPath(directory);
        var manifestPath = Path.Combine(root, "00-pack.data.dv");
        var manifestSource = File.ReadAllText(manifestPath, Encoding.UTF8);
        var manifest = DvDocument.Parse(manifestSource).Definition("data", manifestIdentity).GetProperty("value");
        string Source(string relative)
        {
            if (string.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative)) throw new InvalidDataException("Content source must be relative to its pack.");
            var path = Path.GetFullPath(Path.Combine(root, relative));
            if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Content source leaves its pack.");
            return File.ReadAllText(path, Encoding.UTF8);
        }
        var sources = manifest.GetProperty("sources").EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
        if (sources.Length == 0 || sources.Distinct(StringComparer.OrdinalIgnoreCase).Count() != sources.Length)
            throw new InvalidDataException("Pack needs unique explicit source paths.");
        var result = Parse(new[] { manifestSource }.Concat(sources.Select(Source)), manifestIdentity);
        var histories = new Dictionary<string, DvDocument>(StringComparer.Ordinal);
        foreach (var path in manifest.Get("history_sources").Items())
            histories.Add(path.Text(), DvDocument.Parse(Source(path.Text())));
        result.Histories = new System.Collections.ObjectModel.ReadOnlyDictionary<string, DvDocument>(histories);
        return result;
    }

    public JsonElement Data(string identity) => Document.Definition("data", identity).GetProperty("value");
}
