using System.Text.Json;
using System.Text.Json.Nodes;

namespace DuelView.Runtime;

internal static class LifeCognitionScenario
{
    internal static void Acceptance(JsonObject root,JsonElement declaration,IEnumerable<string> actors)
    {
        var expectations=root["expectations"] as JsonArray??new();
        var boundaries=root["knowledge_boundaries"] as JsonArray??new();
        foreach(var actor in actors)
        {
            expectations.Add(LifeScenario.Object(new {id=actor+".cognition.sourced",inference_evidence=new {actor,@object=actor,facet="infer",field="music"}}));
            foreach(var other in actors.Where(other=>other!=actor))
            {
                foreach(var field in declaration.Get("protected_target_fields").Items())
                    boundaries.Add(new JsonObject{["actor"]=actor,["ref"]=LifeScenario.Ref(other+"."+field.Text())});
                foreach(var field in declaration.Get("unknown_target_conclusions").Items())
                    expectations.Add(new JsonObject{["id"]=actor+".cognition.unknown."+other+"."+field.Text(),["actor"]=actor,
                        ["condition"]=new JsonObject{["op"]="equals",["ref"]=LifeScenario.Ref(other+".infer."+field.Text()),["value"]="unknown"}});
            }
        }
        root["expectations"]=expectations;root["knowledge_boundaries"]=boundaries;
    }

    internal static JsonObject Expand(JsonElement declaration,string actor,IEnumerable<string> others)
    {
        JsonNode Replace(JsonNode node,string other)
        {
            if(node is JsonValue value&&value.TryGetValue<string>(out var text))return JsonValue.Create(text.Replace("${self}",actor).Replace("${other}",other))!;
            if(node is JsonArray array)return new JsonArray(array.Select(item=>Replace(item!,other)).ToArray());
            if(node is JsonObject map)return new JsonObject(map.Select(item=>new KeyValuePair<string,JsonNode?>(item.Key,Replace(item.Value!,other))));
            return node.DeepClone();
        }
        var result=LifeScenario.Copy(declaration)!.AsObject();
        foreach(var group in new[]{"inputs","queries"})
        {
            var entries=new JsonArray();
            foreach(var input in declaration.Get("self_"+group).Items())entries.Add(Replace(LifeScenario.Copy(input)!,actor));
            foreach(var other in others.Where(other=>other!=actor))
                foreach(var input in declaration.Get("target_"+group).Items())entries.Add(Replace(LifeScenario.Copy(input)!,other));
            foreach(var input in entries.OfType<JsonObject>())
            {
                input["ref"]=LifeScenario.Ref(input["path"]!.GetValue<string>());input.Remove("path");
            }
            result[group]=entries;
            result.Remove("self_"+group);result.Remove("target_"+group);
        }
        return result;
    }
}
