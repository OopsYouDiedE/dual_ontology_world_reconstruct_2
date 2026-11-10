using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Core;

/// <summary>Checks an authored timed history, not host execution. Content, abilities, routes and subjective predictions remain DV.</summary>
public static partial class CaseHistory
{
    public sealed record Issue(string Event, string Kind, string Detail);
    public sealed record Decision(string Event, string Actor, double SelectedScore, IReadOnlyDictionary<string, double> Scores,
        IReadOnlyDictionary<string, double> Needs, IReadOnlyList<string> InformationUsed, IReadOnlyDictionary<string, double> PerceivedNeedEffects)
    {
        public bool Valid { get; init; }
        public Sim4Planner.Plan? Forecast { get; init; }
    }
    public sealed record Report(bool Valid, int Actors, int Events, IReadOnlyList<Issue> Issues, IReadOnlyList<Decision> Decisions)
    {
        public string DecisionModel { get; init; } = "legacy-authored-choices";
        public string DecisionScope { get; init; } = "authored-candidate-list";
        public int PointVerifiedEvents { get; init; }
        public int PointUnspecifiedEvents { get; init; }
        public IReadOnlyList<string> FinalFacts { get; init; } = [];
        public IReadOnlyList<string> ActiveActors { get; init; } = [];
        public string Scope { get; init; } = "complete-history";
    }
    public sealed record AuditItem(string Id, string Expected, string Actual, bool Passed);
    private static string Text(JsonElement e, string key) => e.GetProperty(key).GetString() is { Length: > 0 } s ? s : throw new FormatException("Missing " + key);
    private static JsonElement[] List(JsonElement e, string key) => e.TryGetProperty(key, out var v) ? v.EnumerateArray().ToArray() : [];
    private static string[] Strings(JsonElement e, string key) => List(e, key).Select(x => x.GetString() ?? throw new FormatException(key)).ToArray();
    private static Dictionary<string, double> Numbers(JsonElement e) => e.EnumerateObject().ToDictionary(x => x.Name, x => x.Value.GetDouble(), StringComparer.Ordinal);
    private static JsonNode? Bind(JsonNode? value, string actor, string goal)
    {
        string Substitute(string text) => text.Replace("$actor", actor, StringComparison.Ordinal).Replace("$goal", goal, StringComparison.Ordinal);
        if (value is JsonObject record)
        {
            var result = new JsonObject();
            foreach (var property in record) result.Add(Substitute(property.Key), Bind(property.Value, actor, goal));
            return result;
        }
        if (value is JsonArray array) return new JsonArray(array.Select(x => Bind(x, actor, goal)).ToArray());
        if (value is JsonValue scalar && scalar.TryGetValue<string>(out var text)) return JsonValue.Create(Substitute(text));
        return value?.DeepClone();
    }

    private static JsonElement Expand(JsonElement source)
    {
        var root = JsonNode.Parse(source.GetRawText())!.AsObject();
        static JsonObject Merge(JsonObject defaults, JsonObject value)
        {
            var result = (JsonObject)defaults.DeepClone();
            foreach (var field in value)
                result[field.Key] = field.Value is JsonObject child && result[field.Key] is JsonObject prior
                    ? Merge(prior, child) : field.Value?.DeepClone();
            return result;
        }
        foreach (var category in new[] { "actors", "actions" })
        {
            var defaults = root[category == "actors" ? "actor_defaults" : "action_defaults"] as JsonObject ?? new JsonObject();
            var values = root[category]!.AsArray();
            for (var i = 0; i < values.Count; i++) values[i] = Merge(defaults, values[i]!.AsObject());
        }
        foreach (var action in root["actions"]!.AsArray())
        {
            action!["to"] ??= action["from"]!.DeepClone();
            var choices = action["choices"] as JsonArray ?? new JsonArray();
            for (var i = 0; i < choices.Count; i++)
            {
                if (choices[i] is JsonValue reference && reference.TryGetValue<string>(out var id))
                    choices[i] = root["choice_templates"]![id]!.DeepClone();
                var choice = choices[i]!.AsObject();
                choice["seconds"] ??= action["end"]!.GetValue<int>() - action["start"]!.GetValue<int>();
                if (choice["inherit_information"]?.GetValue<bool>() == true)
                    choice["requires_information"] = action["decision_information"]?.DeepClone() ?? new JsonArray();
            }
            action["choices"] = choices.DeepClone();
        }
        return JsonSerializer.SerializeToElement(root);
    }

    public static Report Check(JsonElement history, CheckRequest? request = null)
    {
        history = Expand(history);
        if (request is not null) history = Project(history, request);
        var issues = new List<Issue>(); var decisions = new List<Decision>();
        var invalid = new HashSet<string>(StringComparer.Ordinal);
        void Fail(string id, string kind, string detail)
        {
            if (!issues.Any(x => x.Event == id && x.Kind == kind && x.Detail == detail)) issues.Add(new(id, kind, detail));
            invalid.Add(id);
        }
        var start = history.GetProperty("start").GetInt32(); var end = history.GetProperty("end").GetInt32();
        if (start >= end) throw new FormatException("Invalid history interval");
        var nodes = List(history, "nodes").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var routes = List(history, "routes").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var edges = List(history, "edges").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var channels = List(history, "channels").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var actors = List(history, "actors").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var actions = List(history, "actions").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var typedHistory = history.TryGetProperty("declaration_model", out var declarationModel) && declarationModel.GetString() == "typed-history-v1";
        var operations = List(history, "operations").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var policies = List(history, "policies").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var policyChoices = new Dictionary<string, JsonElement[]>(StringComparer.Ordinal);
        var resourceDefinitions = List(history, "resources").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var objects = List(history, "objects").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var holders = new Dictionary<string, string>(StringComparer.Ordinal);
        var objectLocations = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (id, item) in objects)
        {
            _ = Text(item, "type");
            var held = item.TryGetProperty("holder", out var holder);
            var located = item.TryGetProperty("location", out var location);
            if (held == located) throw new FormatException("Object must have exactly one holder or location: " + id);
            if (held)
            {
                if (!actors.ContainsKey(holder.GetString()!)) throw new FormatException("Unknown object holder: " + id);
                holders.Add(id, holder.GetString()!);
            }
            else
            {
                if (!nodes.ContainsKey(location.GetString()!)) throw new FormatException("Unknown object location: " + id);
                objectLocations.Add(id, location.GetString()!);
            }
            if (item.TryGetProperty("point", out var point))
            {
                var coordinates = point.EnumerateArray().ToArray();
                if (coordinates.Length is not (2 or 3) || coordinates.Any(x => !x.TryGetInt32(out _))) throw new FormatException("Object point must use integer decimeters: " + id);
            }
        }
        IEnumerable<string> EventResources(JsonElement e) => Strings(e, "resources")
            .Concat(Strings(e, "uses")).Concat(Strings(e, "takes"))
            .Concat(List(e, "gives").Select(x => Text(x, "object")))
            .Concat(List(e, "places").Select(x => Text(x, "object")))
            .Concat(new[] { "@body(" + Text(e, "actor") + ")" })
            .Concat(List(e, "gives").Select(x => "@body(" + Text(x, "to") + ")")).Distinct(StringComparer.Ordinal);
        var typedResources = history.TryGetProperty("resources", out _);
        foreach (var resource in resourceDefinitions.Values)
        {
            if (resource.TryGetProperty("capacity", out var capacity) && capacity.GetInt32() < 1) throw new FormatException("Invalid resource capacity");
            if (resource.TryGetProperty("location", out var location) && !nodes.ContainsKey(location.GetString()!)) throw new FormatException("Unknown resource location");
        }
        if (actors.Count == 0 || actions.Count == 0 || actions.Count > 10000) throw new FormatException("History size");
        var positions = actors.ToDictionary(x => x.Key, x => Text(x.Value, "location"), StringComparer.Ordinal);
        static int[]? Point(JsonElement value, string key)
        {
            if (!value.TryGetProperty(key, out var point)) return null;
            var coordinates = point.EnumerateArray().ToArray();
            if (coordinates.Length is not (2 or 3) || coordinates.Any(x => !x.TryGetInt32(out _))) throw new FormatException("Position must use integer decimeters");
            return coordinates.Select(x => x.GetInt32()).ToArray();
        }
        static double Distance(int[] a, int[] b)
        {
            if (a.Length != b.Length) throw new FormatException("Position dimensions differ");
            return Math.Sqrt(a.Zip(b, (x, y) => Math.Pow((double)x - y, 2)).Sum()) / 10;
        }
        var actorPoints = actors.ToDictionary(x => x.Key, x => Point(x.Value, "point"), StringComparer.Ordinal);
        var objectPoints = objects.ToDictionary(x => x.Key, x => Point(x.Value, "point"), StringComparer.Ordinal);
        var verifiedPoints = new HashSet<string>(StringComparer.Ordinal);
        var unspecifiedPoints = new HashSet<string>(StringComparer.Ordinal);
        var needs = actors.ToDictionary(x => x.Key, x => Numbers(x.Value.GetProperty("needs")), StringComparer.Ordinal);
        var weights = actors.ToDictionary(x => x.Key, x => Numbers(x.Value.GetProperty("weights")), StringComparer.Ordinal);
        var information = actors.ToDictionary(x => x.Key, x => Strings(x.Value, "initial_information").ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);
        var knowledge = actors.ToDictionary(x => x.Key, x => Strings(x.Value, "initial_propositions").ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);
        var receivedPropositions = actors.ToDictionary(x => x.Key, _ => new Dictionary<string, string[]>(StringComparer.Ordinal), StringComparer.Ordinal);
        var state = Strings(history, "initial_facts").ToHashSet(StringComparer.Ordinal);
        var lastNeedTime = actors.Keys.ToDictionary(x => x, _ => start, StringComparer.Ordinal);
        JsonElement[] Segments(JsonElement route) => typedHistory ? Strings(route, "edge_ids").Where(edges.ContainsKey).Select(x => edges[x]).ToArray() : [route];
        foreach (var (id, edge) in edges)
        {
            if (!nodes.ContainsKey(Text(edge, "from")) || !nodes.ContainsKey(Text(edge, "to"))) throw new FormatException("Unknown edge endpoint: " + id);
            var seconds = edge.GetProperty("minimum_seconds").GetDouble();
            if (!double.IsFinite(seconds) || seconds <= 0) throw new FormatException("Invalid edge duration: " + id);
        }
        JsonElement[] ElaborateChoices(JsonElement e, JsonElement profile)
        {
            if (!profile.TryGetProperty("policy_id", out var policyId) || !policies.TryGetValue(policyId.GetString()!, out var policy))
                throw new FormatException("Unknown actor policy");
            var intent = Text(e, "intent");
            var prediction = policy.GetProperty("predictions").GetProperty(intent);
            var goal = Text(profile, "priority"); var actor = Text(profile, "id");
            var seconds = e.GetProperty("end").GetInt32() - e.GetProperty("start").GetInt32();
            var choices = new List<JsonElement>();
            void Add(string id, JsonElement definition, IEnumerable<string> requires)
            {
                var effect = Bind(JsonNode.Parse(definition.GetProperty("effect").GetRawText()), actor, goal);
                choices.Add(JsonSerializer.SerializeToElement(new
                {
                    id, seconds, perceived_need_effects = effect,
                    requires_propositions = requires.Select(x => x.Replace("$actor", actor, StringComparison.Ordinal).Replace("$goal", goal, StringComparison.Ordinal)).Distinct(StringComparer.Ordinal).ToArray()
                }));
            }
            Add("do", prediction, Strings(e, "requires_propositions").Concat(Strings(prediction, "requires_propositions")));
            foreach (var alternative in List(policy, "alternatives"))
                if (!alternative.TryGetProperty("intents", out _) || Strings(alternative, "intents").Contains(intent))
                    Add(Text(alternative, "id"), alternative, Strings(alternative, "requires_propositions"));
            if (choices.Select(x => Text(x, "id")).Distinct(StringComparer.Ordinal).Count() != choices.Count) throw new FormatException("Duplicate policy choice");
            return choices.ToArray();
        }
        foreach (var a in actors)
        {
            if (!nodes.ContainsKey(positions[a.Key])) throw new FormatException("Unknown actor start node");
            foreach (var (key, value) in needs[a.Key])
                if (!double.IsFinite(value) || value < 0 || value > 100 || !weights[a.Key].TryGetValue(key, out var w) || !double.IsFinite(w) || w < 0)
                    throw new FormatException("Invalid actor drive profile");
        }
        int Begin(JsonElement e) => e.GetProperty("start").GetInt32();
        int Finish(JsonElement e) => e.GetProperty("end").GetInt32();
        foreach (var (id, e) in actions)
        {
            if (!actors.ContainsKey(Text(e, "actor"))) throw new FormatException("Unknown event actor");
            if (typedHistory)
            {
                if (!e.TryGetProperty("operation_id", out var operationId) || !operations.TryGetValue(operationId.GetString()!, out var operation))
                    Fail(id, "operation-schema", "Missing declared operation");
                else
                {
                    var actor = Text(e, "actor");
                    var goal = actors[actor].TryGetProperty("priority", out var priority) ? priority.GetString()! : "";
                    var expected = history.TryGetProperty("action_defaults", out var defaults)
                        ? JsonNode.Parse(defaults.GetRawText())!.AsObject() : new JsonObject();
                    foreach (var field in Bind(JsonNode.Parse(operation.GetRawText()), actor, goal)!.AsObject()) expected[field.Key] = field.Value?.DeepClone();
                    var actual = JsonNode.Parse(e.GetRawText())!.AsObject();
                    var instanceFields = new HashSet<string>(["id", "actor", "start", "end", "from", "to", "route", "operation_id", "selected", "choices", "decision_information", "companion_actions", "point", "from_point", "to_point"], StringComparer.Ordinal);
                    static bool Empty(JsonNode? node) => node is null || node is JsonArray a && a.Count == 0 || node is JsonObject o && o.Count == 0;
                    foreach (var key in expected.Select(x => x.Key).Concat(actual.Select(x => x.Key)).Distinct(StringComparer.Ordinal).Where(x => !instanceFields.Contains(x)))
                        if (!(Empty(expected[key]) && Empty(actual[key])) && !JsonNode.DeepEquals(expected[key], actual[key]))
                            Fail(id, "operation-schema", "Instance changes operation field: " + key);
                }
                if (Text(e, "selected") != "do") Fail(id, "operation-schema", "Selected policy action is not the executed operation");
                var expectedChoices = ElaborateChoices(e, actors[Text(e, "actor")]);
                policyChoices[id] = expectedChoices;
                var authoredChoices = List(e, "choices");
                if (authoredChoices.Length != expectedChoices.Length) Fail(id, "policy-elaboration", "Policy candidate set differs");
                foreach (var choice in expectedChoices)
                {
                    var matches = authoredChoices.Where(x => Text(x, "id") == Text(choice, "id")).ToArray();
                    if (matches.Length != 1 || matches[0].GetProperty("seconds").GetDouble() != choice.GetProperty("seconds").GetDouble() ||
                        !JsonNode.DeepEquals(JsonNode.Parse(matches[0].GetProperty("perceived_need_effects").GetRawText()), JsonNode.Parse(choice.GetProperty("perceived_need_effects").GetRawText())) ||
                        !Strings(matches[0], "requires_propositions").ToHashSet(StringComparer.Ordinal).SetEquals(Strings(choice, "requires_propositions")))
                        Fail(id, "policy-elaboration", "Policy candidate differs: " + Text(choice, "id"));
                }
            }
            if (Begin(e) < start || Finish(e) > end || Finish(e) <= Begin(e)) Fail(id, "interval", "Invalid action interval");
            if (!nodes.ContainsKey(Text(e, "from")) || !nodes.ContainsKey(Text(e, "to"))) Fail(id, "location", "Unknown action node");
            var resources = Strings(e, "resources");
            if (resources.Distinct(StringComparer.Ordinal).Count() != resources.Length) Fail(id, "resource", "Duplicate resource reservation");
            foreach (var resource in EventResources(e))
                if (typedResources && !resource.StartsWith("@body(", StringComparison.Ordinal) && !resourceDefinitions.ContainsKey(resource) && !objects.ContainsKey(resource))
                    Fail(id, "resource", "Undeclared resource: " + resource);
            foreach (var item in Strings(e, "uses").Concat(Strings(e, "takes")).Concat(List(e, "gives").Select(x => Text(x, "object"))).Concat(List(e, "places").Select(x => Text(x, "object"))))
                if (!objects.ContainsKey(item)) Fail(id, "object", "Unknown object: " + item);
            foreach (var transfer in List(e, "gives"))
                if (!actors.ContainsKey(Text(transfer, "to"))) Fail(id, "object-transfer", "Unknown recipient: " + Text(transfer, "to"));
            foreach (var target in Strings(e, "erase_actor_memories"))
                if (!actors.ContainsKey(target)) Fail(id, "memory-target", "Unknown actor: " + target);
            if (e.TryGetProperty("actual_need_effects", out var effects))
                foreach (var (need, delta) in Numbers(effects))
                    if (!needs[Text(e, "actor")].ContainsKey(need) || !double.IsFinite(delta)) Fail(id, "need-effect", "Invalid actual need effect: " + need);
        }
        var ordered = actions.OrderBy(x => Begin(x.Value)).ThenBy(x => x.Key, StringComparer.Ordinal).ToArray();
        foreach (var group in ordered.GroupBy(x => Text(x.Value, "actor")))
        {
            var list = group.ToArray();
            var retainsPosition = history.TryGetProperty("idle", out var idle) && idle.GetString() == "retain_location";
            if (!retainsPosition && (Begin(list[0].Value) != start || Finish(list[^1].Value) != end))
                Fail(group.Key, "coverage", "History does not cover entire interval");
            for (var i = 1; i < list.Length; i++)
                if (!retainsPosition && Begin(list[i].Value) > Finish(list[i - 1].Value)) Fail(list[i].Key, "coverage", "Undeclared interval");
            for (var i = 0; i < list.Length; i++)
            for (var j = i + 1; j < list.Length; j++)
                if (Begin(list[j].Value) < Finish(list[i].Value))
                {
                    Fail(list[j].Key, "actor-overlap", list[i].Key);
                    Fail(list[i].Key, "actor-overlap", list[j].Key);
                }
        }
        foreach (var group in ordered.SelectMany(x => EventResources(x.Value).Select(r => (Resource: r, Event: x))).GroupBy(x => x.Resource))
        {
            var list = group.OrderBy(x => Begin(x.Event.Value)).ToArray();
            var capacity = !objects.ContainsKey(group.Key) && resourceDefinitions.TryGetValue(group.Key, out var definition) && definition.TryGetProperty("capacity", out var count) ? count.GetInt32() : 1;
            foreach (var time in list.Select(x => Begin(x.Event.Value)).Distinct())
            {
                var occupied = list.Where(x => Begin(x.Event.Value) <= time && time < Finish(x.Event.Value)).ToArray();
                if (occupied.Length > capacity)
                    foreach (var item in occupied) Fail(item.Event.Key, "resource-overlap", group.Key + ": capacity " + capacity);
            }
        }
        var notifications = List(history, "information");
        var environment = List(history, "environment");
        if (notifications.Select(n => Text(n, "id")).Distinct(StringComparer.Ordinal).Count() != notifications.Length)
            throw new FormatException("Duplicate information identity");
        foreach (var channel in channels.Values)
        {
            if (!nodes.ContainsKey(Text(channel, "from")) || !nodes.ContainsKey(Text(channel, "to"))) throw new FormatException("Unknown channel endpoint");
            if (channel.GetProperty("minimum_delay").GetInt32() < 0) throw new FormatException("Negative channel delay");
        }
        foreach (var change in environment)
        {
            var at = change.GetProperty("at").GetInt32();
            if (at < start || at > end) throw new FormatException("Environment event outside history");
        }
        foreach (var n in notifications)
        {
            var id = Text(n, "id"); var receiver = Text(n, "actor"); var time = n.GetProperty("at").GetInt32();
            if (!actors.ContainsKey(receiver) || time < start || time > end) throw new FormatException("Information receiver/time");
            if (!actions.TryGetValue(Text(n, "source_action"), out var source) || Finish(source) > time)
                Fail(id, "information-source", "Source action has not finished");
            _ = Text(n, "channel");
            if (!n.TryGetProperty("propositions", out _) && !n.TryGetProperty("content", out _))
                throw new FormatException("Missing information propositions");
            if (typedHistory && actions.TryGetValue(Text(n, "source_action"), out var sourceAction) && channels.TryGetValue(Text(n, "channel"), out var sourceChannel))
            {
                var expected = sourceChannel.TryGetProperty("transform", out _) ? Strings(sourceChannel, "transform") : Strings(sourceAction, "emits");
                if (!Strings(n, "propositions").ToHashSet(StringComparer.Ordinal).SetEquals(expected))
                    Fail(id, "information-payload", "Notification does not match source emission and channel transformation");
                if (Strings(sourceAction, "emits").Length == 0) Fail(id, "information-payload", "Source action emits no information");
            }
        }
        var pendingCompletions = new HashSet<string>(StringComparer.Ordinal);
        var completed = new HashSet<string>(StringComparer.Ordinal);
        void CheckObjects(string id, JsonElement e)
        {
            var actor = Text(e, "actor");
            foreach (var item in Strings(e, "uses").Concat(Strings(e, "takes")).Distinct(StringComparer.Ordinal))
            {
                if (!objects.ContainsKey(item)) continue;
                if (holders.TryGetValue(item, out var holder))
                {
                    if (holder != actor) Fail(id, "object-holder", item + " held by " + holder);
                }
                else if (!objectLocations.TryGetValue(item, out var location) || location != positions[actor])
                    Fail(id, "object-location", "Object unavailable here: " + item);
                else
                {
                    var itemPoint = objectPoints[item];
                    if (actorPoints[actor] is { } actorPoint && itemPoint is not null && actors[actor].TryGetProperty("reach_meters", out var declaredReach))
                    {
                        var reach = declaredReach.GetDouble();
                        if (!double.IsFinite(reach) || reach < 0) throw new FormatException("Invalid actor reach");
                        if (Distance(actorPoint, itemPoint) > reach + 1e-9) Fail(id, "object-reach", "Object beyond declared reach: " + item);
                    }
                    else unspecifiedPoints.Add(id);
                }
            }
            foreach (var transfer in List(e, "gives"))
            {
                var item = Text(transfer, "object"); var recipient = Text(transfer, "to");
                if (!holders.TryGetValue(item, out var holder) || holder != actor) Fail(id, "object-holder", "Transfer requires ownership: " + item);
                if (!positions.TryGetValue(recipient, out var location) || location != positions[actor]) Fail(id, "object-transfer", "Recipient is not present: " + recipient);
            }
            foreach (var placement in List(e, "places"))
            {
                var item = Text(placement, "object");
                if (!holders.TryGetValue(item, out var holder) || holder != actor) Fail(id, "object-holder", "Placement requires holding: " + item);
                if (Text(placement, "location") != positions[actor]) Fail(id, "object-placement", "Placement cannot change rooms");
                var point = Point(placement, "point");
                if (point is not null && actorPoints[actor] is { } current && actors[actor].TryGetProperty("reach_meters", out var reach) && Distance(current, point) > reach.GetDouble())
                    Fail(id, "object-reach", "Placement beyond declared reach");
                else if (point is null || actorPoints[actor] is null) unspecifiedPoints.Add(id);
            }
        }
        void CheckContinuous(string id, JsonElement e)
        {
            CheckObjects(id, e);
            foreach (var fact in Strings(e, "requires_during"))
                if (!state.Contains(fact)) Fail(id, "continuous-precondition", fact);
            foreach (var fact in Strings(e, "requires_absent_during"))
                if (state.Contains(fact)) Fail(id, "continuous-precondition", "Unexpected " + fact);
            var profile = actors[Text(e, "actor")];
            if (profile.TryGetProperty("contact_presence_fact", out var presence) &&
                Strings(profile, "contact_capabilities").Contains(Text(e, "capability")) && !state.Contains(presence.GetString()!))
                Fail(id, "contact-presence", "Object manipulation requires presence throughout the action");
            if (Text(e, "kind") == "move" && routes.TryGetValue(Text(e, "route"), out var route))
            {
                foreach (var segment in Segments(route))
                {
                    var bypass = segment.TryGetProperty("access_bypass_capability", out var ability) && Strings(profile, "capabilities").Contains(ability.GetString()!);
                    foreach (var fact in Strings(segment, "requires"))
                        if (!bypass && !state.Contains(fact)) Fail(id, "route-access", "In transit: " + fact);
                    foreach (var fact in Strings(segment, "requires_absent"))
                        if (state.Contains(fact)) Fail(id, "movement-state", "In transit: " + fact);
                }
            }
        }
        foreach (var time in actions.Values.SelectMany(e => new[] { Begin(e), Finish(e) }).Concat(notifications.Select(n => n.GetProperty("at").GetInt32()))
                     .Concat(environment.Select(n => n.GetProperty("at").GetInt32())).Where(t => start <= t && t <= end).Distinct().Order())
        {
            // Continuous need evolution precedes every instantaneous effect. In particular,
            // saturation at an action's completion must not erase decay during its interval.
            foreach (var (actor, profile) in actors)
            {
                foreach (var (need, rate) in Numbers(profile.GetProperty("need_decay_per_second")))
                {
                    if (!needs[actor].ContainsKey(need) || !double.IsFinite(rate) || rate < 0) throw new FormatException("Invalid decay");
                    needs[actor][need] = Math.Clamp(needs[actor][need] - rate * (time - lastNeedTime[actor]), 0, 100);
                }
                lastNeedTime[actor] = time;
            }
            foreach (var (id, e) in ordered.Where(x => Begin(x.Value) < time && time <= Finish(x.Value) && pendingCompletions.Contains(x.Key) && !invalid.Contains(x.Key)))
                CheckContinuous(id, e);
            foreach (var (id, e) in ordered.Where(x => Finish(x.Value) == time && pendingCompletions.Contains(x.Key) && !invalid.Contains(x.Key)))
            {
                foreach (var fact in Strings(e, "requires_end"))
                    if (!state.Contains(fact)) Fail(id, "completion-precondition", fact);
                foreach (var fact in Strings(e, "requires_absent_end"))
                    if (state.Contains(fact)) Fail(id, "completion-precondition", "Unexpected " + fact);
            }

            // Paired physical actions cannot borrow a companion's merely declared interval.
            // Resolve failures before either participant is allowed to commit its effects.
            var changed = true;
            while (changed)
            {
                var count = invalid.Count;
                foreach (var (id, e) in ordered.Where(x => Finish(x.Value) == time && pendingCompletions.Contains(x.Key) && !invalid.Contains(x.Key)))
                    foreach (var companion in Strings(e, "companion_actions"))
                        if (!pendingCompletions.Contains(companion) || invalid.Contains(companion))
                            Fail(id, "companion", "Companion action did not execute successfully: " + companion);
                changed = invalid.Count != count;
            }

            var changes = environment.Where(n => n.GetProperty("at").GetInt32() == time).ToArray();
            var endings = ordered.Where(x => Finish(x.Value) == time && pendingCompletions.Contains(x.Key) && !invalid.Contains(x.Key)).ToArray();
            var writes = changes.Select(x => (Id: Text(x, "id"), Value: x))
                .Concat(endings.Select(x => (Id: x.Key, Value: x.Value))).ToArray();
            foreach (var fact in writes.SelectMany(x => Strings(x.Value, "adds")).Intersect(writes.SelectMany(x => Strings(x.Value, "removes")), StringComparer.Ordinal))
                foreach (var writer in writes.Where(x => Strings(x.Value, "adds").Contains(fact) || Strings(x.Value, "removes").Contains(fact)))
                    Fail(writer.Id, "simultaneous-write", "Conflicting changes to " + fact);
            changed = true;
            while (changed)
            {
                var count = invalid.Count;
                foreach (var (id, e) in endings.Where(x => !invalid.Contains(x.Key)))
                    foreach (var companion in Strings(e, "companion_actions"))
                        if (invalid.Contains(companion)) Fail(id, "companion", "Companion action has conflicting effects: " + companion);
                changed = invalid.Count != count;
            }
            foreach (var change in changes.Where(x => !invalid.Contains(Text(x, "id"))))
            {
                foreach (var fact in Strings(change, "removes")) state.Remove(fact);
                foreach (var fact in Strings(change, "adds")) state.Add(fact);
            }
            foreach (var (id, e) in endings.Where(x => !invalid.Contains(x.Key)))
            {
                var actor = Text(e, "actor");
                if (Text(e, "kind") == "move")
                {
                    var sameNode = positions[actor] == Text(e, "to");
                    positions[actor] = Text(e, "to");
                    actorPoints[actor] = Point(e, "to_point") ?? (sameNode ? actorPoints[actor] : null);
                }
                foreach (var f in Strings(e, "removes")) state.Remove(f);
                foreach (var f in Strings(e, "adds")) state.Add(f);
                foreach (var item in Strings(e, "takes"))
                {
                    objectLocations.Remove(item);
                    holders[item] = actor;
                    objectPoints[item] = null;
                }
                foreach (var transfer in List(e, "gives"))
                {
                    var item = Text(transfer, "object");
                    objectLocations.Remove(item);
                    holders[item] = Text(transfer, "to");
                    objectPoints[item] = null;
                }
                foreach (var placement in List(e, "places"))
                {
                    var item = Text(placement, "object"); holders.Remove(item);
                    objectLocations[item] = Text(placement, "location"); objectPoints[item] = Point(placement, "point");
                }
                if (e.TryGetProperty("actual_need_effects", out var effects))
                    foreach (var (need, delta) in Numbers(effects))
                    {
                        if (!needs[actor].ContainsKey(need) || !double.IsFinite(delta)) throw new FormatException("Invalid actual need effect");
                        needs[actor][need] = Math.Clamp(needs[actor][need] + delta, 0, 100);
                    }
                foreach (var target in Strings(e, "erase_actor_memories"))
                {
                    var retained = Strings(actors[target], "retained_information").ToHashSet(StringComparer.Ordinal);
                    information[target].RemoveWhere(id => !retained.Contains(id));
                    foreach (var idToRemove in receivedPropositions[target].Keys.Where(id => !retained.Contains(id)).ToArray())
                        receivedPropositions[target].Remove(idToRemove);
                    knowledge[target] = Strings(actors[target], "retained_propositions")
                        .Concat(receivedPropositions[target].Values.SelectMany(x => x)).ToHashSet(StringComparer.Ordinal);
                }
                completed.Add(id);
            }
            foreach (var (id, e) in ordered.Where(x => Begin(x.Value) < time && time < Finish(x.Value) && pendingCompletions.Contains(x.Key) && !invalid.Contains(x.Key)))
                CheckContinuous(id, e);
            foreach (var n in notifications.Where(n => n.GetProperty("at").GetInt32() == time))
            {
                var source = Text(n, "source_action");
                if (invalid.Contains(Text(n, "id"))) continue;
                if (!completed.Contains(source))
                { Fail(Text(n, "id"), "information-source", "Source action has not completed successfully"); continue; }
                if (!channels.TryGetValue(Text(n, "channel"), out var channel) ||
                    Text(channel, "from") != Text(actions[source], "to") ||
                    Text(channel, "to") != positions[Text(n, "actor")] ||
                    time - Finish(actions[source]) < channel.GetProperty("minimum_delay").GetInt32())
                { Fail(Text(n, "id"), "information-channel", "No timely channel between sender and receiver"); continue; }
                if (actions.Values.Any(a => Text(a, "actor") == Text(n, "actor") && Text(a, "kind") == "move" && Begin(a) < time && time < Finish(a)))
                { Fail(Text(n, "id"), "information-location", "Receiver is travelling"); continue; }
                if (n.TryGetProperty("at_location", out var at) && positions[Text(n, "actor")] != at.GetString())
                { Fail(Text(n, "id"), "information-location", "Receiver not at declared listening/observation node"); continue; }
                if (n.TryGetProperty("requires", out var requires) && requires.EnumerateArray().Any(x => !state.Contains(x.GetString()!)))
                { Fail(Text(n, "id"), "information-condition", "Channel/world conditions absent"); continue; }
                information[Text(n, "actor")].Add(Text(n, "id"));
                // Legacy payloads may contain records. Typed histories use declared symbols;
                // only those propositions enter the subjective reasoning context.
                var propositions = List(n, "propositions").Where(x => x.ValueKind == JsonValueKind.String).Select(x => x.GetString()!).ToArray();
                receivedPropositions[Text(n, "actor")][Text(n, "id")] = propositions;
                knowledge[Text(n, "actor")].UnionWith(propositions);
            }
            foreach (var (id, e) in ordered.Where(x => Begin(x.Value) == time))
            {
                if (invalid.Contains(id)) continue;
                var before = issues.Count; var actor = Text(e, "actor"); var profile = actors[actor];
                var location = Text(e, "from"); var duration = Finish(e) - Begin(e);
                if (!nodes.ContainsKey(location) || positions[actor] != location) Fail(id, "location", positions[actor] + " != " + location);
                var fromPoint = Point(e, "from_point") ?? Point(e, "point") ?? actorPoints[actor];
                var toPoint = Point(e, "to_point") ?? (Text(e, "kind") == "move" && Text(e, "to") != location ? null : fromPoint);
                if (fromPoint is not null && actorPoints[actor] is { } currentPoint && !fromPoint.SequenceEqual(currentPoint))
                    Fail(id, "position", "Action does not start at the actor's actual point");
                if (fromPoint is not null && toPoint is not null && actorPoints[actor] is not null)
                {
                    verifiedPoints.Add(id);
                    if (Text(e, "kind") != "move" && !fromPoint.SequenceEqual(toPoint)) Fail(id, "teleport", "Non-movement action changes room position");
                    if (Text(e, "kind") == "move" && Text(e, "to") == location)
                    {
                        if (!profile.TryGetProperty("maximum_speed", out var speedLimit)) unspecifiedPoints.Add(id);
                        else
                        {
                            var speed = speedLimit.GetDouble();
                            if (!double.IsFinite(speed) || speed <= 0) throw new FormatException("Invalid speed");
                            if (Distance(fromPoint, toPoint) > speed * duration + 1e-9) Fail(id, "travel-time", "Room movement exceeds speed budget");
                        }
                    }
                }
                else unspecifiedPoints.Add(id);
                if (!Strings(profile, "capabilities").Contains(Text(e, "capability"))) Fail(id, "capability", Text(e, "capability"));
                foreach (var required in Strings(e, "requires")) if (!state.Contains(required)) Fail(id, "world-precondition", required);
                foreach (var absent in Strings(e, "requires_absent")) if (state.Contains(absent)) Fail(id, "world-precondition", "Unexpected " + absent);
                foreach (var proposition in Strings(e, "requires_propositions"))
                    if (!knowledge[actor].Contains(proposition)) Fail(id, "information", "Actor has not received proposition: " + proposition);
                CheckContinuous(id, e);
                foreach (var resource in Strings(e, "resources"))
                    if (resourceDefinitions.TryGetValue(resource, out var definition) && definition.TryGetProperty("location", out var resourceLocation) && resourceLocation.GetString() != location)
                        Fail(id, "resource-location", resource);
                if (profile.TryGetProperty("contact_presence_fact", out var presence) &&
                    Strings(profile, "contact_capabilities").Contains(Text(e, "capability")) && !state.Contains(presence.GetString()!))
                    Fail(id, "contact-presence", "Object manipulation requires declared presence state");
                foreach (var companion in Strings(e, "companion_actions"))
                    if (!actions.TryGetValue(companion, out var other) || Text(other, "actor") == actor ||
                        Begin(other) != time || Finish(other) != Finish(e) || Text(other, "from") != location || Text(other, "to") != Text(e, "to"))
                        Fail(id, "companion", "No matching physical companion: " + companion);
                if (Text(e, "kind") == "move")
                {
                    if (!routes.TryGetValue(Text(e, "route"), out var route)) Fail(id, "route", "Unknown route");
                    else
                    {
                        if (Text(route, "from") != location || Text(route, "to") != Text(e, "to")) Fail(id, "route", "Endpoints mismatch");
                        if (typedHistory)
                        {
                            var segmentIds = Strings(route, "edge_ids"); var cursor = location; double seconds = 0;
                            if (segmentIds.Length == 0) Fail(id, "route", "Typed route has no graph edges");
                            foreach (var segmentId in segmentIds)
                            {
                                if (!edges.TryGetValue(segmentId, out var segment)) { Fail(id, "route", "Unknown edge: " + segmentId); continue; }
                                if (Text(segment, "from") != cursor) Fail(id, "route", "Disconnected edge: " + segmentId);
                                cursor = Text(segment, "to"); seconds += segment.GetProperty("minimum_seconds").GetDouble();
                                if (segment.TryGetProperty("capability", out var mode) && !Strings(profile, "capabilities").Contains(mode.GetString()!))
                                    Fail(id, "movement-capability", "Actor lacks edge movement mode: " + segmentId);
                            }
                            if (cursor != Text(e, "to")) Fail(id, "route", "Edge chain ends at the wrong node");
                            if (Math.Abs(route.GetProperty("minimum_seconds").GetDouble() - seconds) > 1e-9) Fail(id, "route", "Route duration differs from edge sum");
                            if (duration < seconds) Fail(id, "travel-time", "Insufficient time for declared edge chain");
                        }
                        var abilities = Strings(profile, "capabilities");
                        if (route.TryGetProperty("capability", out var movementCapability) && !abilities.Contains(movementCapability.GetString()!))
                            Fail(id, "movement-capability", "Actor lacks declared movement mode");
                        var bypass = route.TryGetProperty("access_bypass_capability", out var bypassAbility) && abilities.Contains(bypassAbility.GetString()!);
                        foreach (var f in Strings(route, "requires")) if (!state.Contains(f) && !bypass) Fail(id, "route-access", f);
                        foreach (var f in Strings(route, "requires_absent")) if (state.Contains(f)) Fail(id, "movement-state", f);
                        var minimum = route.GetProperty("minimum_seconds").GetDouble();
                        if (!double.IsFinite(minimum) || minimum <= 0) throw new FormatException("Invalid route duration");
                        if (duration < minimum) Fail(id, "travel-time", duration + " < " + minimum);
                        if (!(history.TryGetProperty("travel_model", out var model) && model.GetString() == "node_graph_seconds"))
                        {
                        var points = List(route, "points"); double length = 0;
                        if (points.Length >= 2)
                        {
                            var routeFromPoint = nodes[Text(route, "from")].GetProperty("point").EnumerateArray().Select(x => x.GetDouble()).ToArray();
                            var routeToPoint = nodes[Text(route, "to")].GetProperty("point").EnumerateArray().Select(x => x.GetDouble()).ToArray();
                            if (!points[0].EnumerateArray().Select(x => x.GetDouble()).SequenceEqual(routeFromPoint) ||
                                !points[^1].EnumerateArray().Select(x => x.GetDouble()).SequenceEqual(routeToPoint))
                                Fail(id, "route-geometry", "Polyline does not meet declared location points");
                        }
                        for (var i = 1; i < points.Length; i++)
                        {
                            var a = points[i - 1].EnumerateArray().Select(v => v.GetDouble()).ToArray();
                            var b = points[i].EnumerateArray().Select(v => v.GetDouble()).ToArray();
                            if (a.Length != 3 || b.Length != 3 || a.Concat(b).Any(v => !double.IsFinite(v))) throw new FormatException("Invalid route point");
                            length += Math.Sqrt(a.Zip(b, (u, v) => (u - v) * (u - v)).Sum());
                        }
                        var speed = profile.GetProperty("maximum_speed").GetDouble();
                        if (!double.IsFinite(speed) || speed <= 0) throw new FormatException("Invalid speed");
                        if (points.Length < 2 || duration * speed + 1e-9 < length) Fail(id, "travel-time", "Polyline exceeds speed budget");
                        }
                    }
                }
                else if (Text(e, "to") != location) Fail(id, "teleport", "Non-movement action changes location");
                if (duration < e.GetProperty("minimum_seconds").GetInt32()) Fail(id, "action-time", "Action too short");
                if (e.TryGetProperty("passive", out var passive) && passive.GetBoolean())
                {
                    if (Text(e, "kind") != "hold" || Strings(e, "adds").Length != 0 || Strings(e, "removes").Length != 0 ||
                        List(e, "choices").Length != 0 || Strings(e, "erase_actor_memories").Length != 0 ||
                        e.GetProperty("actual_need_effects").EnumerateObject().Any())
                        Fail(id, "passive-effects", "Passive occupancy cannot perform an action");
                    if (issues.Count == before) pendingCompletions.Add(id);
                    continue;
                }
                var scores = new Dictionary<string, double>(StringComparer.Ordinal);
                var availableChoices = typedHistory ? policyChoices[id] : List(e, "choices");
                foreach (var option in availableChoices)
                {
                    var optionId = Text(option, "id");
                    if (Strings(option, "requires_information").Any(x => !information[actor].Contains(x))) continue;
                    if (Strings(option, "blocked_by_information").Any(x => information[actor].Contains(x))) continue;
                    if (Strings(option, "requires_propositions").Any(x => !knowledge[actor].Contains(x))) continue;
                    var effects = Numbers(option.GetProperty("perceived_need_effects"));
                    scores.Add(optionId, AutonomyDriveSolver.Score(needs[actor], weights[actor], effects,
                        option.GetProperty("seconds").GetDouble(), profile.GetProperty("time_cost").GetDouble()));
                }
                var selected = Text(e, "selected");
                Sim4Planner.Plan? forecast = null;
                if (typedHistory && profile.TryGetProperty("policy_id", out var actorPolicy) && policies.TryGetValue(actorPolicy.GetString()!, out var planningPolicy) &&
                    planningPolicy.TryGetProperty("planner", out var planner) && planner.GetString() == "sim4")
                {
                    var candidates = availableChoices.Select(option => new Sim4Planner.Candidate(Text(option, "id"),
                        option.GetProperty("seconds").GetDouble(), Numbers(option.GetProperty("perceived_need_effects")),
                        Strings(option, "requires_propositions"), [], [], [])).ToArray();
                    var input = new Sim4Planner.Input(actor, id + ":" + time,
                        new Dictionary<string, double>(needs[actor]), weights[actor], Numbers(profile.GetProperty("need_decay_per_second")),
                        profile.GetProperty("time_cost").GetDouble(), knowledge[actor].ToArray(), candidates);
                    forecast = Sim4Planner.Build(input, new(planningPolicy.TryGetProperty("planning_depth", out var depth) ? depth.GetInt32() : 3));
                    scores = forecast.FirstActionScores.ToDictionary(x => x.Key, x => x.Value, StringComparer.Ordinal);
                    scores["stop"] = 0;
                }
                if (!scores.TryGetValue(selected, out var selectedScore)) Fail(id, "information", "Selected option unavailable in actor mind");
                else
                {
                    if (selectedScore < scores.Values.Max() - 1e-9) Fail(id, "drive-choice", "A declared available option scores higher");
                    var selectedOption = availableChoices.Single(x => Text(x, "id") == selected);
                    decisions.Add(new(id, actor, selectedScore, scores, new Dictionary<string, double>(needs[actor]),
                        typedHistory ? Strings(selectedOption, "requires_propositions") : Strings(selectedOption, "requires_information"), Numbers(selectedOption.GetProperty("perceived_need_effects")))
                        { Valid = issues.Count == before, Forecast = forecast });
                }
                if (issues.Count == before) pendingCompletions.Add(id);
            }
        }
        foreach (var f in Strings(history, "required_final_facts")) if (!state.Contains(f)) Fail("$final", "final-state", f);
        foreach (var a in actors)
            if (a.Value.TryGetProperty("final_location", out var final) && positions[a.Key] != final.GetString()) Fail(a.Key, "final-location", positions[a.Key]);
        // A later continuous-condition failure invalidates the whole event certificate.
        decisions = decisions.Select(x => x with { Valid = x.Valid && !invalid.Contains(x.Event) && completed.Contains(x.Event) }).ToList();
        var schemaCertified = typedHistory && !issues.Any(x => x.Kind is "operation-schema" or "policy-elaboration" or "information-payload");
        return new(issues.Count == 0, actors.Count, actions.Count, issues, decisions)
        {
            DecisionModel = schemaCertified ? decisions.Any(x => x.Forecast is not null) ? "schema-policy-sim4" : "schema-policy-utility" : typedHistory ? "rejected-schema-policy" : "legacy-authored-choices",
            DecisionScope = typedHistory ? "submitted-operation-and-declared-alternatives" : "authored-candidate-list",
            PointVerifiedEvents = verifiedPoints.Count(x => !unspecifiedPoints.Contains(x)),
            PointUnspecifiedEvents = unspecifiedPoints.Count,
            FinalFacts = state.Order(StringComparer.Ordinal).ToArray(),
            ActiveActors = actions.Values.Select(x => Text(x, "actor")).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray(),
            Scope = history.TryGetProperty("projection", out _) ? "dependency-closed-subhistory" : "complete-history"
        };
    }

    public static IEnumerable<AuditItem> Audit(JsonElement history, JsonElement audit = default)
    {
        var report = Check(history);
        yield return new("complete-history", "valid", report.Valid ? "valid" : JsonSerializer.Serialize(report.Issues), report.Valid);
        foreach (var decision in report.Decisions)
            yield return new(decision.Event, "selected-maximum", decision.Valid ? "selected-maximum" : "invalid-decision-or-action", decision.Valid);
        foreach (var branch in List(history, "branches"))
        {
            var scoped = Check(history, new(Events: Strings(branch, "events"), Goals: Strings(branch, "goals")));
            yield return new("branch:" + Text(branch, "id"), "valid", scoped.Valid ? "valid" : JsonSerializer.Serialize(scoped.Issues), scoped.Valid);
        }
        foreach (var mutation in List(audit.ValueKind == JsonValueKind.Object ? audit : history, "mutations"))
        {
            var copy = JsonNode.Parse(Expand(history).GetRawText())!;
            var collection = mutation.TryGetProperty("collection", out var declaredCollection) ? declaredCollection.GetString() : "actions";
            if (collection is not ("actions" or "information" or "actors")) throw new FormatException("Unsupported history mutation collection");
            var action = copy[collection]!.AsArray().Single(x => x!["id"]!.GetValue<string>() == Text(mutation, "action"))!;
            foreach (var field in mutation.GetProperty("set").EnumerateObject()) action[field.Name] = JsonNode.Parse(field.Value.GetRawText());
            if (mutation.TryGetProperty("refresh_time", out var refresh) && refresh.GetBoolean())
                foreach (var choice in action["choices"]!.AsArray())
                    choice!["seconds"] = action["end"]!.GetValue<int>() - action["start"]!.GetValue<int>();
            var changed = Check(JsonSerializer.SerializeToElement(copy));
            var expected = Text(mutation, "expect_issue");
            var passed = changed.Issues.Any(x => x.Kind == expected);
            yield return new(Text(mutation, "id"), expected, passed ? expected : JsonSerializer.Serialize(changed.Issues), passed);
        }
    }
}
