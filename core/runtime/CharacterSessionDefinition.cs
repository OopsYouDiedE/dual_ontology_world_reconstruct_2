using System.Text.Json;
using System.Text.Json.Nodes;
using DuelView.Dv;

namespace DuelView.Runtime;

/// <summary>A finite authored session uses the production Core and the shared DV parser.</summary>
public sealed class CharacterSessionDefinition
{
    public JsonElement Declaration { get; }
    public string Hash { get; }
    private readonly DvDocument policies;

    public CharacterSessionDefinition(string source,string policySource,Func<string,string>? readSource=null)
    {
        var document=DvDocument.Parse(source);
        if(document.Definition("data","runtime.character_session").GetProperty("value").Get("compact").Flag() && source.Count(c=>c=='\n')>2000)
            throw new InvalidDataException("Compact scenario source exceeds the 2000-line authoring limit.");
        Declaration=CampaignScenario.Expand(document.Definition("data","runtime.character_session").GetProperty("value"),
            readSource??(path=>File.ReadAllText(path.Replace("res://",""))));
        CampaignProgress.Validate(Declaration);
        ValidateReservations(Declaration);
        Hash=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Declaration.GetRawText()))).ToLowerInvariant();
        policies=DvDocument.Parse(policySource);
    }

    private static void ValidateReservations(JsonElement declaration)
    {
        var actorIds=declaration.Get("actors").Items().Select(actor=>actor.Get("id").Text()).ToHashSet(StringComparer.Ordinal);
        var actorActions=declaration.Get("actors").Items().ToDictionary(
            actor=>actor.Get("id").Text(),
            actor=>actor.Get("actions").Items().Select(action=>action.Get("id").Text()).ToHashSet(StringComparer.Ordinal),
            StringComparer.Ordinal);
        var slots=new HashSet<string>(StringComparer.Ordinal);
        foreach(var slot in declaration.Get("slots").Items())
        {
            var id=slot.Get("id").Text();
            var capacity=slot.Get("capacity");
            if(string.IsNullOrWhiteSpace(id)||capacity.ValueKind!=JsonValueKind.Number||!capacity.TryGetInt32(out var count)||count<1||!slots.Add(id))
                throw new InvalidDataException($"Invalid or duplicate reservation slot '{id}'; capacity must be a positive integer.");
        }
        foreach(var station in declaration.Get("yield_stations").Items())
            if(!slots.Add("yield.station."+station.Get("id").Text()))
                throw new InvalidDataException($"Duplicate yield reservation slot '{station.Get("id").Text()}'.");
        foreach(var actor in declaration.Get("actors").Items())
        foreach(var action in actor.Get("actions").Items())
        {
        foreach(var text in new[]{"completion_text","public_completion_text"})
            if(action.Get(text).ValueKind!=JsonValueKind.Undefined&&(action.Get(text).ValueKind!=JsonValueKind.String||action.Get(text).Text().Length>16000))
                throw new InvalidDataException("Action presentation text must be a bounded string: "+action.Get("id").Text());
        var completionLines=action.Get("completion_lines");
        if(completionLines.ValueKind!=JsonValueKind.Undefined&&(completionLines.ValueKind!=JsonValueKind.Array||completionLines.GetArrayLength()>32))
            throw new InvalidDataException("Action completion lines must be a bounded array: "+action.Get("id").Text());
        foreach(var line in completionLines.Items())
        {
            var viewpoint=line.Get("speaker");
            if(line.Get("text").ValueKind!=JsonValueKind.String||line.Get("text").Text().Length>16000||
               viewpoint.ValueKind!=JsonValueKind.Undefined&&(viewpoint.ValueKind!=JsonValueKind.String||!actorIds.Contains(viewpoint.Text())))
                throw new InvalidDataException("Invalid completion line or viewpoint: "+action.Get("id").Text());
            if(line.Get("when").ValueKind!=JsonValueKind.Undefined)_=Condition.Compile(line.Get("when"),actor.Get("id").Text());
        }
        var cooldown=action.Get("cooldown_minutes");
        if(cooldown.ValueKind!=JsonValueKind.Undefined&&(!double.IsFinite(cooldown.Number(double.NaN))||cooldown.Number()<0))
            throw new InvalidDataException("Action cooldown must be a finite nonnegative duration: "+action.Get("id").Text());
        foreach(var member in action.Get("motor").Get("observe_group").Items())
            if(!actorIds.Contains(member.Text()))throw new InvalidDataException("Unknown group observation actor: "+member.Text());
        var observedActions=action.Get("motor").Get("observed_group_actions").Items().ToArray();
        if(observedActions.Length>16 || observedActions.Select(item=>item.Get("actor").Text()).Distinct(StringComparer.Ordinal).Count()!=observedActions.Length)
            throw new InvalidDataException("Invalid observed group action budget: "+action.Get("id").Text());
        foreach(var observed in observedActions)
        {
            var observedActor=observed.Get("actor").Text();
            if(!action.Get("motor").Get("observe_group").Items().Any(member=>member.Text()==observedActor) ||
               !actorActions.TryGetValue(observedActor,out var candidates) || !candidates.Contains(observed.Get("action").Text()))
                throw new InvalidDataException("Invalid observed group action: "+action.Get("id").Text());
        }
        var handoff=action.Get("handoff");
        if(handoff.ValueKind==JsonValueKind.Object)
        {
            var recipient=handoff.Get("actor").Text();
            if(!actorIds.Contains(recipient) || action.Get("motor").Get("observe_actor").Text()!=recipient || handoff.Get("refs").Items().Count()>8 || handoff.Get("result_refs").Items().Count()>8)
                throw new InvalidDataException("Invalid physical handoff: "+action.Get("id").Text());
            foreach(var reference in handoff.Get("refs").Items().Concat(handoff.Get("result_refs").Items()))_=FieldKey.Read(reference,recipient);
        }
        var guards=action.Get("knowledge_guards").Items().ToArray();
        if(guards.Length>16)throw new InvalidDataException("Knowledge guard budget exceeded: "+action.Get("id").Text());
        foreach(var guard in guards)
        {
            var id=guard.Get("actor").Text();
            if(!actorIds.Contains(id) || guard.Get("mode").Text() is not ("known_true" or "not_known_true"))
                throw new InvalidDataException("Invalid knowledge guard: "+action.Get("id").Text());
            _=FieldKey.Read(guard.Get("ref"),id);
        }
        foreach(var resource in action.Get("resource_reservations").Items())
        {
            var id=resource.Text();
            if(!slots.Contains(id))
                throw new InvalidDataException($"Actor '{actor.Get("id").Text()}' action '{action.Get("id").Text()}' references undefined reservation slot '{id}'.");
        }
        }
    }

    private JsonElement Policy(string id)=>policies.Definition("data",id).GetProperty("value");

    public RuntimeSession Create(string? deductionSource=null)
    {
        var runtime=Policy("runtime.session");
        var timing=Policy(runtime.Get("action_timing_definition").Text());
        var policy=JsonNode.Parse(runtime.GetRawText())!.AsObject();
        policy["content_time_unit_seconds"]=timing.Get("content_time_unit_seconds").GetDouble();
        if(Declaration.Get("clock_ref").ValueKind==JsonValueKind.Object)
            policy["clock_ref"]=JsonNode.Parse(Declaration.Get("clock_ref").GetRawText());
        var scheduling=JsonNode.Parse(Policy(runtime.Get("scheduling_definition").Text()).GetRawText())!.AsObject();
        var stagger=Declaration.Get("scheduling").Get("actor_stagger_seconds");
        if(stagger.ValueKind==JsonValueKind.Number)scheduling["actor_stagger_seconds"]=stagger.GetDouble();
        foreach(var key in new[]{"decision_interval_seconds","candidates_per_decision","evaluations_per_slice","milliseconds_per_slice"})
            if(Declaration.Get("scheduling").Get(key).ValueKind==JsonValueKind.Number)
                scheduling[key]=JsonNode.Parse(Declaration.Get("scheduling").Get(key).GetRawText());
        var world=Declaration.Get("physical");
        var session=new RuntimeSession(world,JsonSerializer.SerializeToElement(policy),
            JsonSerializer.SerializeToElement(scheduling),Policy(runtime.Get("clock_definition").Text()),
            Policy(runtime.Get("residency_definition").Text()),world.Get("time").Number()*timing.Get("content_time_unit_seconds").Number());
        if(Declaration.Get("completion").Get("mode").Text()=="observation_window")
            session.ConfigureObservationHorizon(Declaration.Get("completion").Get("end_minutes").Number());
        session.ConfigureBindings(Declaration.Get("bindings"));
        session.ConfigureHostPhysicalBindings(Declaration.Get("host_physical_bindings"));
        session.ConfigureReservations(Declaration.Get("slots"));
        foreach(var process in Declaration.Get("world_processes").Items())
        {
            var id=process.Get("law").Text();
            var adoption=world.Get("adoptions").Get(id);
            var reference=Declaration.Get("clock_ref");
            if(adoption.ValueKind!=JsonValueKind.Object || reference.ValueKind!=JsonValueKind.Object)
                throw new InvalidDataException("World process requires an adopted law and clock: "+id);
            var automatic=JsonNode.Parse(adoption.GetRawText())!.AsObject();
            automatic["trigger"]=process.Get("once").Flag()?"once":"rising_edge";
            session.Rules.Register(id,JsonSerializer.SerializeToElement(automatic),FieldKey.Read(reference,"world"));
        }
        foreach(var station in Declaration.Get("yield_stations").Items())
            session.Reservations.Define("yield.station."+station.Get("id").Text(),1);
        foreach(var actor in Declaration.Get("actors").Items())
        {
            var actorNode=JsonNode.Parse(actor.GetRawText())!.AsObject();
            var actions=actorNode["actions"]!.AsArray();
            var actorId=actor.Get("id").Text();
            foreach(var station in Declaration.Get("yield_stations").Items())
            {
                var id=station.Get("id").Text();
                actions.Add(JsonSerializer.SerializeToNode(new {
                    id=actorId+".yield."+id,label="让开通路",kind="travel",manual_only=true,
                    precondition=new {op="constant",value=true},duration=1,host_execution=true,
                    timing=new {host_elapsed=true},minimum_travel_distance_m=0.4,
                    route_rooms=new[]{station.Get("room").Text()},resource_reservations=new[]{"yield.station."+id},
                    perceived_need_effects=new {},completed_need_effects=new {},
                    motor=new {target=station.Get("target"),posture="standing",animation="walk"}
                }));
            }
            var actorData=JsonSerializer.SerializeToElement(actorNode);
            session.RegisterActor(actorData,Policy(runtime.Get("attention").Text()),
                ActionCatalog.Compile(actorData,world,Declaration.Get("cost_model"),timing),actor.Get("autonomous").Flag());
            if(actor.Get("incapacitated_ref").ValueKind==JsonValueKind.Object)
                session.ConfigureIncapacitation(actorId,actor.Get("incapacitated_ref"));
        }
        session.ConfigurePresenceGroups(Declaration.Get("presence_groups"));
        session.ConfigureAccumulators(Declaration.Get("objective_accumulators"));
        session.ConfigureMechanics(Declaration);
        if(Declaration.Get("deduction").ValueKind==JsonValueKind.Object)
            session.ConfigureDeduction(deductionSource??throw new InvalidDataException("Deduction source is required."),Declaration.Get("deduction"));
        return session;
    }
}
