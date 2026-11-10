using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Dv;

/// <summary>Elaborates typed history declarations. Definitions are data; events cannot supply effects or scores.</summary>
public sealed class HistoryScriptReader
{
    private sealed record Token(string Text, int Line, int Column, bool Quoted = false);
    private readonly List<Token> tokens = [];
    private int at;
    private readonly JsonObject root = new()
    {
        ["version"] = "typed-history-v1", ["declaration_model"] = "typed-history-v1",
        ["idle"] = "retain_location", ["travel_model"] = "node_graph_seconds"
    };
    private readonly Dictionary<string, JsonObject> profiles = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> operations = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> policies = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> actors = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> edges = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> channels = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JsonObject> events = new(StringComparer.Ordinal);
    private readonly HashSet<string> nodes = new(StringComparer.Ordinal);
    private readonly HashSet<string> abilities = new(StringComparer.Ordinal);
    private readonly HashSet<string> objectTypes = new(StringComparer.Ordinal);
    private readonly List<JsonObject> objects = [], resources = [], environment = [], receives = [], routes = [];
    private readonly List<string> facts = [], finalFacts = [];

    private HistoryScriptReader(string source)
    {
        if (source.Length > 1_000_000) throw new FormatException("History source budget");
        int i = 0, line = 1, column = 1;
        while (i < source.Length)
        {
            if (char.IsWhiteSpace(source[i])) { if (source[i++] == '\n') { line++; column = 1; } else column++; continue; }
            var begin = i; var col = column;
            if (source[i] == '"')
            {
                i++;
                while (i < source.Length && source[i] != '"') { if (source[i++] == '\\' && i < source.Length) i++; }
                if (i == source.Length) throw new FormatException($"History {line}:{col}: unterminated string");
                i++; tokens.Add(new(JsonSerializer.Deserialize<string>(source[begin..i])!, line, col, true));
            }
            else if (i + 1 < source.Length && (source.AsSpan(i, 2).SequenceEqual(":=") || source.AsSpan(i, 2).SequenceEqual("->") || source.AsSpan(i, 2).SequenceEqual("..")))
            { i += 2; tokens.Add(new(source[begin..i], line, col)); }
            else if ("{}[]():;,=|".Contains(source[i])) { i++; tokens.Add(new(source[begin..i], line, col)); }
            else
            {
                while (i < source.Length && !char.IsWhiteSpace(source[i]) && !"{}[]():;,=|".Contains(source[i]) &&
                       !(i + 1 < source.Length && (source.AsSpan(i, 2).SequenceEqual("->") || source.AsSpan(i, 2).SequenceEqual("..")))) i++;
                if (begin == i) throw new FormatException($"History {line}:{col}: unexpected character");
                tokens.Add(new(source[begin..i], line, col));
            }
            column += i - begin;
            if (tokens.Count > 100000) throw new FormatException("History token budget");
        }
    }

    public static JsonElement Elaborate(string source, string name = "history")
    {
        var reader = new HistoryScriptReader(source);
        reader.root["id"] = name;
        reader.Read();
        return JsonSerializer.SerializeToElement(reader.root);
    }
    private Token Current => at < tokens.Count ? tokens[at] : new("<eof>", tokens.LastOrDefault()?.Line ?? 1, 1);
    private FormatException Error(string message) => new($"History {Current.Line}:{Current.Column}: {message}");
    private bool Take(string text) { if (Current.Text != text) return false; at++; return true; }
    private void Need(string text) { if (!Take(text)) throw Error("Expected " + text); }
    private string Name() { var t = Current; if (t.Text == "<eof>" || (!t.Quoted && "{}[]():;,=|".Contains(t.Text))) throw Error("Expected name"); at++; return t.Text; }
    private int Integer() => int.TryParse(Name(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : throw Error("Expected integer seconds");
    private JsonArray Names()
    {
        Need("["); var result = new JsonArray();
        while (!Take("]")) { result.Add(Name()); if (!Take(",") && Current.Text != "]") throw Error("Expected comma"); }
        return result;
    }
    private JsonNode Value(int depth = 0)
    {
        if (depth > 48) throw Error("Definition nesting budget");
        if (Take("{"))
        {
            var result = new JsonObject();
            while (!Take("}"))
            {
                var key = Name(); Need(":=");
                if (result.ContainsKey(key)) throw Error("Duplicate field " + key);
                result[key] = Value(depth + 1); if (!Take(",")) Take(";");
            }
            return result;
        }
        if (Take("["))
        {
            var result = new JsonArray();
            while (!Take("]")) { result.Add(Value(depth + 1)); if (!Take(",") && Current.Text != "]") throw Error("Expected comma"); }
            return result;
        }
        var token = Current; var text = Name();
        if (!token.Quoted && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var number))
        {
            if (!double.IsFinite(number)) throw Error("Non-finite number");
            return JsonValue.Create(number)!;
        }
        return !token.Quoted && text is "true" or "false" ? JsonValue.Create(text == "true")! : JsonValue.Create(text)!;
    }
    private JsonArray? Point()
    {
        if (!Take("(")) return null;
        var p = new JsonArray();
        do
        {
            var text = Name();
            if (!decimal.TryParse(text, NumberStyles.Number, CultureInfo.InvariantCulture, out var metres) || metres * 10 != decimal.Truncate(metres * 10))
                throw Error("Room position must use at most one decimal place");
            p.Add(decimal.ToInt32(metres * 10));
        } while (Take(","));
        Need(")"); if (p.Count != 3) throw Error("Room position requires three coordinates");
        return p;
    }
    private static string Text(JsonObject value, string key) => value[key]?.GetValue<string>() ?? throw new FormatException("Missing " + key);
    private static JsonArray Array(JsonObject value, string key) => value[key] as JsonArray ?? new JsonArray();
    private static JsonObject Merge(JsonObject defaults, JsonObject value)
    {
        var result = (JsonObject)defaults.DeepClone();
        foreach (var pair in value)
            result[pair.Key] = result[pair.Key] is JsonObject prior && pair.Value is JsonObject child ? Merge(prior, child) : pair.Value?.DeepClone();
        return result;
    }
    public static JsonNode Bind(JsonNode value, string actor, string goal)
    {
        string Replace(string text) => text.Replace("$actor", actor, StringComparison.Ordinal).Replace("$goal", goal, StringComparison.Ordinal);
        if (value is JsonObject obj)
        { var result = new JsonObject(); foreach (var pair in obj) result.Add(Replace(pair.Key), pair.Value is null ? null : Bind(pair.Value, actor, goal)); return result; }
        if (value is JsonArray list) return new JsonArray(list.Select(x => x is null ? null : Bind(x, actor, goal)).ToArray());
        return value is JsonValue scalar && scalar.TryGetValue<string>(out var text) ? JsonValue.Create(Replace(text))! : value.DeepClone();
    }
    private void Read()
    {
        while (at < tokens.Count)
        {
            var command = Name();
            switch (command)
            {
                case "clock": root["clock"] = new JsonObject { ["origin"] = Name(), ["unit"] = "second" }; root["start"] = Integer(); root["end"] = Integer(); break;
                case "node": ReadNames(nodes); break;
                case "capability": ReadNames(abilities); break;
                case "type": ReadNames(objectTypes); break;
                case "initial": foreach (var v in Names()) facts.Add(v!.GetValue<string>()); break;
                case "final": foreach (var v in Names()) finalFacts.Add(v!.GetValue<string>()); break;
                case "def": ReadDefinition(); break;
                case "actor": ReadActor(); break;
                case "edge": ReadEdge(); break;
                case "channel": ReadChannel(); break;
                case "resource": ReadResource(); break;
                case "object": ReadObject(); break;
                case "world":
                { var id = Name(); Need("at"); var time = Integer(); var value = Value().AsObject(); value["id"] = id; value["at"] = time; environment.Add(value); break; }
                case "move": ReadMove(); break;
                case "work": ReadWork(); break;
                case "receive": ReadReceive(); break;
                case "branch":
                {
                    var id = Name(); var definition = Value().AsObject(); definition["id"] = id;
                    if (definition.Any(x => x.Key is not ("id" or "events" or "goals"))) throw Error("Unknown branch field");
                    root["branches"] ??= new JsonArray(); root["branches"]!.AsArray().Add(definition); break;
                }
                default: throw Error("Unknown history declaration " + command);
            }
            Need(";");
        }
        Finish();
    }
    private void ReadNames(HashSet<string> set)
    { do { var name = Name(); if (!set.Add(name)) throw Error("Duplicate declaration " + name); } while (Take(",")); }
    private void ReadDefinition()
    {
        var id = Name(); Need(":"); var type = Name(); Need(":="); var value = Value().AsObject();
        var declarations = type switch { "Profile" => profiles, "Policy" => policies, "Operation" => operations, _ => throw Error("Unknown definition type " + type) };
        value["id"] = id;
        if (type == "Operation") value["minimum_seconds"] ??= 1;
        if (!declarations.TryAdd(id, value)) throw Error("Duplicate definition " + id);
    }
    private void ReadActor()
    {
        var id = Name(); var name = Current.Quoted ? Name() : id; Need(":"); var profile = Name(); Need("at"); var location = Name(); var point = Point();
        Need("goal"); var goal = Name(); var patch = Current.Text == "{" ? Value().AsObject() : new JsonObject();
        if (!profiles.TryGetValue(profile, out var defaults)) throw Error("Unknown profile " + profile);
        var value = Merge(defaults, patch); value["id"] = id; value["name"] = name; value["location"] = location; value["priority"] = goal;
        if (point is not null) value["point"] = point;
        var goalProfile = value["goal"] as JsonObject ?? throw Error("Profile requires goal parameters");
        value["needs"]![goal] = goalProfile["need"]!.DeepClone(); value["weights"]![goal] = goalProfile["weight"]!.DeepClone();
        value["need_decay_per_second"]![goal] = goalProfile["decay"]!.DeepClone(); value.Remove("goal");
        value = Bind(value, id, goal).AsObject();
        if (!actors.TryAdd(id, value)) throw Error("Duplicate actor " + id);
    }
    private void ReadEdge()
    {
        var id = Name(); Need(":"); var from = Name(); Need("->"); var to = Name(); Need(":="); var seconds = Integer();
        var value = Current.Text == "{" ? Value().AsObject() : new JsonObject();
        value["id"] = id; value["from"] = from; value["to"] = to; value["minimum_seconds"] = seconds;
        if (!edges.TryAdd(id, value)) throw Error("Duplicate edge " + id);
    }
    private void ReadChannel()
    {
        var id = Name(); Need(":"); var from = Name(); Need("->"); var to = Name();
        var value = Current.Text == "{" ? Value().AsObject() : new JsonObject();
        value["id"] = id; value["from"] = from; value["to"] = to; value["minimum_delay"] ??= 0;
        if (!channels.TryAdd(id, value)) throw Error("Duplicate channel " + id);
    }
    private void ReadResource()
    {
        var id = Name(); var value = new JsonObject { ["id"] = id, ["capacity"] = 1 };
        if (Take("at")) value["location"] = Name();
        resources.Add(value);
    }
    private void ReadObject()
    {
        var id = Name(); Need(":"); var type = Name();
        if (!objectTypes.Contains(type)) throw Error("Unknown object type " + type);
        var value = new JsonObject { ["id"] = id, ["type"] = type };
        if (Take("held")) value["holder"] = Name();
        else { Need("at"); value["location"] = Name(); if (Point() is { } point) value["point"] = point; }
        objects.Add(value);
    }
    private (string Id, string Actor, int Start, int End) EventHeader()
    { var id = Name(); var actor = Name(); var start = Integer(); Need(".."); var end = Integer(); return (id, actor, start, end); }
    private JsonObject Instantiate(string operation, string actor)
    {
        if (!operations.TryGetValue(operation, out var definition)) throw Error("Unknown operation " + operation);
        if (!actors.TryGetValue(actor, out var profile)) throw Error("Unknown actor " + actor);
        var result = Bind(definition, actor, Text(profile, "priority")).AsObject(); result.Remove("id");
        result["operation_id"] = operation; result["actor"] = actor;
        result["minimum_seconds"] ??= 1; result["selected"] = "do";
        return result;
    }
    private void ReadMove()
    {
        var e = EventHeader(); Need("using"); var operation = Name();
        var result = Instantiate(operation, e.Actor);
        if (Take("within"))
        {
            var location = Name(); Need("from"); var from = Point() ?? throw Error("Expected room start position");
            Need("to"); var to = Point() ?? throw Error("Expected room end position");
            if (Text(result, "kind") != "move") throw Error("Room movement requires movement constructor");
            var speed = actors[e.Actor]["maximum_speed"]!.GetValue<double>();
            if (!double.IsFinite(speed) || speed <= 0) throw Error("Invalid movement speed");
            var distance = Math.Sqrt(from.Zip(to, (a, b) => Math.Pow(a!.GetValue<int>() - b!.GetValue<int>(), 2)).Sum()) / 10;
            var edgeId = e.Id + ".room";
            var edge = new JsonObject { ["id"] = edgeId, ["from"] = location, ["to"] = location, ["minimum_seconds"] = Math.Max(1, (int)Math.Ceiling(distance / speed)) };
            if (!edges.TryAdd(edgeId, edge)) throw Error("Duplicate room edge");
            var roomRoute = (JsonObject)edge.DeepClone(); roomRoute["id"] = e.Id + ".path"; roomRoute["edge_ids"] = new JsonArray(edgeId); routes.Add(roomRoute);
            result["from"] = location; result["to"] = location; result["from_point"] = from; result["to_point"] = to; result["route"] = Text(roomRoute, "id");
            AddEvent(e, result); return;
        }
        Need("via"); var path = Names();
        if (Text(result, "kind") != "move" || path.Count == 0) throw Error("move requires a movement constructor and nonempty edge chain");
        var selected = path.Select(x => edges.TryGetValue(x!.GetValue<string>(), out var edge) ? edge : throw Error("Unknown edge")).ToArray();
        for (var i = 1; i < selected.Length; i++) if (Text(selected[i - 1], "to") != Text(selected[i], "from")) throw Error("Disconnected edge chain");
        var route = new JsonObject
        {
            ["id"] = e.Id + ".path", ["from"] = Text(selected[0], "from"), ["to"] = Text(selected[^1], "to"),
            ["edge_ids"] = path.DeepClone(), ["minimum_seconds"] = selected.Sum(x => x["minimum_seconds"]!.GetValue<int>())
        };
        foreach (var field in new[] { "requires", "requires_absent" })
            route[field] = new JsonArray(selected.SelectMany(x => Array(x, field)).Select(x => x!.GetValue<string>()).Distinct().Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
        foreach (var field in new[] { "capability", "access_bypass_capability" })
        {
            var values = selected.Where(x => x[field] is not null).Select(x => Text(x, field)).Distinct().ToArray();
            if (values.Length > 1) throw Error("Mixed movement modes"); if (values.Length == 1) route[field] = values[0];
        }
        routes.Add(route); result["from"] = route["from"]!.DeepClone(); result["to"] = route["to"]!.DeepClone(); result["route"] = route["id"]!.DeepClone();
        if (Take("to")) result["to_point"] = Point() ?? throw Error("Expected room position");
        if (Take("with")) result["companion_actions"] = Names();
        AddEvent(e, result);
    }
    private void ReadWork()
    {
        var e = EventHeader(); Need("using"); var result = Instantiate(Name(), e.Actor); Need("at"); var location = Name();
        if (Text(result, "kind") == "move") throw Error("work cannot use a movement constructor");
        result["from"] = location; result["to"] = location;
        if (Point() is { } point) { result["from_point"] = point.DeepClone(); result["to_point"] = point; }
        if (Take("with")) result["companion_actions"] = Names();
        AddEvent(e, result);
    }
    private void AddEvent((string Id, string Actor, int Start, int End) e, JsonObject result)
    {
        result["id"] = e.Id; result["start"] = e.Start; result["end"] = e.End;
        result["choices"] = Choices(result, actors[e.Actor]);
        if (!events.TryAdd(e.Id, result)) throw Error("Duplicate event " + e.Id);
    }
    private JsonArray Choices(JsonObject action, JsonObject actor)
    {
        if (!policies.TryGetValue(Text(actor, "policy_id"), out var policy)) throw Error("Unknown actor policy");
        var intent = Text(action, "intent");
        var prediction = Bind(policy["predictions"]?[intent] ?? throw Error("No policy prediction for " + intent), Text(actor, "id"), Text(actor, "priority")).AsObject();
        var effects = Bind(prediction["effect"]!, Text(actor, "id"), Text(actor, "priority"));
        JsonObject Choice(string id, JsonNode effect, JsonArray requirements) => new()
        {
            ["id"] = id, ["perceived_need_effects"] = effect.DeepClone(), ["requires_propositions"] = requirements.DeepClone(),
            ["seconds"] = action["end"]!.GetValue<int>() - action["start"]!.GetValue<int>()
        };
        var requires = new JsonArray(Array(action, "requires_propositions").Concat(Array(prediction, "requires_propositions")).Select(x => x!.DeepClone()).ToArray());
        var result = new JsonArray { Choice("do", effects, requires) };
        foreach (var raw in Array(policy, "alternatives").OfType<JsonObject>())
        {
            var alternative = Bind(raw, Text(actor, "id"), Text(actor, "priority")).AsObject();
            var intents = Array(alternative, "intents");
            if (alternative.ContainsKey("intents") && !intents.Any(x => x!.GetValue<string>() == intent)) continue;
            result.Add(Choice(Text(alternative, "id"), Bind(alternative["effect"]!, Text(actor, "id"), Text(actor, "priority")), Array(alternative, "requires_propositions")));
        }
        return result;
    }
    private void ReadReceive()
    {
        var id = Name(); var actor = Name(); Need("at"); var time = Integer(); Need("from"); var source = Name(); Need("via"); var channel = Name();
        receives.Add(new JsonObject { ["id"] = id, ["actor"] = actor, ["at"] = time, ["source_action"] = source, ["channel"] = channel });
    }
    private void Finish()
    {
        var allowed = new HashSet<string>(["id", "kind", "capability", "minimum_seconds", "intent", "resources", "uses", "requires", "requires_during", "requires_absent_during", "requires_propositions", "adds", "removes", "actual_need_effects", "emits", "takes", "gives", "places", "erase_actor_memories"], StringComparer.Ordinal);
        foreach (var operation in operations.Values)
        {
            if (operation.Any(field => !allowed.Contains(field.Key))) throw Error("Unknown operation field");
            if (Text(operation, "kind") is not ("move" or "work" or "observe" or "presence" or "think" or "speak")) throw Error("Unknown event constructor");
            if (!abilities.Contains(Text(operation, "capability"))) throw Error("Unknown operation capability");
            _ = Text(operation, "intent");
        }
        foreach (var list in new[] { resources, objects, environment, receives })
            if (list.Select(x => Text(x, "id")).Distinct(StringComparer.Ordinal).Count() != list.Count) throw Error("Duplicate identity");
        var eventIds = events.Keys.Concat(environment.Select(x => Text(x, "id"))).Concat(receives.Select(x => Text(x, "id"))).ToArray();
        if (eventIds.Distinct(StringComparer.Ordinal).Count() != eventIds.Length) throw Error("Repeated event identity");
        foreach (var actor in actors.Values)
        {
            if (!nodes.Contains(Text(actor, "location"))) throw Error("Actor references unknown node");
            foreach (var capability in Array(actor, "capabilities")) if (!abilities.Contains(capability!.GetValue<string>())) throw Error("Unknown ability");
        }
        foreach (var edge in edges.Values)
            if (!nodes.Contains(Text(edge, "from")) || !nodes.Contains(Text(edge, "to"))) throw Error("Edge references unknown node");
        foreach (var n in receives)
        {
            if (!actors.ContainsKey(Text(n, "actor")) || !events.TryGetValue(Text(n, "source_action"), out var source) || !channels.TryGetValue(Text(n, "channel"), out var channel))
                throw Error("Receive references undeclared actor, source or channel");
            if (source["emits"] is not JsonArray emitted || emitted.Count == 0) throw Error("Source operation emits no information");
            var payload = channel["transform"] as JsonArray ?? emitted;
            n["propositions"] = payload.DeepClone(); n["at_location"] = channel["to"]!.DeepClone();
        }
        static JsonArray Values(IEnumerable<JsonObject> values) => new(values.Select(x => (JsonNode?)x.DeepClone()).ToArray());
        root["nodes"] = Values(nodes.Select(id => new JsonObject { ["id"] = id }));
        root["actors"] = Values(actors.Values); root["edges"] = Values(edges.Values); root["routes"] = Values(routes); root["resources"] = Values(resources);
        root["channels"] = Values(channels.Values); root["objects"] = Values(objects); root["environment"] = Values(environment);
        root["operations"] = Values(operations.Values); root["policies"] = Values(policies.Values);
        root["actions"] = Values(events.Values); root["information"] = Values(receives);
        root["initial_facts"] = new JsonArray(facts.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
        root["required_final_facts"] = new JsonArray(finalFacts.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());
    }
}
