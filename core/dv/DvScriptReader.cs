using System.Globalization;
using System.Text.Json;

namespace DuelView.Dv;

/// <summary>Bounded, data-only DV content syntax. Implemented in C#, never self-hosted.</summary>
public sealed class DvScriptReader(string source)
{
    private int position, nodes;

    public static JsonElement Parse(string source) => new DvScriptReader(source).Read();

    private JsonElement Read()
    {
        var root = new Dictionary<string, object>(StringComparer.Ordinal)
        {
            ["data"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["narratives"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["profiles"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["items"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["rules"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["characters"] = new Dictionary<string, object>(StringComparer.Ordinal),
            ["layouts"] = new Dictionary<string, object>(StringComparer.Ordinal)
        };
        while (!End())
        {
            var declaration = Identifier();
            if (declaration == "schema")
            {
                if (root.ContainsKey("schema")) throw Error("Duplicate schema declaration");
                root["schema"] = Value(0);
            }
            else
            {
                if (declaration == "history")
                {
                    var historyName = Identifier();
                    var body = HistoryBody();
                    var data = (Dictionary<string, object>)root["data"];
                    if (!data.TryAdd("case_history", HistoryScriptReader.Elaborate(body, historyName))) throw Error("Duplicate history");
                    data.TryAdd("case_theory", new Dictionary<string, object> { ["scopes"] = new object[0], ["audit"] = new object[0] });
                    Separator();
                    continue;
                }
                var category = declaration switch
                {
                    "data" or "数据" => "data",
                    "narrative" or "叙述" => "narratives", "profile" or "认知" => "profiles",
                    "item" or "物品" => "items", "rule" or "规则" => "rules",
                    "character" or "人物" => "characters", "layout" or "布置" => "layouts",
                    _ => throw Error("Expected schema, data, item, character, rule, layout, narrative or profile declaration")
                };
                Skip();
                var id = Peek() == '"' ? Text() : Identifier();
                var definitions = (Dictionary<string, object>)root[category];
                if (!definitions.TryAdd(id, Mapping(1))) throw Error("Duplicate " + declaration + " identity: " + id);
            }
            Separator();
        }
        if (!root.ContainsKey("schema")) throw Error("Missing schema declaration");
        return JsonSerializer.SerializeToElement(root, new JsonSerializerOptions { MaxDepth = 256 });
    }

    private string HistoryBody()
    {
        Expect('{'); var start = position; var depth = 1; var quoted = false;
        while (position < source.Length)
        {
            var c = source[position++];
            if (quoted && c == '\\') { if (position < source.Length) position++; continue; }
            if (c == '"') quoted = !quoted;
            if (quoted) continue;
            if (c == '{') depth++;
            if (c == '}' && --depth == 0) return source[start..(position - 1)];
        }
        throw Error("Unterminated history");
    }

    private Dictionary<string, object> Mapping(int depth)
    {
        Budget(depth);
        Expect('{');
        var result = new Dictionary<string, object>(StringComparer.Ordinal);
        while (!Take('}'))
        {
            Skip();
            var name = Peek() == '"' ? Text() : Identifier();
            if (!Take('=') && !Take(':')) throw Error("Expected '=' after field name");
            if (!result.TryAdd(name, Value(depth))) throw Error("Duplicate field: " + name);
            Separator();
        }
        return result;
    }

    private object Value(int depth)
    {
        Budget(depth);
        Skip();
        var first = Peek();
        if (first == '"') return Text();
        if (first == '{') return Mapping(depth + 1);
        if (first == '[')
        {
            Budget(depth + 1);
            position++;
            var values = new List<object>();
            while (!Take(']')) { values.Add(Value(depth + 1)); Separator(); }
            return values;
        }
        if (first == '-' || char.IsAsciiDigit(first))
        {
            var start = position++;
            while (position < source.Length && (char.IsAsciiDigit(source[position]) || source[position] is '.' or 'e' or 'E' or '+' or '-')) position++;
            if (!double.TryParse(source[start..position], NumberStyles.Float, CultureInfo.InvariantCulture, out var number) || !double.IsFinite(number))
                throw Error("Expected a finite number");
            return number;
        }
        var symbol = Identifier();
        if (symbol == "true") return true;
        if (symbol == "false") return false;
        if (!Take('(')) throw Error("Text values must be quoted; unknown literal: " + symbol);
        var arguments = new List<object>();
        while (!Take(')')) { arguments.Add(Value(depth + 1)); Separator(); }
        return Call(symbol, arguments);
    }

    private object Call(string name, List<object> arguments)
    {
        Dictionary<string, object> Record(params (string Key, object Value)[] fields) => fields.ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
        void Arity(int count) { if (arguments.Count != count) throw Error(name + " expects " + count + " arguments"); }
        switch (name)
        {
            case "ref":
                Arity(3); return Record(("type", "ref"), ("object", arguments[0]), ("facet", arguments[1]), ("field", arguments[2]));
            case "eq": case "at_least":
                Arity(2); return Record(("op", name == "eq" ? "equals" : name), ("ref", arguments[0]), ("value", arguments[1]));
            case "all": return Record(("op", "all"), ("items", arguments));
            case "not": Arity(1); return Record(("op", "not"), ("item", arguments[0]));
            case "assign": case "increment":
                Arity(2); return Record(("op", name), ("ref", arguments[0]), ("value", arguments[1]));
            case "truth": Arity(1); return Record(("op", "constant"), ("value", arguments[0]));
            case "rational": Arity(1); return Record(("$dv_rational", arguments[0]));
            default: throw Error("Unknown DV content operator: " + name);
        }
    }

    private string Identifier()
    {
        Skip();
        var start = position;
        if (position >= source.Length || !(char.IsLetter(source[position]) || source[position] == '_')) throw Error("Expected an identifier");
        position++;
        while (position < source.Length && (char.IsLetterOrDigit(source[position]) || source[position] is '_' or '.' or '-')) position++;
        return source[start..position];
    }

    private string Text()
    {
        Skip();
        var start = position;
        Expect('"');
        while (position < source.Length)
        {
            var next = source[position++];
            if (next == '\\') { if (position < source.Length) position++; }
            else if (next == '"')
            {
                try { return JsonSerializer.Deserialize<string>(source[start..position])!; }
                catch (JsonException) { throw Error("Invalid text escape"); }
            }
        }
        throw Error("Unterminated text");
    }

    private void Skip()
    {
        while (position < source.Length)
        {
            if (char.IsWhiteSpace(source[position]) || (position == 0 && source[position] == '\uFEFF')) position++;
            else if (source[position] == '#' || source.AsSpan(position).StartsWith("//", StringComparison.Ordinal))
            { while (position < source.Length && source[position] != '\n') position++; }
            else break;
        }
    }
    private bool End() { Skip(); return position >= source.Length; }
    private char Peek() => position < source.Length ? source[position] : throw Error("Unexpected end of DV source");
    private bool Take(char token) { Skip(); if (position >= source.Length || source[position] != token) return false; position++; return true; }
    private void Expect(char token) { if (!Take(token)) throw Error("Expected '" + token + "'"); }
    private void Separator() { if (!Take(';')) Take(','); }
    // A saved content pack combines every published source in one declaration
    // stream; its budget must cover that complete bundle as well as each file.
    private void Budget(int depth)
    {
        if (depth > 64) throw Error($"DV content depth budget exceeded: {depth} > 64");
        if (++nodes > 1_000_000) throw Error($"DV content node budget exceeded: {nodes} > 1000000");
    }
    private FormatException Error(string message)
    {
        var before = source[..Math.Min(position, source.Length)];
        return new FormatException($"DV {before.Count(c => c == '\n') + 1}:{before.Length - before.LastIndexOf('\n')}: {message}");
    }
}
