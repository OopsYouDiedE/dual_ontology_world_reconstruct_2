using System.Text.Json;
using System.Text.Json.Nodes;
using DuelView.Dv;

namespace DuelView.Runtime;

internal sealed record SharedFragment(JsonObject Declaration,int[] Days);

/// <summary>Composes reusable authored declarations before compact expansion.
/// Local scenario values win; content still owns all facts, motives and actions.</summary>
internal static class SharedScenario
{
    private static readonly string[] Maps = ["actor_defaults", "facts", "fact_labels", "room_labels", "templates"];
    private static readonly string[] Collections = ["fixtures", "slots", "presence_groups", "objective_accumulators", "world_processes", "deductions", "strategy_activities"];
    private static JsonNode? Copy(JsonNode? value) => value?.DeepClone();
    private static JsonObject Map(JsonNode? value) => value as JsonObject ?? new();
    private static JsonArray List(JsonNode? value) => value as JsonArray ?? [];
    private static string Text(JsonNode? value) => value?.GetValue<string>() ?? "";

    internal static SharedFragment[] Read(JsonElement manifest, Func<string, string> read)
    {
        var references = manifest.Get("shared_sources");
        if (references.ValueKind == JsonValueKind.Undefined) return [];
        if (references.ValueKind != JsonValueKind.Array || references.GetArrayLength() > 32)
            throw new InvalidDataException("Shared sources must be a bounded list of DV declarations.");
        var paths = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<SharedFragment>();
        foreach (var reference in references.EnumerateArray())
        {
            var path = reference.Get("source").Text();
            if (path.Length == 0 || !paths.Add(path)) throw new InvalidDataException("Missing or duplicate shared DV source: " + path);
            var days=reference.Get("days");
            if(days.ValueKind!=JsonValueKind.Undefined&&(days.ValueKind!=JsonValueKind.Array||days.GetArrayLength() is <1 or >32||
                days.EnumerateArray().Any(day=>day.ValueKind!=JsonValueKind.Number||!day.TryGetInt32(out var number)||number is <1 or >32)))
                throw new InvalidDataException("Shared source days must be distinct positive campaign day numbers: "+path);
            var selectedDays=days.Items().Select(day=>day.GetInt32()).ToArray();
            if(selectedDays.Distinct().Count()!=selectedDays.Length)throw new InvalidDataException("Duplicate shared source day: "+path);
            var data = DvDocument.Parse(read(path)).Definition("data", "runtime.character_session").GetProperty("value");
            if (!data.Get("compact").Flag() || data.Get("campaign").ValueKind != JsonValueKind.Undefined || data.Get("shared_sources").ValueKind != JsonValueKind.Undefined)
                throw new InvalidDataException("Shared source must be a nonrecursive compact declaration: " + path);
            foreach (var field in data.EnumerateObject())
                if (field.Name != "compact" && field.Name != "actors" && !Maps.Contains(field.Name) && !Collections.Contains(field.Name))
                    throw new InvalidDataException("Unsupported shared declaration field: " + field.Name);
            result.Add(new(JsonNode.Parse(data.GetRawText())!.AsObject(),selectedDays));
        }
        return result.ToArray();
    }

    private static void Missing(JsonObject target, JsonObject source)
    {
        foreach (var field in source)
        {
            if (!target.ContainsKey(field.Key)) target[field.Key] = Copy(field.Value);
            else if (target[field.Key] is JsonObject existing && field.Value is JsonObject fallback) Missing(existing, fallback);
        }
    }

    private static void Append(JsonObject target, string field, JsonNode? source, bool deduplicate = false)
    {
        if (source is null) return;
        if (source is not JsonArray values) throw new InvalidDataException("Shared declaration requires an array: " + field);
        target[field] ??= new JsonArray();
        var destination = target[field] as JsonArray ?? throw new InvalidDataException("Scenario declaration requires an array: " + field);
        foreach (var value in values)
            if (!deduplicate || !destination.Any(prior => JsonNode.DeepEquals(prior, value))) destination.Add(Copy(value));
    }

    private static void AppendNamed(JsonObject target, string field, JsonNode? source)
    {
        if (source is null) return;
        if (source is not JsonArray values) throw new InvalidDataException("Shared declaration requires an array: " + field);
        target[field] ??= new JsonArray();
        var destination = target[field] as JsonArray ?? throw new InvalidDataException("Scenario declaration requires an array: " + field);
        foreach (var value in values)
        {
            var id = Text(value?["id"] ?? value?["law"] ?? value?["action"]);
            var prior = id.Length == 0 ? null : destination.FirstOrDefault(item => Text(item?["id"] ?? item?["law"] ?? item?["action"]) == id);
            if (prior is null) destination.Add(Copy(value));
            else if (prior is JsonObject local && value is JsonObject fallback) Missing(local, fallback);
        }
    }

    internal static JsonElement Apply(JsonElement scenario, IReadOnlyList<SharedFragment> shared,int day=1)
    {
        if (shared.Count == 0) return scenario;
        if (!scenario.Get("compact").Flag()) throw new InvalidDataException("Shared sources require compact scenario declarations.");
        var result = JsonNode.Parse(scenario.GetRawText())!.AsObject();
        foreach (var source in shared.Where(fragment=>fragment.Days.Length==0||fragment.Days.Contains(day)))
        {
            var fragment=source.Declaration;
            foreach (var field in Maps)
            {
                if (fragment[field] is null) continue;
                if (fragment[field] is not JsonObject fallback) throw new InvalidDataException("Shared declaration requires an object: " + field);
                result[field] ??= new JsonObject();
                Missing(result[field]!.AsObject(), fallback);
            }
            foreach (var field in Collections) AppendNamed(result, field, fragment[field]);
            var used = new HashSet<string>(StringComparer.Ordinal);
            foreach (var actor in List(fragment["actors"]))
            {
                var id = Text(actor?["id"]);
                if (id.Length == 0 || !used.Add(id)) throw new InvalidDataException("Missing or duplicate shared actor identity.");
                var local = List(result["actors"]).SingleOrDefault(item => Text(item?["id"]) == id) as JsonObject
                    ?? throw new InvalidDataException("Shared declarations reference an actor absent from the scenario: " + id);
                var fallback = actor!.AsObject();
                foreach (var field in new[] { "actions", "perceptions", "rules" }) Append(local, field, fallback[field]);
                var modifiers = fallback["opinion"]?["modifiers"];
                if (modifiers is not null)
                {
                    local["opinion"] ??= new JsonObject();
                    Append(local["opinion"]!.AsObject(), "modifiers", modifiers, true);
                }
                if(fallback["goal_planning"] is JsonObject planning)
                {
                    local["goal_planning"]??=new JsonObject();
                    AppendNamed(local["goal_planning"]!.AsObject(),"goals",planning["goals"]);
                }
                var remaining = fallback.DeepClone().AsObject();
                foreach (var field in new[] { "actions", "perceptions", "rules" }) remaining.Remove(field);
                Missing(local, remaining);
            }
        }
        return JsonSerializer.SerializeToElement(result);
    }
}
