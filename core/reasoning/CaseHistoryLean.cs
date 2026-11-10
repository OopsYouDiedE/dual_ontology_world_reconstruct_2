using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace DuelView.Core;

/// <summary>Generates an independent, computable Lean authoring target from DV history data.
/// It never imports a C# validity judgment. Generated sources belong in .runtime only.</summary>
public static class CaseHistoryLean
{
    public sealed record ExportResult(string Source, string Scope, IReadOnlyList<string> Covered,
        IReadOnlyList<string> NotCovered, int Actors, int Events, IReadOnlyList<string> SelectedEvents);
    private static JsonElement[] Rows(JsonElement value, string field) => value.TryGetProperty(field, out var array) ? array.EnumerateArray().ToArray() : [];
    private static string[] Names(JsonElement value, string field) => Rows(value, field).Select(x => x.GetString() ?? throw new FormatException(field)).ToArray();
    private static string Text(JsonElement value, string field) => value.GetProperty(field).GetString() ?? throw new FormatException(field);
    private static string Integer(JsonElement value, string field, long fallback = 0)
    {
        if (!value.TryGetProperty(field, out var n)) return fallback.ToString(CultureInfo.InvariantCulture);
        var number = n.GetDecimal();
        if (number != decimal.Truncate(number)) throw new FormatException("Lean history seconds must be integral: " + field);
        return number.ToString(CultureInfo.InvariantCulture);
    }
    private static string List(IEnumerable<string> values) => "[" + string.Join(", ", values) + "]";
    private sealed class Symbols
    {
        private readonly Dictionary<string, int> ids = new(StringComparer.Ordinal);
        public string Id(string value)
        {
            if (!ids.TryGetValue(value, out var id)) { id = ids.Count; ids.Add(value, id); }
            return id.ToString(CultureInfo.InvariantCulture);
        }
        public string Many(IEnumerable<string> values) => List(values.Distinct(StringComparer.Ordinal).Select(Id));
        public string Optional(JsonElement value, string key) => value.TryGetProperty(key, out var item) ? "some " + Id(item.GetString()!) : "none";
    }

    public static ExportResult Export(JsonElement history, string moduleName, CaseHistory.CheckRequest request) =>
        Export(CaseHistory.Project(history, request), moduleName);

    public static ExportResult Export(JsonElement history, string moduleName, JsonElement request = default, string? rejectionTarget = null)
    {
        if (!Regex.IsMatch(moduleName, "^[A-Za-z][A-Za-z0-9_]*$")) throw new ArgumentException("Invalid Lean namespace", nameof(moduleName));
        if (!history.TryGetProperty("declaration_model", out var model) || model.GetString() != "typed-history-v1")
            throw new NotSupportedException("Lean history export requires the typed DV elaboration; legacy JSON must be migrated first.");
        var actors = Rows(history, "actors"); var actions = Rows(history, "actions"); var edges = Rows(history, "edges");
        var routes = Rows(history, "routes").ToDictionary(x => Text(x, "id"), StringComparer.Ordinal);
        var actorIds = new Symbols(); var nodeIds = new Symbols(); var edgeIds = new Symbols(); var facts = new Symbols(); var capabilities = new Symbols(); var resources = new Symbols();
        foreach (var category in new[] { "actors", "nodes", "edges", "resources", "objects", "actions" })
        {
            var ids = Rows(history, category).Select(x => Text(x, "id")).ToArray();
            if (ids.Distinct(StringComparer.Ordinal).Count() != ids.Length) throw new FormatException("Duplicate history identity: " + category);
        }
        foreach (var actor in actors) actorIds.Id(Text(actor, "id"));
        foreach (var node in Rows(history, "nodes")) nodeIds.Id(Text(node, "id"));
        foreach (var edge in edges) edgeIds.Id(Text(edge, "id"));
        var resourceRows = Rows(history, "resources").Select(x => (Id: Text(x, "id"), Capacity: Integer(x, "capacity", 1))).ToList();
        foreach (var obj in Rows(history, "objects"))
        {
            var id = Text(obj, "id"); resourceRows.RemoveAll(x => x.Id == id); resourceRows.Add((id, "1"));
        }
        foreach (var actor in actors) resourceRows.Add(("@body(" + Text(actor, "id") + ")", "1"));
        if (resourceRows.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != resourceRows.Count) throw new FormatException("Reserved body resource identity collision");
        foreach (var resource in resourceRows) resources.Id(resource.Id);
        string Actor(JsonElement a) => "⟨" + nodeIds.Id(Text(a, "location")) + ", " + capabilities.Many(Names(a, "capabilities")) + ", "
            + nodeIds.Optional(a, "final_location") + ", " + facts.Optional(a, "contact_presence_fact") + ", " + capabilities.Many(Names(a, "contact_capabilities")) + "⟩";
        string Edge(JsonElement e) => "⟨" + nodeIds.Id(Text(e, "from")) + ", " + nodeIds.Id(Text(e, "to")) + ", " + Integer(e, "minimum_seconds")
            + ", " + facts.Many(Names(e, "requires")) + ", " + facts.Many(Names(e, "requires_absent")) + ", " + capabilities.Optional(e, "capability") + ", " + capabilities.Optional(e, "access_bypass_capability") + "⟩";
        string Action(JsonElement a)
        {
            var move = Text(a, "kind") == "move";
            var path = move && routes.TryGetValue(Text(a, "route"), out var route) ? Names(route, "edge_ids") : [];
            var reserved = Names(a, "resources").Concat(Names(a, "uses")).Concat(Names(a, "takes"))
                .Concat(Rows(a, "gives").Select(x => Text(x, "object")))
                .Concat(Rows(a, "places").Select(x => Text(x, "object")))
                .Append("@body(" + Text(a, "actor") + ")")
                .Concat(Rows(a, "gives").Select(x => "@body(" + Text(x, "to") + ")"));
            return "⟨" + actorIds.Id(Text(a, "actor")) + ", " + Integer(a, "start") + ", " + Integer(a, "end") + ", "
                + nodeIds.Id(Text(a, "from")) + ", " + nodeIds.Id(Text(a, "to")) + ", " + (move ? "true" : "false") + ", "
                + Integer(a, "minimum_seconds") + ", " + List(path.Select(edgeIds.Id)) + ", " + capabilities.Id(Text(a, "capability")) + ", "
                + string.Join(", ", new[] { "requires", "requires_absent", "requires_during", "requires_absent_during", "requires_end", "requires_absent_end", "adds", "removes" }.Select(key => facts.Many(Names(a, key))))
                + ", " + resources.Many(reserved) + "⟩";
        }
        if (history.TryGetProperty("projection", out var projection)) request = projection;
        var selected = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("events", out var requested)
            ? requested.EnumerateArray().Select(x => x.GetString()!).ToArray() : actions.Select(x => Text(x, "id")).ToArray();
        var scope = request.ValueKind == JsonValueKind.Object ? "projected-history-dependency-context" : "complete-declared-history";
        var source = new StringBuilder("import Std\nset_option maxRecDepth 100000\nset_option maxHeartbeats 0\nnamespace " + moduleName + "\n");
        source.Append(Kernel);
        source.AppendLine("def actors : List ActorData := " + List(actors.Select(Actor)));
        source.AppendLine("def edges : List EdgeData := " + List(edges.Select(Edge)));
        source.AppendLine("def actions : List ActionData := " + List(actions.Select(Action)));
        source.AppendLine("def capacities : List Nat := " + List(resourceRows.Select(x => x.Capacity)));
        source.AppendLine("def environment : List ChangeData := " + List(Rows(history, "environment").Select(x => "⟨" + Integer(x, "at") + ", " + facts.Many(Names(x, "adds")) + ", " + facts.Many(Names(x, "removes")) + "⟩")));
        source.AppendLine("def initialFacts : List Nat := " + facts.Many(Names(history, "initial_facts")));
        source.AppendLine("def finalFacts : List Nat := " + facts.Many(Names(history, "required_final_facts")));
        source.AppendLine("def starts : Int := " + Integer(history, "start"));
        source.AppendLine("def ends : Int := " + Integer(history, "end"));
        source.AppendLine("def nodeCount : Nat := " + Rows(history, "nodes").Length.ToString(CultureInfo.InvariantCulture));
        source.AppendLine("def times : List Int := " + List(actions.SelectMany(a => new[] { a.GetProperty("start").GetInt64(), a.GetProperty("end").GetInt64() })
            .Concat(Rows(history, "environment").Select(x => x.GetProperty("at").GetInt64())).Distinct().Order().Select(x => x.ToString(CultureInfo.InvariantCulture))));
        source.AppendLine("def timeGridValid : Bool := decide (times.Pairwise (fun a b => a < b)) && actions.all (fun a => times.contains a.start && times.contains a.finish) && environment.all (fun e => times.contains e.time)");
        source.AppendLine("def scheduleValid : Bool := timeGridValid && checkSchedule actors edges capacities nodeCount starts ends actions environment");
        source.AppendLine("def runResult : Bool × State := replay actors edges actions environment times ⟨actors.map (·.initialNode), initialFacts⟩");
        source.AppendLine("def finalValid : Bool := allPresent runResult.2.facts finalFacts && (actors.zip runResult.2.positions).all (fun p => match p.1.finalNode with | none => true | some n => p.2 == n)");
        if (rejectionTarget is null)
        {
            source.AppendLine("theorem schedule_checked : scheduleValid = true := by decide +kernel");
            source.AppendLine("theorem transitions_checked : runResult.1 = true := by decide +kernel");
            source.AppendLine("theorem final_state_checked : finalValid = true := by decide +kernel");
            source.AppendLine("#print axioms schedule_checked\n#print axioms transitions_checked\n#print axioms final_state_checked");
        }
        else
        {
            if (rejectionTarget is not ("scheduleValid" or "runResult.1" or "finalValid")) throw new ArgumentException("Unknown rejection obligation");
            source.AppendLine("theorem mutation_rejected : " + rejectionTarget + " = false := by decide +kernel");
            source.AppendLine("#print axioms mutation_rejected");
        }
        source.AppendLine("end " + moduleName);
        return new(source.ToString(), scope,
            ["declared-integer-time-intervals", "graph-edge-chain-connectivity-and-time", "actor-node-continuity", "body-and-resource-capacity-half-open-intervals", "capability-and-route-access", "world-start-during-end-preconditions", "atomic-world-add-remove-transitions", "declared-final-facts-and-locations"],
            ["DV-elaborator-correctness-and-operation-schema-binding", "subjective-information-and-memory", "Sim4-prediction-and-choice", "object-custody-transfer", "room-coordinates-contact-geometry-and-Godot-physics", "environment-causal-origin"],
            actors.Length, actions.Length, selected);
    }

    private const string Kernel = """
structure ActorData where
  initialNode : Nat
  capabilities : List Nat
  finalNode : Option Nat
  presence : Option Nat
  contactCapabilities : List Nat
structure EdgeData where
  origin : Nat
  destination : Nat
  seconds : Int
  required : List Nat
  absent : List Nat
  capability : Option Nat
  bypass : Option Nat
structure ActionData where
  actor : Nat
  start : Int
  finish : Int
  origin : Nat
  destination : Nat
  moving : Bool
  minimum : Int
  path : List Nat
  capability : Nat
  required : List Nat
  absent : List Nat
  during : List Nat
  duringAbsent : List Nat
  endRequired : List Nat
  endAbsent : List Nat
  adds : List Nat
  removes : List Nat
  resources : List Nat
structure ChangeData where
  time : Int
  adds : List Nat
  removes : List Nat
structure State where
  positions : List Nat
  facts : List Nat
structure Walk where
  node : Nat
  seconds : Int
  valid : Bool
def allPresent (facts required : List Nat) : Bool := required.all facts.contains
def allAbsent (facts absent : List Nat) : Bool := absent.all (fun f => !facts.contains f)
def intervalsOverlap (a b : ActionData) : Bool := decide (a.start < b.finish ∧ b.start < a.finish)
def walking (edges : List EdgeData) (a : ActionData) : Walk :=
  a.path.foldl (fun w id => match edges[id]? with
    | none => { w with valid := false }
    | some e => ⟨e.destination, w.seconds + e.seconds, w.valid && w.node == e.origin && decide (e.seconds > 0)⟩)
    ⟨a.origin, 0, true⟩
def optionalCapability (actor : ActorData) (capability : Option Nat) : Bool :=
  match capability with | none => true | some c => actor.capabilities.contains c
def routeOpen (edges : List EdgeData) (actor : ActorData) (facts : List Nat) (a : ActionData) : Bool :=
  a.path.all (fun id => match edges[id]? with
    | none => false
    | some e =>
      let bypass := match e.bypass with | none => false | some c => actor.capabilities.contains c
      optionalCapability actor e.capability && (bypass || allPresent facts e.required) && allAbsent facts e.absent)
def continuous (actors : List ActorData) (edges : List EdgeData) (s : State) (a : ActionData) : Bool :=
  match actors[a.actor]? with
  | none => false
  | some actor =>
    let presence := match actor.presence with
      | none => true
      | some f => !actor.contactCapabilities.contains a.capability || s.facts.contains f
    allPresent s.facts a.during && allAbsent s.facts a.duringAbsent && presence && (!a.moving || routeOpen edges actor s.facts a)
def startValid (actors : List ActorData) (edges : List EdgeData) (s : State) (a : ActionData) : Bool :=
  match actors[a.actor]?, s.positions[a.actor]? with
  | some actor, some position =>
    position == a.origin && actor.capabilities.contains a.capability &&
    allPresent s.facts a.required && allAbsent s.facts a.absent && continuous actors edges s a
  | _, _ => false
def checkSchedule (actors : List ActorData) (edges : List EdgeData) (capacities : List Nat)
    (nodeCount : Nat) (starts ends : Int) (actions : List ActionData) (changes : List ChangeData) : Bool :=
  decide (starts < ends) && actors.all (fun a => decide (a.initialNode < nodeCount)) &&
  edges.all (fun e => decide (e.origin < nodeCount ∧ e.destination < nodeCount ∧ 0 < e.seconds)) &&
  capacities.all (fun capacity => decide (0 < capacity)) &&
  changes.all (fun c => decide (starts ≤ c.time ∧ c.time ≤ ends)) &&
  actions.all (fun a =>
    let w := walking edges a
    decide (a.actor < actors.length ∧ a.origin < nodeCount ∧ a.destination < nodeCount ∧
      starts ≤ a.start ∧ a.start < a.finish ∧ a.finish ≤ ends ∧ 0 ≤ a.minimum ∧ a.minimum ≤ a.finish - a.start) &&
    (if a.moving then !a.path.isEmpty && w.valid && w.node == a.destination && decide (w.seconds ≤ a.finish - a.start)
     else a.origin == a.destination) &&
    a.resources.all (fun r => match capacities[r]? with | none => false | some cap => decide (0 < cap))) &&
  (actions.zipIdx).all (fun p => (actions.zipIdx).all (fun q =>
    p.2 == q.2 || !(intervalsOverlap p.1 q.1) || p.1.actor != q.1.actor)) &&
  actions.all (fun a => a.resources.all (fun r =>
    let occupied := actions.filter (fun b => decide (b.start ≤ a.start ∧ a.start < b.finish) && b.resources.contains r)
    match capacities[r]? with | none => false | some cap => decide (occupied.length ≤ cap)))
def tick (actors : List ActorData) (edges : List EdgeData) (actions : List ActionData)
    (changes : List ChangeData) (time : Int) (s : State) : Bool × State := Id.run do
  let ending := actions.filter (fun a => a.finish == time)
  let changing := changes.filter (fun c => c.time == time)
  let before := actions.all (fun a =>
    if decide (a.start < time ∧ time ≤ a.finish) then continuous actors edges s a else true)
  let endConditions := ending.all (fun a => allPresent s.facts a.endRequired && allAbsent s.facts a.endAbsent)
  let adds := (ending.flatMap (·.adds)) ++ (changing.flatMap (·.adds))
  let removes := (ending.flatMap (·.removes)) ++ (changing.flatMap (·.removes))
  let atomic := allAbsent adds removes
  let positions := ending.foldl (fun ps a => if a.moving then ps.mapIdx (fun i n => if i == a.actor then a.destination else n) else ps) s.positions
  let next : State := ⟨positions, (s.facts.filter (fun f => !removes.contains f)) ++ adds⟩
  let after := actions.all (fun a =>
    if decide (a.start < time ∧ time < a.finish) then continuous actors edges next a else true)
  let starting := actions.filter (fun a => a.start == time)
  let valid := before && endConditions && atomic && after && starting.all (startValid actors edges next)
  return (valid, next)
def replay (actors : List ActorData) (edges : List EdgeData) (actions : List ActionData)
    (changes : List ChangeData) (times : List Int) (initial : State) : Bool × State :=
  times.foldl (fun result time =>
    let next := tick actors edges actions changes time result.2
    (result.1 && next.1, next.2)) (true, initial)

""";
}
