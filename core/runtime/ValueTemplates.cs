using System.Globalization;
using System.Numerics;
using System.Text;
using System.Text.Json;
using DuelView.Dv;

namespace DuelView.Runtime;

/// <summary>
/// A finite, pure interpreter for authored dv-value-template declarations. The supplied
/// document is the entire catalog; loading files and committing world state are not its jobs.
/// JSON objects and ordered DV pair records are both accepted. List expressions remain lists.
/// </summary>
public sealed class ValueTemplates
{
    public const int MaximumTemplateNodes = 200_000;
    public const int MaximumEvaluationNodes = 1_000_000;
    public const int MaximumDepth = 128;
    public const int MaximumTextCharacters = 16_000_000;
    private readonly DvDocument document;
    private readonly Dictionary<string, Definition> definitions = new(StringComparer.Ordinal);
    private readonly Dictionary<(string Category, string Identity), JsonElement> catalog = [];
    private static readonly JsonSerializerOptions JsonOptions = new() { MaxDepth = MaximumDepth * 2 + 16 };
    private static readonly JsonElement Empty = JsonSerializer.SerializeToElement(System.Array.Empty<int>());
    private static readonly JsonElement False = JsonSerializer.SerializeToElement(false);

    public ValueTemplates(DvDocument document)
    {
        this.document = document ?? throw new ArgumentNullException(nameof(document));
        BuildCatalog();
        if (!document.Root.TryGetProperty("data", out var data)) return;
        foreach (var entry in data.EnumerateObject())
        {
            var value = Get(entry.Value, "value");
            if (RecordLike(value) && Find(value, "kind", False).ValueKind == JsonValueKind.String && Text(Find(value, "kind", False)) == "dv-value-template"
                || entry.Name.StartsWith("template.", StringComparison.Ordinal))
                definitions.Add(entry.Name, new Compiler(entry.Name).Compile(value));
        }
        foreach (var (id, definition) in definitions)
        {
            foreach (var dependency in definition.Data) _ = Get(document.Definition("data", dependency), "value");
            foreach (var (target, count) in definition.Calls)
                if (!definitions.TryGetValue(target, out var other) || other.Parameters.Length != count)
                    throw Error(id, "Unknown template or wrong argument count: " + target);
        }
        CheckCycles(definitions.ToDictionary(p => p.Key, p => p.Value.Calls.Select(c => c.Id).ToHashSet(StringComparer.Ordinal)), "templates");
    }

    public IReadOnlyCollection<string> Identities => definitions.Keys;

    /// <summary>Pure authored projections used by value.content, including item groups.</summary>
    public JsonElement Content(string category, string identity) => catalog.GetValueOrDefault((category, identity), False);

    private void BuildCatalog()
    {
        foreach (var category in document.Root.EnumerateObject())
            if (category.Value.ValueKind == JsonValueKind.Object)
                foreach (var entry in category.Value.EnumerateObject()) catalog.Add((category.Name, entry.Name), entry.Value);
        var groups = new Dictionary<string, List<JsonElement>>(StringComparer.Ordinal);
        if (document.Root.TryGetProperty("items", out var items)) foreach (var entry in items.EnumerateObject())
        {
            var item = entry.Value;
            var name = Get(item, "name"); var group = Text(Get(item, "group"));
            var layout = Content("layouts", group);
            var facets = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var facet in Get(item, "facets").EnumerateObject())
            {
                var fields = facet.Value.EnumerateObject().ToDictionary(p => p.Name, p => Cell(p.Value, Json(1), Json(0), Empty), StringComparer.Ordinal);
                if (facet.Name == "state")
                {
                    if (!fields.TryAdd("name", Cell(name, Json(1), Json(0), Empty))) throw new InvalidDataException("Item name has two sources: " + entry.Name);
                    if (layout.ValueKind == JsonValueKind.Object && TryFind(Get(layout, "items"), Json(entry.Name), out var location))
                        if (!fields.TryAdd("location", Cell(location, Json(1), Json(0), Empty))) throw new InvalidDataException("Item location has two sources: " + entry.Name);
                }
                facets.Add(facet.Name, Json(fields));
            }
            if (!facets.ContainsKey("state")) throw new InvalidDataException("Item needs state facets: " + entry.Name);
            var projected = RecordValue(("id", Json(entry.Name)), ("kind", Get(item, "kind")), ("facets", Json(facets)),
                ("map_kind", Get(item, "map_kind")), ("map_title", name), ("visible_fields", Get(item, "visible_fields")));
            catalog[("items", entry.Name)] = projected;
            if (!groups.TryGetValue(group, out var members)) groups.Add(group, members = []);
            members.Add(projected);
        }
        foreach (var (group, members) in groups) catalog[("groups", group)] = Array(members);
        if (document.Root.TryGetProperty("rules", out var rules)) foreach (var entry in rules.EnumerateObject())
            catalog[("rules", entry.Name)] = RecordValue(("name", Json(entry.Name)), ("version", Get(entry.Value, "version")),
                ("premise", Get(entry.Value, "premise")), ("effects", Get(entry.Value, "effects")));
        if (document.Root.TryGetProperty("characters", out var characters)) foreach (var entry in characters.EnumerateObject())
            catalog[("characters", entry.Name)] = RecordValue(("personality", With(Get(entry.Value, "personality"), Json("id"), Json(entry.Name))),
                ("obeys", Array(Items(Get(entry.Value, "obeys")).Select(v => With(v, Json("content_origin"), Json(document.Hash))))),
                ("name", Find(entry.Value, "name", Json(entry.Name))), ("autonomy", Find(entry.Value, "autonomy", False)));
        catalog[("meta", "hash")] = Json(document.Hash);
        catalog[("meta", "schema")] = Json(DvDocument.Schema);
    }

    public JsonElement Instantiate(string identity, params JsonElement[] arguments)
    {
        ArgumentException.ThrowIfNullOrEmpty(identity);
        ArgumentNullException.ThrowIfNull(arguments);
        return new Evaluation(this).Call(identity, arguments, 0);
    }

    /// <summary>
    /// Optional lowering at an assembly boundary. Nonempty unique text-key pair lists
    /// become JSON objects. Do not use before template evaluation: a pair list can also
    /// intentionally be an indexed list. Empty lists and duplicate-key records stay lists.
    /// </summary>
    public static JsonElement NormalizeRecords(JsonElement value) => Normalize(value, 0);
    private static JsonElement Normalize(JsonElement value, int depth)
    {
        if (depth > MaximumDepth) throw new InvalidDataException("Record normalization depth exceeded.");
        if (value.ValueKind == JsonValueKind.Object)
            return Json(value.EnumerateObject().ToDictionary(p => p.Name, p => Normalize(p.Value, depth + 1)));
        if (value.ValueKind != JsonValueKind.Array) return value;
        var items = value.EnumerateArray().ToArray();
        if (items.Length > 0 && items.All(p => p.ValueKind == JsonValueKind.Array && p.GetArrayLength() == 2 && p[0].ValueKind == JsonValueKind.String)
            && items.Select(p => Text(p[0])).Distinct(StringComparer.Ordinal).Count() == items.Length)
            return Json(items.ToDictionary(p => Text(p[0]), p => Normalize(p[1], depth + 1)));
        return Array(items.Select(p => Normalize(p, depth + 1)));
    }

    private sealed record Node(string Op, JsonElement Literal, string Name, Node[] Children, Dictionary<string, Node> Bindings);
    private sealed record Definition(string[] Parameters, Dictionary<string, Node> Bindings, Node[] Checks, Node Value,
        HashSet<string> Data, List<(string Id, int Count)> Calls);

    private sealed class Compiler(string id)
    {
        private int nodes;
        private HashSet<string> parameters = new(StringComparer.Ordinal);
        private readonly HashSet<string> bindingNames = new(StringComparer.Ordinal);
        private readonly HashSet<string> indexNames = new(StringComparer.Ordinal);
        private readonly Dictionary<string, HashSet<string>> dependencies = new(StringComparer.Ordinal);
        private readonly HashSet<string> data = new(StringComparer.Ordinal);
        private readonly List<(string Id, int Count)> calls = [];

        internal Definition Compile(JsonElement value)
        {
            var record = Record(value);
            Only(record, "kind", "parameters", "bindings", "checks", "value");
            if (Text(Required(record, "kind")) != "dv-value-template") throw Error(id, "Expected dv-value-template.");
            var names = Items(Required(record, "parameters")).Select(Text).ToArray();
            parameters = new(names, StringComparer.Ordinal);
            if (names.Length != parameters.Count || names.Any(string.IsNullOrEmpty)) throw Error(id, "Duplicate or empty parameter name.");
            var declared = Declare(Required(record, "bindings"));
            var scope = declared.Keys.ToHashSet(StringComparer.Ordinal);
            var indices = new HashSet<string>(StringComparer.Ordinal);
            var bindings = Bindings(declared, scope, indices, 0);
            var checks = record.TryGetValue("checks", out var check) ? Expressions(check, scope, indices, null, 0) : [];
            var result = Expression(Required(record, "value"), scope, indices, null, 0);
            CheckCycles(dependencies, id + " bindings");
            return new(names, bindings, checks, result, data, calls);
        }

        private Dictionary<string, JsonElement> Declare(JsonElement value)
        {
            var result = Record(value);
            foreach (var name in result.Keys)
            {
                if (name.Length == 0 || parameters.Contains(name) || indexNames.Contains(name) || !bindingNames.Add(name))
                    throw Error(id, "Binding names must be unique: " + name);
                dependencies.Add(name, new(StringComparer.Ordinal));
            }
            return result;
        }
        private Dictionary<string, Node> Bindings(Dictionary<string, JsonElement> declarations, HashSet<string> scope, HashSet<string> indices, int depth) =>
            declarations.ToDictionary(p => p.Key, p => Expression(p.Value, scope, indices, p.Key, depth), StringComparer.Ordinal);
        private Node[] Expressions(JsonElement values, HashSet<string> scope, HashSet<string> indices, string? owner, int depth) =>
            Items(values).Select(v => Expression(v, scope, indices, owner, depth)).ToArray();
        private Node Expression(JsonElement value, HashSet<string> scope, HashSet<string> indices, string? owner, int depth)
        {
            if (++nodes > MaximumTemplateNodes || depth > MaximumDepth) throw Error(id, "Template node or depth limit exceeded.");
            if (value.ValueKind is JsonValueKind.String or JsonValueKind.True or JsonValueKind.False ||
                value.ValueKind == JsonValueKind.Number && double.IsFinite(value.GetDouble())) return new("literal", value, "", [], []);
            var record = Record(value);
            var op = Text(Required(record, "$"));
            string Name(string key) { var name = Text(Required(record, key)); return name.Length > 0 ? name : throw Error(id, "Empty " + key); }
            Node Make(string name = "", Node[]? children = null, Dictionary<string, Node>? bindings = null) => new(op, default, name, children ?? [], bindings ?? []);
            switch (op)
            {
                case "param":
                case "value":
                case "index":
                    Only(record, "$", "name");
                    var name = Name("name");
                    if (!(op == "param" ? parameters : op == "value" ? scope : indices).Contains(name)) throw Error(id, "Name outside scope: " + name);
                    if (op == "value" && owner is not null) dependencies[owner].Add(name);
                    return Make(name);
                case "data":
                    Only(record, "$", "id", "copy");
                    _ = Bool(Required(record, "copy")); // JsonElement is immutable; both ownership requests are safe.
                    var target = Name("id"); data.Add(target); return Make(target);
                case "template":
                    Only(record, "$", "id", "args");
                    target = Name("id");
                    var args = Expressions(Required(record, "args"), scope, indices, owner, depth + 1);
                    calls.Add((target, args.Length)); return Make(target, args);
                case "list":
                    Only(record, "$", "items");
                    return Make(children: Expressions(Required(record, "items"), scope, indices, owner, depth + 1));
                case "expand":
                case "first":
                case "fold":
                    Only(record, op == "expand" ? ["$", "source", "index", "bindings", "value"] : op == "fold"
                        ? ["$", "source", "index", "accumulator", "seed", "bindings", "value"] : ["$", "source", "index", "bindings", "when", "value", "fallback"]);
                    var source = Expression(Required(record, "source"), scope, indices, owner, depth + 1);
                    var seed = op == "fold" ? Expression(Required(record, "seed"), scope, indices, owner, depth + 1) : null;
                    var index = Name("index");
                    if (parameters.Contains(index) || bindingNames.Contains(index) || !indexNames.Add(index)) throw Error(id, "Duplicate index: " + index);
                    var declared = Declare(Required(record, "bindings"));
                    var accumulator = op == "fold" ? Name("accumulator") : "";
                    if (op == "fold")
                    {
                        if (parameters.Contains(accumulator) || indexNames.Contains(accumulator) || !bindingNames.Add(accumulator)) throw Error(id, "Duplicate accumulator: " + accumulator);
                        dependencies.Add(accumulator, new(StringComparer.Ordinal));
                        declared.Add(accumulator, False);
                    }
                    var innerScope = new HashSet<string>(scope, StringComparer.Ordinal); innerScope.UnionWith(declared.Keys);
                    var innerIndices = new HashSet<string>(indices, StringComparer.Ordinal) { index };
                    var bindings = Bindings(declared, innerScope, innerIndices, depth + 1);
                    var body = Expression(Required(record, "value"), innerScope, innerIndices, owner, depth + 1);
                    if (op == "fold") return new(op, Json(accumulator), index, [source, seed!, body], bindings);
                    return op == "expand" ? Make(index, [source, body], bindings) : Make(index,
                        [source, Expression(Required(record, "when"), innerScope, innerIndices, owner, depth + 1), body,
                        Expression(Required(record, "fallback"), scope, indices, owner, depth + 1)], bindings);
                default:
                    Only(record, "$", "args");
                    var arity = op == "choose" ? 3 : Arity(op);
                    if (arity < 0) throw Error(id, "Unsupported operator: " + op);
                    args = Expressions(Required(record, "args"), scope, indices, owner, depth + 1);
                    if (args.Length != arity) throw Error(id, $"{op} requires {arity} arguments.");
                    return Make(children: args);
            }
        }
    }

    private sealed class Frame(Dictionary<string, JsonElement> parameters, Dictionary<string, Node> bindings, Frame? parent = null, string index = "", int position = 0)
    {
        internal readonly Dictionary<string, JsonElement> Parameters = parameters;
        internal readonly Dictionary<string, Node> Bindings = bindings;
        internal readonly Dictionary<string, JsonElement> Cache = new(StringComparer.Ordinal);
        internal readonly HashSet<string> Resolving = new(StringComparer.Ordinal);
        internal readonly Frame? Parent = parent;
        internal readonly string Index = index;
        internal readonly int Position = position;
    }

    private sealed class Evaluation(ValueTemplates templates)
    {
        private int remaining = MaximumEvaluationNodes;
        private long characters = MaximumTextCharacters;
        private readonly HashSet<string> active = new(StringComparer.Ordinal);
        // The document is immutable and every operator is pure. Shared no-argument
        // authored catalogs can be reused inside one evaluation without re-expanding them.
        private readonly Dictionary<string, JsonElement> constants = new(StringComparer.Ordinal);
        private void Spend(int depth, int cost = 1)
        {
            if (depth > MaximumDepth || cost < 0 || cost > remaining) throw new InvalidDataException("Value template evaluation node or depth limit exceeded.");
            remaining -= cost;
        }
        private JsonElement TextResult(string value)
        {
            if (value.Length > characters) throw new InvalidDataException("Value template text limit exceeded.");
            characters -= value.Length; return Json(value);
        }
        private JsonElement JoinText(IEnumerable<string> parts, int depth)
        {
            var builder = new StringBuilder();
            foreach (var part in parts)
            {
                Spend(depth);
                if ((long)builder.Length + part.Length > characters) throw new InvalidDataException("Value template text limit exceeded.");
                builder.Append(part);
            }
            return TextResult(builder.ToString());
        }
        internal JsonElement Call(string id, JsonElement[] args, int depth)
        {
            Spend(depth);
            if (!templates.definitions.TryGetValue(id, out var definition)) throw Error(id, "Missing template declaration.");
            if (args.Length != definition.Parameters.Length) throw Error(id, "Wrong argument count.");
            if (args.Any(a => a.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)) throw Error(id, "Null parameters are not DV values.");
            if (args.Length == 0 && constants.TryGetValue(id, out var constant)) return constant;
            if (!active.Add(id)) throw Error(id, "Cyclic template call.");
            try
            {
                var frame = new Frame(definition.Parameters.Zip(args).ToDictionary(p => p.First, p => p.Second, StringComparer.Ordinal), definition.Bindings);
                foreach (var check in definition.Checks) _ = Value(check, frame, depth + 1);
                var result = Value(definition.Value, frame, depth + 1);
                if (args.Length == 0) constants.Add(id, result);
                return result;
            }
            catch (InvalidDataException error) { throw Error(id, error.Message); }
            finally { active.Remove(id); }
        }
        private JsonElement Value(Node node, Frame frame, int depth)
        {
            Spend(depth);
            switch (node.Op)
            {
                case "literal": return node.Literal;
                case "param": return frame.Parameters[node.Name];
                case "value":
                    for (var owner = frame; owner is not null; owner = owner.Parent)
                    {
                        if (!owner.Bindings.TryGetValue(node.Name, out var expression)) continue;
                        if (owner.Cache.TryGetValue(node.Name, out var found)) return found;
                        if (!owner.Resolving.Add(node.Name)) throw new InvalidDataException("Cyclic binding: " + node.Name);
                        try { return owner.Cache[node.Name] = Value(expression, owner, depth + 1); }
                        finally { owner.Resolving.Remove(node.Name); }
                    }
                    throw new InvalidDataException("Missing binding: " + node.Name);
                case "index":
                    for (var owner = frame; owner is not null; owner = owner.Parent) if (owner.Index == node.Name) return Json(owner.Position);
                    throw new InvalidDataException("Missing index: " + node.Name);
                case "data": return Get(templates.document.Definition("data", node.Name), "value");
                case "template": return Call(node.Name, node.Children.Select(n => Value(n, frame, depth + 1)).ToArray(), depth + 1);
                case "choose": return Value(node.Children[Bool(Value(node.Children[0], frame, depth + 1)) ? 1 : 2], frame, depth + 1);
                case "list": return Array(node.Children.Select(n => Value(n, frame, depth + 1)));
                case "expand":
                case "first":
                case "fold":
                    var source = Items(Value(node.Children[0], frame, depth + 1)); Spend(depth, source.Length);
                    var result = new List<JsonElement>();
                    var accumulated = node.Op == "fold" ? Value(node.Children[1], frame, depth + 1) : default;
                    for (var i = 0; i < source.Length; i++)
                    {
                        var inner = new Frame(frame.Parameters, node.Bindings, frame, node.Name, i);
                        if (node.Op == "fold")
                        {
                            inner.Cache[Text(node.Literal)] = accumulated;
                            accumulated = Value(node.Children[2], inner, depth + 1);
                        }
                        else if (node.Op == "first")
                        {
                            if (Bool(Value(node.Children[1], inner, depth + 1))) return Value(node.Children[2], inner, depth + 1);
                        }
                        else
                        {
                            var expanded = Items(Value(node.Children[1], inner, depth + 1)); Spend(depth, expanded.Length); result.AddRange(expanded);
                        }
                    }
                    return node.Op == "fold" ? accumulated : node.Op == "first" ? Value(node.Children[3], frame, depth + 1) : Array(result);
                default: return Apply(node.Op, node.Children.Select(n => Value(n, frame, depth + 1)).ToArray(), depth);
            }
        }

        private JsonElement Apply(string op, JsonElement[] a, int depth)
        {
            switch (op)
            {
                case "value.add": case "value.sub": case "value.mul": case "value.div": return Arithmetic(op, a[0], a[1]);
                case "value.eq": return Json(ScalarEqual(a[0], a[1]));
                case "value.same": return Json(Same(a[0], a[1]));
                case "value.lt": return Json(Compare(a[0], a[1]) < 0);
                case "value.not": return Json(!Bool(a[0]));
                case "value.floor": return Json(Math.Floor(Number(a[0])));
                case "value.cat": return JoinText([Text(a[0]), Text(a[1])], depth);
                case "value.show": return TextResult(Show(a[0], depth + 1));
                case "value.count": return Json(Items(a[0]).Length);
                case "value.range":
                    var first = Index(a[0]); var end = Index(a[1]);
                    if (end < first) throw new InvalidDataException("Range end precedes its start.");
                    Spend(depth, end - first);
                    return Array(Enumerable.Range(first, end - first).Select(n => Json(n)));
                case "value.at": var items = Items(a[0]); var index = Index(a[1]); return index < items.Length ? items[index] : throw new InvalidDataException("List index outside its bounds.");
                case "value.length": return Json(Text(a[0]).Length);
                case "value.slice":
                    var text = Text(a[0]); var start = Index(a[1]); var count = Index(a[2]);
                    if (start > text.Length || count > text.Length - start) throw new InvalidDataException("Text slice outside its bounds.");
                    if (count > characters) throw new InvalidDataException("Value template text limit exceeded.");
                    return TextResult(text.Substring(start, count));
                case "value.is_text": return Json(a[0].ValueKind == JsonValueKind.String);
                case "value.is_list": return Json(a[0].ValueKind is JsonValueKind.Array or JsonValueKind.Object && !IsRational(a[0]));
                case "value.is_numeric_value": return Json(ExactNumber.TryRead(a[0], out _));
                case "value.content":
                    return templates.Content(Text(a[0]), Text(a[1]));
                case "value.text_join": return JoinText(Items(a[0]).Select(Text), depth);
                case "value.pair": case "value.single": case "value.list3": return Array(a);
                case "value.get": return Get(a[0], a[1]);
                case "value.find": return Find(a[0], a[1], a[2]);
                case "value.with": return With(a[0], a[1], a[2]);
                case "value.with_many": return WithMany(a[0], a[1]);
                case "value.without": return Without(a[0], a[1]);
                case "value.has": return Json(Items(a[0]).Any(v => Same(v, a[1])));
                case "value.has_key": return Json(TryFind(a[0], a[1], out _));
                case "value.clone": case "value.snapshot": case "value.copy": return a[0];
                case "value.append": return Array(Items(a[0]).Append(a[1]));
                case "value.min": return Compare(a[0], a[1]) < 0 ? a[0] : a[1];
                case "value.max": return Compare(a[0], a[1]) < 0 ? a[1] : a[0];
                case "value.and": return Bool(a[0]) ? a[1] : False;
                case "value.or": return Bool(a[0]) ? Json(true) : a[1];
                case "value.record_like": return Json(RecordLike(a[0]));
                case "value.require": return Bool(a[0]) ? Json(true) : throw new InvalidDataException(Text(a[1]));
                case "value.concat": var right = Items(a[1]); Spend(depth, right.Length); return Array(Items(a[0]).Concat(right));
                case "domain.ref": return RecordValue(("type", Json("ref")), ("object", a[0]), ("facet", a[1]), ("field", a[2]));
                case "domain.scoped_ref": return With(Apply("domain.ref", a[1..], depth + 1), Json("subject"), a[0]);
                case "domain.fact": return RecordValue(("op", Json("equals")), ("ref", a[0]), ("value", a[1]));
                case "domain.all": return RecordValue(("op", Json("all")), ("items", a[0]));
                case "domain.not": return RecordValue(("op", Json("not")), ("item", a[0]));
                case "domain.true": return RecordValue(("op", Json("constant")), ("value", Json("true")));
                case "domain.at_least": return RecordValue(("op", Json("at_least")), ("ref", a[0]), ("value", a[1]));
                case "domain.held_for":
                    if (Number(a[3]) < 0) throw new InvalidDataException("Held-for duration must be nonnegative.");
                    return RecordValue(("op", Json("held_for")), ("ref", a[0]), ("value", a[1]), ("clock", a[2]), ("duration", a[3]));
                case "domain.assign": case "domain.increment": return RecordValue(("op", Json(op[7..])), ("ref", a[0]), ("value", a[1]));
                case "domain.axiom": return RecordValue(("name", a[0]), ("version", a[1]), ("premise", a[2]), ("effects", a[3]));
                case "domain.contract": return With(Apply("domain.axiom", a[..4], depth + 1), Json("postcondition"), a[4]);
                case "domain.instance": return With(With(a[1], Json("schema"), Get(a[1], "name")), Json("name"), a[0]);
                case "domain.field": return Cell(a[0], Json(1), Json(0), Empty);
                case "domain.cell": return Cell(a[0], a[1], a[2], a[3]);
                case "domain.unknown": return Unknown();
                case "domain.object":
                    var kind = a[1].ValueKind == JsonValueKind.String && Text(a[1]) == "perceived" ? Unknown() : Cell(a[1], Json(1), Json(0), Empty);
                    var facets = With(a[2], Json("identity"), With(Find(a[2], "identity", Empty), Json("kind"), kind));
                    return RecordValue(("id", a[0]), ("kind", a[1]), ("facets", NormalizeRecords(facets)));
                case "domain.binding": return RecordValue(("physical", a[0]), ("local", a[1]), ("subject", a[2]));
                case "domain.criterion":
                    if (Text(a[2]) is not ("numeric" or "matches")) throw new InvalidDataException("Unsupported value criterion.");
                    return RecordValue(("id", a[0]), ("ref", a[1]), ("mode", a[2]), ("target", a[3]), ("weight", a[4]));
                case "domain.request": return RecordValue(("id", a[0]), ("requester", a[1]), ("self", a[2]));
                case "domain.person_policy":
                    ValidateExpressionPolicy(a[4]);
                    if (Number(a[2]) < 0 || Number(a[3]) < 0) throw new InvalidDataException("Negative policy cost.");
                    return RecordValue(("subject", a[0]), ("values", a[1]), ("effort_cost", a[2]), ("uncertainty_cost", a[3]), ("expression", a[4]));
                case "domain.compose": return SceneComposer.Materialize(a[0]);
                case "domain.read": return Read(a[0], a[1]);
                case "domain.truth": return Truth(a[0], a[1], depth + 1);
                case "domain.uncontested": return Json(Uncontested(a[0]));
                case "domain.surface_parts": return RecordValue(("format", Json("surface-parts-v1")), ("parts", a[0]));
                case "domain.any_chain":
                    var conditions = Items(a[1]); Spend(depth, conditions.Length); var result = a[0];
                    foreach (var condition in conditions) result = Apply("domain.not", [Apply("domain.all", [Array([Apply("domain.not", [result], depth), Apply("domain.not", [condition], depth)])], depth)], depth);
                    return result;
                default: throw new InvalidDataException("Unsupported operator: " + op);
            }
        }

        private string Show(JsonElement value, int depth)
        {
            var builder = new StringBuilder();
            void Append(string text)
            {
                if ((long)builder.Length + text.Length > characters) throw new InvalidDataException("Value template text limit exceeded.");
                builder.Append(text);
            }
            void Visit(JsonElement item, int level)
            {
                Spend(level);
                if (item.ValueKind == JsonValueKind.String) Append(Text(item));
                else if (item.ValueKind is JsonValueKind.True or JsonValueKind.False) Append(Bool(item) ? "true" : "false");
                else if (IsRational(item)) Append(Text(Get(item, "$dv_rational")));
                else if (item.ValueKind == JsonValueKind.Number) Append(item.GetDouble().ToString("R", CultureInfo.InvariantCulture));
                else
                {
                    Append("["); var items = Items(item);
                    for (var i = 0; i < items.Length; i++) { if (i > 0) Append(", "); Visit(items[i], level + 1); }
                    Append("]");
                }
            }
            Visit(value, depth);
            return builder.ToString();
        }
        private JsonElement Truth(JsonElement world, JsonElement proposition, int depth)
        {
            Spend(depth);
            var op = Text(Get(proposition, "op"));
            if (op == "constant") return Get(proposition, "value");
            if (op == "not") return Json(Text(Truth(world, Get(proposition, "item"), depth + 1)) switch { "unknown" => "unknown", "true" => "false", _ => "true" });
            if (op == "all")
            {
                var result = "true";
                foreach (var item in Items(Get(proposition, "items")))
                {
                    var truth = Text(Truth(world, item, depth + 1));
                    if (truth == "false") return Json("false");
                    if (truth == "unknown") result = "unknown";
                }
                return Json(result);
            }
            var cell = Read(world, Get(proposition, "ref"));
            if (!Uncontested(cell)) return Json("unknown");
            var actual = Get(cell, "value"); var expected = Get(proposition, "value");
            if (op == "equals") return Json(Same(actual, expected) ? "true" : "false");
            if (op == "at_least") return Json(Compare(actual, expected) >= 0 ? "true" : "false");
            if (op != "held_for") throw new InvalidDataException("Unknown proposition operator: " + op);
            if (!Same(actual, expected)) return Json("false");
            var clock = Read(world, Get(proposition, "clock"));
            if (!Uncontested(clock) || !ExactNumber.TryRead(Get(clock, "value"), out _) || !ExactNumber.TryRead(Get(cell, "time"), out _)) return Json("unknown");
            return Json(Compare(Get(clock, "value"), Arithmetic("value.add", Get(cell, "time"), Get(proposition, "duration"))) >= 0 ? "true" : "false");
        }
    }

    private static JsonElement Read(JsonElement world, JsonElement reference)
    {
        var scope = Find(reference, "subject", Json(""));
        if (!ScalarEqual(scope, Json("")) && !ScalarEqual(scope, Get(world, "subject"))) throw new InvalidDataException("Cross-subject reference access.");
        var identity = Get(reference, "object");
        if (ScalarEqual(Get(world, "domain"), Json("mind")) &&
            Items(Find(Find(world, "CognitionFilter", Empty), "hidden_objects", Empty)).Any(v => Same(v, identity))) return Unknown();
        if (!TryFind(Get(world, "objects"), identity, out var obj)) return Unknown();
        if (!TryFind(Get(obj, "facets"), Get(reference, "facet"), out var facet)) return Unknown();
        return Find(facet, Get(reference, "field"), Unknown());
    }
    private static bool Uncontested(JsonElement cell) => Bool(Get(cell, "known")) && !Bool(Get(cell, "conflicted"));
    private static JsonElement Unknown() => RecordValue(("known", False), ("value", False), ("confidence", Json(0)), ("time", Json(-1)), ("claims", Empty), ("conflicted", False));
    private static JsonElement Cell(JsonElement value, JsonElement confidence, JsonElement time, JsonElement basis)
    {
        var weight = Number(confidence);
        if (weight < 0 || weight > 1) throw new InvalidDataException("Expected weight in [0,1].");
        return RecordValue(("known", Json(true)), ("value", value), ("confidence", confidence), ("time", time), ("claims", Empty), ("basis", basis), ("conflicted", False));
    }
    private static void ValidateExpressionPolicy(JsonElement policy)
    {
        if (!RecordLike(policy)) throw new InvalidDataException("Expression policy must be a record.");
        foreach (var axis in Items(policy))
        {
            _ = Text(axis[0]);
            if (!RecordLike(axis[1])) throw new InvalidDataException("Expression policy weights must be a record.");
            foreach (var weight in Items(axis[1])) { _ = Text(weight[0]); _ = Number(weight[1]); }
        }
    }

    private static JsonElement Json<T>(T value) => JsonSerializer.SerializeToElement(value, JsonOptions);
    private static JsonElement Array(IEnumerable<JsonElement> values) => Json(values.ToArray());
    private static JsonElement RecordValue(params (string Key, JsonElement Value)[] fields) => Json(fields.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal));
    private static JsonElement[] Items(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Array => value.EnumerateArray().ToArray(),
        JsonValueKind.Object when !IsRational(value) => value.EnumerateObject().Select(p => Array([Json(p.Name), p.Value])).ToArray(),
        _ => throw new InvalidDataException("Expected a DV list or record.")
    };
    private static bool RecordLike(JsonElement value) => value.ValueKind == JsonValueKind.Object && !IsRational(value) ||
        value.ValueKind == JsonValueKind.Array && value.EnumerateArray().All(p => p.ValueKind == JsonValueKind.Array && p.GetArrayLength() == 2);
    private static Dictionary<string, JsonElement> Record(JsonElement value)
    {
        var result = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        var items = Items(value);
        if (items.Length > MaximumTemplateNodes) throw new InvalidDataException("Template record size exceeded.");
        foreach (var pair in items)
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2 || !result.TryAdd(Text(pair[0]), pair[1]))
                throw new InvalidDataException("Expected unique text-keyed record entries.");
        return result;
    }
    private static bool TryFind(JsonElement record, JsonElement key, out JsonElement value)
    {
        if (record.ValueKind == JsonValueKind.Object && key.ValueKind == JsonValueKind.String) return record.TryGetProperty(Text(key), out value);
        if (record.ValueKind == JsonValueKind.Array)
        {
            for (var i = record.GetArrayLength() - 1; i >= 0; i--)
            {
                var pair = record[i];
                if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2) throw new InvalidDataException("Malformed DV record entry.");
                if (ScalarEqual(pair[0], key)) { value = pair[1]; return true; }
            }
        }
        else if (record.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected a DV record.");
        value = default; return false;
    }
    private static JsonElement Get(JsonElement value, string key) => Get(value, Json(key));
    private static JsonElement Get(JsonElement value, JsonElement key) => TryFind(value, key, out var found) ? found : throw new InvalidDataException("Missing field: " + key);
    private static JsonElement Find(JsonElement value, string key, JsonElement fallback) => Find(value, Json(key), fallback);
    private static JsonElement Find(JsonElement value, JsonElement key, JsonElement fallback) => TryFind(value, key, out var found) ? found : fallback;
    private static JsonElement With(JsonElement record, JsonElement key, JsonElement value)
    {
        var entries = Items(record).ToList();
        var found = false;
        for (var i = 0; i < entries.Count; i++)
        {
            var pair = entries[i];
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2) throw new InvalidDataException("Malformed DV record entry.");
            if (!found && ScalarEqual(pair[0], key)) { entries[i] = Array([key, value]); found = true; }
        }
        if (!found) entries.Add(Array([key, value]));
        return record.ValueKind == JsonValueKind.Object && key.ValueKind == JsonValueKind.String
            ? Json(entries.ToDictionary(p => Text(p[0]), p => p[1], StringComparer.Ordinal)) : Array(entries);
    }
    private static JsonElement WithMany(JsonElement record, JsonElement updates)
    {
        var changes = Items(updates);
        if (changes.Length == 0) return record;
        var entries = Items(record).ToList();
        var present = new List<JsonElement>();
        for (var i = 0; i < entries.Count; i++)
        {
            var pair = entries[i];
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2) throw new InvalidDataException("Malformed DV record entry.");
            present.Add(pair[0]);
            if (TryFind(updates, pair[0], out var next)) entries[i] = Array([pair[0], next]);
        }
        foreach (var pair in changes)
        {
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() != 2) throw new InvalidDataException("Malformed DV update entry.");
            if (present.Any(p => Same(p, pair[0]))) continue;
            present.Add(pair[0]); entries.Add(Array([pair[0], Get(updates, pair[0])]));
        }
        return record.ValueKind == JsonValueKind.Object && entries.All(p => p[0].ValueKind == JsonValueKind.String)
            ? Json(entries.ToDictionary(p => Text(p[0]), p => p[1], StringComparer.Ordinal)) : Array(entries);
    }
    private static JsonElement Without(JsonElement record, JsonElement key)
    {
        var entries = Items(record).Where(p => !ScalarEqual(p[0], key)).ToArray();
        return record.ValueKind == JsonValueKind.Object ? Json(entries.ToDictionary(p => Text(p[0]), p => p[1], StringComparer.Ordinal)) : Array(entries);
    }
    private static string Text(JsonElement value) => value.ValueKind == JsonValueKind.String ? value.GetString()! : throw new InvalidDataException("Expected Text.");
    private static bool Bool(JsonElement value) => value.ValueKind switch { JsonValueKind.True => true, JsonValueKind.False => false, _ => throw new InvalidDataException("Expected Bool.") };
    private static bool IsRational(JsonElement value) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty("$dv_rational", out _);
    private static double Number(JsonElement value)
    {
        if (!ExactNumber.TryRead(value, out var number)) throw new InvalidDataException("Expected finite Number.");
        var result = value.ValueKind == JsonValueKind.Number ? value.GetDouble() : (double)number.Numerator / (double)number.Denominator;
        return double.IsFinite(result) ? result : throw new InvalidDataException("Expected finite Number.");
    }
    private static int Index(JsonElement value)
    {
        var number = Number(value);
        return number >= 0 && number <= int.MaxValue && number == Math.Truncate(number) ? (int)number : throw new InvalidDataException("Invalid index.");
    }
    private static int Compare(JsonElement left, JsonElement right)
    {
        if (!ExactNumber.TryRead(left, out var a) || !ExactNumber.TryRead(right, out var b)) throw new InvalidDataException("Expected numeric comparison operands.");
        return IsRational(left) || IsRational(right) ? a.CompareTo(b) : Number(left).CompareTo(Number(right));
    }
    private static JsonElement Arithmetic(string op, JsonElement left, JsonElement right)
    {
        if (IsRational(left) || IsRational(right))
        {
            if (!ExactNumber.TryRead(left, out var a) || !ExactNumber.TryRead(right, out var b)) throw new InvalidDataException("Expected numeric operands.");
            return (op switch
            {
                "value.add" => a.Add(b),
                "value.sub" => new ExactNumber(a.Numerator * b.Denominator - b.Numerator * a.Denominator, a.Denominator * b.Denominator),
                "value.mul" => new ExactNumber(a.Numerator * b.Numerator, a.Denominator * b.Denominator),
                _ => new ExactNumber(a.Numerator * b.Denominator, a.Denominator * b.Numerator)
            }).Json();
        }
        var x = Number(left); var y = Number(right);
        var result = op switch { "value.add" => x + y, "value.sub" => x - y, "value.mul" => x * y, _ => x / y };
        return double.IsFinite(result) ? Json(result) : throw new InvalidDataException("Nonfinite arithmetic result.");
    }
    private static bool ScalarEqual(JsonElement left, JsonElement right) =>
        left.ValueKind is JsonValueKind.Object or JsonValueKind.Array && !IsRational(left) || right.ValueKind is JsonValueKind.Object or JsonValueKind.Array && !IsRational(right)
            ? left.Equals(right) : Same(left, right);
    private static bool Same(JsonElement left, JsonElement right)
    {
        if (ExactNumber.TryRead(left, out var a) && ExactNumber.TryRead(right, out var b))
            return IsRational(left) || IsRational(right) ? a == b : Number(left) == Number(right);
        if (left.ValueKind is JsonValueKind.Object or JsonValueKind.Array && right.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
        {
            var l = Items(left); var r = Items(right);
            return l.Length == r.Length && l.Zip(r).All(p => Same(p.First, p.Second));
        }
        return left.ValueKind == right.ValueKind && left.ValueKind switch
        { JsonValueKind.String => Text(left) == Text(right), JsonValueKind.True or JsonValueKind.False => true, _ => false };
    }
    private static JsonElement Required(Dictionary<string, JsonElement> record, string key) => record.TryGetValue(key, out var value) ? value : throw new InvalidDataException("Missing template field: " + key);
    private static void Only(Dictionary<string, JsonElement> record, params string[] names)
    {
        foreach (var key in record.Keys) if (!names.Contains(key, StringComparer.Ordinal)) throw new InvalidDataException("Unsupported template field: " + key);
    }
    private static void CheckCycles(Dictionary<string, HashSet<string>> graph, string label)
    {
        var visiting = new HashSet<string>(StringComparer.Ordinal); var done = new HashSet<string>(StringComparer.Ordinal);
        void Visit(string name, int depth)
        {
            if (depth > MaximumDepth) throw new InvalidDataException("Template dependency depth exceeded: " + label);
            if (done.Contains(name)) return;
            if (!visiting.Add(name)) throw new InvalidDataException("Cyclic template dependency: " + label + "/" + name);
            if (!graph.TryGetValue(name, out var children)) throw new InvalidDataException("Unknown template dependency: " + name);
            foreach (var child in children) Visit(child, depth + 1);
            visiting.Remove(name); done.Add(name);
        }
        foreach (var name in graph.Keys) Visit(name, 0);
    }
    private static InvalidDataException Error(string id, string message) => new("Value template '" + id + "': " + message);
    private static int Arity(string op) => op switch
    {
        "domain.true" or "domain.unknown" => 0,
        "value.not" or "value.floor" or "value.show" or "value.count" or "value.length" or "value.is_text" or "value.is_list" or "value.is_numeric_value" or "value.text_join"
            or "value.single" or "value.clone" or "value.record_like" or "value.snapshot" or "value.copy" or "domain.all" or "domain.not" or "domain.field" or "domain.uncontested" or "domain.surface_parts" or "domain.compose" => 1,
        "value.add" or "value.sub" or "value.mul" or "value.div" or "value.eq" or "value.lt" or "value.cat" or "value.at" or "value.content" or "value.pair" or "value.get" or "value.with_many" or "value.without"
            or "value.has" or "value.has_key" or "value.same" or "value.append" or "value.min" or "value.max" or "value.and" or "value.or" or "value.require" or "value.concat" or "domain.fact" or "domain.at_least"
            or "domain.assign" or "domain.increment" or "domain.instance" or "domain.read" or "domain.truth" or "domain.any_chain" or "value.range" => 2,
        "value.slice" or "value.list3" or "value.find" or "value.with" or "domain.ref" or "domain.object" or "domain.binding" or "domain.request" => 3,
        "domain.scoped_ref" or "domain.held_for" or "domain.axiom" or "domain.cell" => 4,
        "domain.contract" or "domain.criterion" or "domain.person_policy" => 5,
        _ => -1
    };
}
