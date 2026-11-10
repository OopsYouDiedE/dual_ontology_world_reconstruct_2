using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Core;

public static partial class CaseHistory
{
    public sealed record CheckRequest(IReadOnlyList<string>? Events = null, IReadOnlyList<string>? Actors = null,
        int? From = null, int? Until = null, IReadOnlyList<string>? Goals = null);

    /// <summary>Extracts a dependency-closed theorem context from the declared initial state. Never injects a runtime checkpoint.</summary>
    public static JsonElement Project(JsonElement source, CheckRequest request)
    {
        source = Expand(source);
        var all = List(source, "actions").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        int Begin(JsonElement e) => e.GetProperty("start").GetInt32();
        int End(JsonElement e) => e.GetProperty("end").GetInt32();
        var selected = request.Events?.ToHashSet(StringComparer.Ordinal) ?? all.Where(x =>
            (request.Actors is null || request.Actors.Contains(Text(x.Value, "actor"))) &&
            (request.From is null || Begin(x.Value) >= request.From) && (request.Until is null || End(x.Value) <= request.Until))
            .Select(x => x.Key).ToHashSet(StringComparer.Ordinal);
        if (selected.Count == 0 || selected.Any(x => !all.ContainsKey(x))) throw new ArgumentException("Subhistory needs declared events");
        var roots = selected.Order(StringComparer.Ordinal).ToArray();
        var notifications = List(source, "information");
        static IEnumerable<string> ObjectIds(JsonElement e) => Strings(e, "uses").Concat(Strings(e, "takes"))
            .Concat(List(e, "gives").Select(x => Text(x, "object"))).Concat(List(e, "places").Select(x => Text(x, "object")));
        IEnumerable<string> Reservations(JsonElement e) => Strings(e, "resources").Concat(ObjectIds(e))
            .Append("@body:" + Text(e, "actor")).Concat(List(e, "gives").Select(x => "@body:" + Text(x, "to")));
        bool changed;
        do
        {
            changed = false;
            void Include(string id) { if (selected.Add(id)) changed = true; }
            var chosen = selected.Select(x => all[x]).ToArray();
            var horizon = chosen.Max(End);
            var involved = chosen.Select(x => Text(x, "actor")).ToHashSet(StringComparer.Ordinal);
            var facts = chosen.SelectMany(e => Strings(e, "requires").Concat(Strings(e, "requires_during"))
                .Concat(Strings(e, "requires_absent_during")).Concat(Strings(e, "adds")).Concat(Strings(e, "removes")))
                .Concat(request.Goals ?? []).ToHashSet(StringComparer.Ordinal);
            var objects = chosen.SelectMany(ObjectIds).ToHashSet(StringComparer.Ordinal);
            foreach (var e in chosen)
            {
                var actor = Text(e, "actor");
                foreach (var prior in all.Where(x => Text(x.Value, "actor") == actor && Begin(x.Value) < Begin(e))) Include(prior.Key);
                foreach (var companion in Strings(e, "companion_actions"))
                    if (all.ContainsKey(companion)) Include(companion);
                var propositions = Strings(e, "requires_propositions").Concat(List(e, "choices").SelectMany(c => Strings(c, "requires_propositions"))).ToHashSet(StringComparer.Ordinal);
                foreach (var info in notifications.Where(n => Text(n, "actor") == actor && n.GetProperty("at").GetInt32() <= Begin(e) &&
                    Strings(n, "propositions").Any(propositions.Contains)))
                    Include(Text(info, "source_action"));
                var resources = Reservations(e).ToHashSet(StringComparer.Ordinal);
                foreach (var other in all.Where(x => Begin(x.Value) < End(e) && Begin(e) < End(x.Value) && Reservations(x.Value).Any(resources.Contains))) Include(other.Key);
            }
            foreach (var e in all.Where(x => End(x.Value) <= horizon))
                if (Strings(e.Value, "adds").Concat(Strings(e.Value, "removes")).Any(facts.Contains) ||
                    ObjectIds(e.Value).Any(objects.Contains) || Strings(e.Value, "erase_actor_memories").Any(involved.Contains)) Include(e.Key);
        } while (changed);
        var kept = selected.Select(x => all[x]).OrderBy(Begin).ThenBy(x => Text(x, "id"), StringComparer.Ordinal).ToArray();
        var activeActors = kept.Select(x => Text(x, "actor")).ToHashSet(StringComparer.Ordinal);
        var end = kept.Max(End);
        var root = JsonNode.Parse(source.GetRawText())!.AsObject();
        root["actions"] = new JsonArray(kept.Select(x => JsonNode.Parse(x.GetRawText())).ToArray());
        root["information"] = new JsonArray(notifications.Where(x => activeActors.Contains(Text(x, "actor")) && selected.Contains(Text(x, "source_action")) &&
            x.GetProperty("at").GetInt32() <= end).Select(x => JsonNode.Parse(x.GetRawText())).ToArray());
        root["environment"] = new JsonArray(List(source, "environment").Where(x => x.GetProperty("at").GetInt32() <= end).Select(x => JsonNode.Parse(x.GetRawText())).ToArray());
        root["end"] = end;
        root["required_final_facts"] = new JsonArray((request.Goals ?? []).Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
        foreach (var actor in root["actors"]!.AsArray()) actor!.AsObject().Remove("final_location");
        root.Remove("branches");
        root["projection"] = new JsonObject { ["events"] = new JsonArray(roots.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray()),
            ["dependencies"] = new JsonArray(selected.Except(roots).Order(StringComparer.Ordinal).Select(x => (JsonNode?)JsonValue.Create(x)).ToArray()) };
        return JsonSerializer.SerializeToElement(root);
    }
}
