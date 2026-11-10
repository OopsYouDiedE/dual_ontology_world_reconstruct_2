using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

/// <summary>
/// Builds a new scene from a finite DV declaration. This is initialization only;
/// live state, evidence updates, scheduling and reloading belong to the session.
/// All identities, fields, rules, modes, initial cells and evidence come from DV.
/// </summary>
public sealed class SceneComposer(ValueTemplates templates)
{
    private static readonly JsonSerializerOptions Options = new() { MaxDepth = ValueTemplates.MaximumDepth * 2 + 16 };

    public JsonElement Compose(string template, params JsonElement[] arguments) => Materialize(templates.Instantiate(template, arguments));

    public static JsonElement Materialize(JsonElement declaration)
    {
        var nodes = ValueTemplates.MaximumEvaluationNodes;
        return JsonSerializer.SerializeToElement(Visit(ValueTemplates.NormalizeRecords(declaration), 0, ref nodes), Options);
    }

    private static JsonNode? Visit(JsonElement value, int depth, ref int nodes)
    {
        if (depth > ValueTemplates.MaximumDepth || --nodes < 0) throw new InvalidDataException("Scene composition budget exceeded.");
        if (value.ValueKind == JsonValueKind.Array)
        {
            var result = new JsonArray();
            foreach (var item in value.EnumerateArray()) result.Add(Visit(item, depth + 1, ref nodes));
            return result;
        }
        if (value.ValueKind != JsonValueKind.Object) return JsonNode.Parse(value.GetRawText());
        var record = new JsonObject();
        foreach (var property in value.EnumerateObject()) record.Add(property.Name, Visit(property.Value, depth + 1, ref nodes));
        return record["format"]?.GetValueKind() == JsonValueKind.String && record["format"]!.GetValue<string>() is "dv-world-composition" or "dv-world-extension"
            ? World(record) : record;
    }

    private static JsonObject World(JsonObject declaration)
    {
        var extends = Text(declaration, "format") == "dv-world-extension";
        var original = extends ? declaration["base"] as JsonObject ?? throw new InvalidDataException("World extension needs a base world.") : declaration;
        var id = Text(original, "id"); var domain = Text(original, "domain"); var subject = Text(original, "subject");
        if (id.Length == 0 || domain is not ("physical" or "mind") || (domain == "physical" ? subject.Length != 0 : subject.Length == 0))
            throw new InvalidDataException("Invalid world identity, domain or subject.");
        var objects = extends ? (JsonObject)(original["objects"]?.DeepClone() ?? throw new InvalidDataException("Base world needs objects.")) : new JsonObject();
        var addedObjects = 0;
        foreach (var item in extends && declaration["objects"] is null ? new JsonArray() : List(declaration, "objects"))
        {
            var obj = item as JsonObject ?? throw new InvalidDataException("World objects must be records.");
            var identity = Text(obj, "id");
            if (identity.Length == 0 || objects.ContainsKey(identity)) throw new InvalidDataException("Duplicate or empty object identity: " + identity);
            if (obj["facets"] is JsonArray empty && empty.Count == 0) obj["facets"] = new JsonObject();
            if (obj["facets"] is not JsonObject) throw new InvalidDataException("Object facets must be a record: " + identity);
            objects.Add(identity, obj.DeepClone());
            addedObjects++;
        }
        if (declaration["objects_if_missing"] is JsonArray optional)
            foreach (var item in optional)
            {
                var obj = item as JsonObject ?? throw new InvalidDataException("Optional objects must be records.");
                var identity = Text(obj, "id");
                if (identity.Length == 0) throw new InvalidDataException("Optional object needs an identity.");
                if (objects.ContainsKey(identity)) continue;
                if (obj["facets"] is not JsonObject) throw new InvalidDataException("Optional object facets must be a record.");
                objects.Add(identity, obj.DeepClone()); addedObjects++;
            }
        foreach (var item in List(declaration, "writes"))
        {
            var write = item as JsonObject ?? throw new InvalidDataException("Initial writes must be records.");
            var reference = write["ref"] as JsonObject ?? throw new InvalidDataException("Initial write needs a reference.");
            var scope = reference["subject"]?.GetValue<string>() ?? "";
            if (scope.Length > 0 && scope != subject) throw new InvalidDataException("Cross-subject initial write.");
            if (Text(reference, "type") != "ref") throw new InvalidDataException("Initial write needs a field reference.");
            var identity = Text(reference, "object"); var facet = Text(reference, "facet"); var field = Text(reference, "field");
            if (facet.Length == 0 || field.Length == 0 || objects[identity] is not JsonObject obj) throw new InvalidDataException("Initial write targets an unknown object or field.");
            var facets = (JsonObject)obj["facets"]!;
            if (facets[facet] is JsonArray empty && empty.Count == 0) facets[facet] = new JsonObject();
            if (facets[facet] is null) facets[facet] = new JsonObject();
            var fields = facets[facet] as JsonObject ?? throw new InvalidDataException("Initial facet must be a record.");
            var cell = write["cell"] as JsonObject ?? throw new InvalidDataException("Initial write needs a cell.");
            ValidateCell(cell);
            fields[field] = cell.DeepClone();
        }
        var adoptions = extends ? (JsonObject)(original["adoptions"]?.DeepClone() ?? throw new InvalidDataException("Base world needs adoptions.")) : new JsonObject();
        var addedAdoptions = 0;
        foreach (var item in List(declaration, "adoptions"))
        {
            var adoption = item as JsonObject ?? throw new InvalidDataException("Adoption must be a record.");
            var law = adoption["law"] as JsonObject ?? throw new InvalidDataException("Adoption needs a law.");
            var name = Text(law, "name"); var mode = Text(adoption, "mode");
            var confidence = adoption["confidence"]?.GetValue<double>() ?? throw new InvalidDataException("Adoption needs confidence.");
            if (!double.IsFinite(confidence) || confidence < 0 || confidence > 1 || domain == "physical" && confidence != 1)
                throw new InvalidDataException("Invalid adoption confidence: " + name);
            if (domain == "physical" ? mode != "enforce" : mode is not ("predict" or "infer" or "norm")) throw new InvalidDataException("Adoption mode does not match domain.");
            if (adoption["basis"] is not JsonArray basis || basis.Count == 0) throw new InvalidDataException("Adoption needs evidence: " + name);
            if (name.Length == 0 || adoptions.ContainsKey(name)) throw new InvalidDataException("Duplicate or empty law instance: " + name);
            var copy = (JsonObject)adoption.DeepClone(); copy["active"] = true;
            adoptions.Add(name, copy);
            addedAdoptions++;
        }
        var result = (JsonObject)original.DeepClone();
        result.Remove("format"); result.Remove("writes"); result.Remove("objects_if_missing");
        result["objects"] = objects; result["adoptions"] = adoptions;
        result["revision"] = (extends ? original["revision"]?.GetValue<long>() ?? 0 : 0) + addedObjects + addedAdoptions;
        if (!extends) { result["history"] = new JsonArray(); result["seen"] = new JsonArray(); }
        if (declaration["fields"] is JsonObject extra)
            foreach (var (key, value) in extra)
            {
                if (key is "id" or "domain" or "subject" or "objects" or "adoptions" or "revision" or "format" or "base" or "writes")
                    throw new InvalidDataException("World fields cannot replace composition-owned field: " + key);
                result[key] = value?.DeepClone();
            }
        return result;
    }

    private static void ValidateCell(JsonObject cell)
    {
        _ = cell["known"]?.GetValue<bool>() ?? throw new InvalidDataException("Cell needs known flag.");
        _ = cell["conflicted"]?.GetValue<bool>() ?? throw new InvalidDataException("Cell needs conflict flag.");
        var confidence = cell["confidence"]?.GetValue<double>() ?? throw new InvalidDataException("Cell needs confidence.");
        if (!double.IsFinite(confidence) || confidence < 0 || confidence > 1 || cell["value"] is null)
            throw new InvalidDataException("Invalid initial cell.");
    }
    private static string Text(JsonObject value, string key) => value[key]?.GetValue<string>() ?? throw new InvalidDataException("Missing Text field: " + key);
    private static JsonArray List(JsonObject value, string key) => value[key] as JsonArray ?? throw new InvalidDataException("Missing list field: " + key);
}
