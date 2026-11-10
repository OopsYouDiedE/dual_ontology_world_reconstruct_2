using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>Maps only explicitly declared physical identities into one owner's local
/// vocabulary. An unbound reference cannot enter that owner's evidence.</summary>
public sealed class PerceptionBindings
{
    private readonly Dictionary<(string Actor, string Physical), string> local = [];
    private static readonly JsonNode Unmapped = new JsonObject();

    public PerceptionBindings(JsonElement bindings)
    {
        foreach (var binding in bindings.Items())
        {
            var actor = binding.Get("subject").Text();
            var physical = binding.Get("physical").Text();
            var target = binding.Get("local").Text();
            if (actor.Length == 0 || physical.Length == 0 || target.Length == 0 ||
                local.TryGetValue((actor, physical), out var existing) && existing != target)
                throw new InvalidDataException("Ambiguous or invalid perception binding.");
            local[(actor, physical)] = target;
        }
    }

    public FieldKey? Project(string actor, FieldKey physical) => local.TryGetValue((actor, physical.Object), out var target)
        ? physical with { Object = target } : null;

    public JsonElement? Project(string actor, JsonElement value)
    {
        var projected = Visit(actor, value, 0);
        return ReferenceEquals(projected, Unmapped) ? null : JsonSerializer.SerializeToElement(projected);
    }

    private JsonNode? Visit(string actor, JsonElement value, int depth)
    {
        if (depth > ValueTemplates.MaximumDepth) throw new InvalidDataException("Perception value depth exceeded.");
        if (value.ValueKind == JsonValueKind.Object)
        {
            if (value.Get("type").Text() == "ref")
            {
                var scope = value.Get("subject").Text();
                if (scope.Length > 0 && scope != actor) return Unmapped;
                var key = Project(actor, FieldKey.Read(value, actor));
                if (key is null) return Unmapped;
                return new JsonObject { ["type"] = "ref", ["subject"] = actor,
                    ["object"] = key.Value.Object, ["facet"] = key.Value.Facet, ["field"] = key.Value.Field };
            }
            var result = new JsonObject();
            foreach (var item in value.EnumerateObject())
            {
                var child = Visit(actor, item.Value, depth + 1);
                if (ReferenceEquals(child, Unmapped)) return Unmapped;
                result.Add(item.Name, child);
            }
            return result;
        }
        if (value.ValueKind == JsonValueKind.Array)
        {
            var result = new JsonArray();
            foreach (var item in value.EnumerateArray())
            {
                var child = Visit(actor, item, depth + 1);
                if (ReferenceEquals(child, Unmapped)) return Unmapped;
                result.Add(child);
            }
            return result;
        }
        if (value.ValueKind == JsonValueKind.Undefined) return Unmapped;
        if (value.ValueKind == JsonValueKind.Null) return null;
        return JsonNode.Parse(value.GetRawText());
    }
}
