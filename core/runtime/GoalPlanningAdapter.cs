using System.Text.Json;

namespace DuelView.Runtime;

/// <summary>Supplies only owned beliefs and explicit remembered action models to
/// the bounded solver. The objective world's enforcement laws are never read.</summary>
internal sealed class GoalPlanningAdapter
{
    private sealed record Objective(GoalPlanningGoal Goal,Condition Admission);
    private sealed record Model(ActionCandidate Action,Condition Admission,Effect[] Effects,double Cost,double Uncertainty);
    private readonly ActorClient actor;
    private readonly Objective[] goals;
    private readonly Model[] models;
    private readonly Condition admission;
    private readonly string algorithm;
    private readonly bool compare;
    private readonly int depth,expanded,width;
    private readonly double timeUnit;
    private string cache="";
    private GoalPlanningResult? selected,alternative;
    private double selectedFirstPenalty;
    private SavedFact[] basis=[];
    internal string? FirstAction=>selected is {Utility:>0}?selected.FirstAction:null;

    internal GoalPlanningAdapter(ActorClient actor,ActionCandidate[] catalog,double timeUnit)
    {
        this.actor=actor;this.timeUnit=timeUnit;
        var declaration=actor.Declaration.Get("goal_planning");
        admission=declaration.Get("when").ValueKind==JsonValueKind.Object?Condition.Compile(declaration.Get("when"),actor.Id):new Condition.Constant(Truth.True);
        algorithm=declaration.Get("algorithm").Text("best_first");compare=declaration.Get("compare_algorithms").Flag();
        if(algorithm is not ("best_first" or "beam"))throw new InvalidDataException("Unknown personal-goal planning algorithm.");
        int Budget(string name,int fallback,int maximum)
        {
            var value=declaration.Get(name).Number(fallback);
            if(!double.IsFinite(value)||value<1||value>maximum||value!=Math.Truncate(value))throw new InvalidDataException("Invalid goal planning budget: "+name);
            return (int)value;
        }
        depth=Budget("max_depth",6,12);expanded=Budget("max_expanded",512,8192);width=Budget("beam_width",20,128);
        goals=declaration.Get("goals").Items().Select(item=>
        {
            var id=item.Get("id").Text();var weight=item.Get("weight").Number(double.NaN);
            if(string.IsNullOrWhiteSpace(id)||!double.IsFinite(weight)||weight<=0||item.Get("target").ValueKind!=JsonValueKind.Object)
                throw new InvalidDataException("A personal goal needs a named, weighted desired condition.");
            return new Objective(new(id,Condition.Compile(item.Get("target"),actor.Id),weight),
                item.Get("when").ValueKind==JsonValueKind.Object?Condition.Compile(item.Get("when"),actor.Id):new Condition.Constant(Truth.True));
        }).ToArray();
        if(goals.Length>32||goals.Select(item=>item.Goal.Id).Distinct(StringComparer.Ordinal).Count()!=goals.Length)
            throw new InvalidDataException("Duplicate or excessive personal goals.");
        models=catalog.Where(action=>action.Declaration.Get("planning_model").ValueKind==JsonValueKind.Object).Select(action=>
        {
            var model=action.Declaration.Get("planning_model");var cost=model.Get("cost").Number(action.Duration/timeUnit);
            var uncertainty=model.Get("uncertainty_cost").Number();
            var effects=model.Get("effects").Items().Select(effect=>Effect.Compile(effect,actor.Id)).ToArray();
            if(!double.IsFinite(cost)||cost<0||!double.IsFinite(uncertainty)||uncertainty<0||effects.Length is <1 or >64||
                effects.Select(effect=>effect.Key).Distinct().Count()!=effects.Length)
                throw new InvalidDataException("Invalid explicit action planning model: "+action.Id);
            if(action.Declaration.Get("suggestion").ValueKind==JsonValueKind.Object&&uncertainty<=0)
                throw new InvalidDataException("A planning model for persuasion must price another person's uncertain response: "+action.Id);
            return new Model(action,model.Get("when").ValueKind==JsonValueKind.Object?Condition.Compile(model.Get("when"),actor.Id):new Condition.Constant(Truth.True),effects,cost,uncertainty);
        }).ToArray();
        if(models.Length>256)throw new InvalidDataException("Personal goal planning exceeds its action-model budget.");
    }

    internal void Evaluate(double now,Func<ActionCandidate,bool> eligible,Func<ActionCandidate,bool> modelEligible,ActionFailureMemory failures)
    {
        if(goals.Length==0||admission.Evaluate(actor.Recall)!=Truth.True){selected=null;alternative=null;selectedFirstPenalty=0;basis=[];cache="";return;}
        var admitted=goals.Where(goal=>goal.Admission.Evaluate(actor.Recall)==Truth.True).Select(goal=>goal.Goal).ToArray();
        var available=models.Where(model=>!model.Action.Declaration.Get("manual_only").Flag()&&!model.Action.Declaration.Get("physiology_route_only").Flag()&&
            modelEligible(model.Action)&&model.Admission.Evaluate(actor.Recall)==Truth.True&&now/timeUnit>=model.Action.Declaration.Get("not_before_game_minutes").Number()&&
            now/timeUnit<=model.Action.Declaration.Get("not_after_game_minutes").Number(double.PositiveInfinity)).ToArray();
        var first=available.Where(model=>eligible(model.Action)&&model.Action.Recognition.Evaluate(actor.Recall)==Truth.True&&model.Action.Gate.Evaluate(actor.Recall)==Truth.True).Select(model=>model.Action.Id).ToHashSet(StringComparer.Ordinal);
        var operators=available.Select(model=>new GoalPlanningAction(model.Action.Id,new Condition.All([model.Action.Gate,model.Action.Recognition]),model.Effects,model.Cost,model.Uncertainty,failures.Penalty(model.Action.Id,now))).ToArray();
        var keys=admitted.SelectMany(goal=>goal.Target.Inputs).Concat(available.SelectMany(model=>model.Action.Gate.Inputs.Concat(model.Action.Recognition.Inputs).Concat(model.Effects.Select(effect=>effect.Key))))
            .Distinct().OrderBy(key=>key.Object,StringComparer.Ordinal).ThenBy(key=>key.Facet,StringComparer.Ordinal).ThenBy(key=>key.Field,StringComparer.Ordinal).ToArray();
        var facts=keys.Where(key=>actor.Recall(key) is not null).ToDictionary(key=>key,key=>actor.Recall(key)!);
        var signature=string.Join('|',admitted.Select(goal=>goal.Id))+":"+string.Join('|',operators.Select(model=>model.Id+"="+model.FailurePenalty.ToString("R",System.Globalization.CultureInfo.InvariantCulture)))+
            ":"+string.Join('|',first.Order(StringComparer.Ordinal))+":"+string.Join('|',keys.Select(key=>key+"="+(facts.TryGetValue(key,out var fact)?fact.Revision+"/"+fact.Known+"/"+fact.Conflicted+"/"+fact.Value.GetRawText():"unknown")));
        if(signature==cache)return;
        var request=new GoalPlanningRequest(facts,admitted,operators,first,depth,expanded,width);
        selected=GoalPlanning.Solve(request,algorithm);
        selectedFirstPenalty=operators.FirstOrDefault(action=>action.Id==selected.FirstAction)?.FailurePenalty??0;
        alternative=compare?GoalPlanning.Solve(request,algorithm=="best_first"?"beam":"best_first"):null;
        basis=facts.Select(pair=>new SavedFact(pair.Key,pair.Value)).ToArray();cache=signature;
    }
    // The scheduler applies the current step's failure penalty once, alongside
    // other candidates. Later predicted failures remain in the plan's cost.
    internal double Score(string action)=>FirstAction==action?Math.Max(0,selected!.Utility)+selectedFirstPenalty:0;
    internal object Audit()=>new {selected,comparison=alternative,owned_basis=basis,prediction_only=true};
    internal JsonElement Save()=>JsonSerializer.SerializeToElement(new {cache,selected,alternative,basis,selectedFirstPenalty});
    internal void Restore(JsonElement state)
    {
        selected=null;alternative=null;basis=[];cache="";selectedFirstPenalty=0;
        if(state.ValueKind==JsonValueKind.Undefined)return;
        if(state.ValueKind!=JsonValueKind.Object)throw new InvalidDataException("Invalid goal-planning checkpoint.");
        GoalPlanningResult? Result(string key)
        {
            var value=state.Get(key);
            if(value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)return null;
            var result=value.Deserialize<GoalPlanningResult>()??throw new InvalidDataException("Missing goal-planning result.");
            if(result.Algorithm is not ("best_first" or "beam")||!double.IsFinite(result.Utility)||!double.IsFinite(result.Cost)||result.Cost<0||
                result.Expanded is <0 or >8192||result.ActionSequence is null||result.ActionSequence.Count>12||result.ReachedGoals is null||result.ReachedGoals.Count>32||
                result.ActionSequence.Any(id=>!models.Any(model=>model.Action.Id==id))||result.ReachedGoals.Any(id=>!goals.Any(goal=>goal.Goal.Id==id))||
                result.FirstAction is { } first&&(result.ActionSequence.Count==0||result.ActionSequence[0]!=first))
                throw new InvalidDataException("Incompatible goal-planning result checkpoint.");
            return result;
        }
        selected=Result("selected");alternative=Result("alternative");
        cache=state.Get("cache").Text();selectedFirstPenalty=state.Get("selectedFirstPenalty").Number();
        basis=state.Get("basis").Deserialize<SavedFact[]>()??[];
        if(!double.IsFinite(selectedFirstPenalty)||selectedFirstPenalty<0||cache.Length>1000000||basis.Select(item=>item.Key).Distinct().Count()!=basis.Length)
            throw new InvalidDataException("Invalid goal-planning cache checkpoint.");
    }
    internal DecisionIntent? Intent(string action)=>FirstAction==action?new("goal",null,null,null,
        "根据本人已知条件预测"+selected!.ActionSequence.Count+"步行动，检验能否推进"+selected.ReachedGoals.Count+"项自身目标；结果仍待现场执行。",
        GoalAlgorithm:selected.Algorithm,GoalSequence:selected.ActionSequence.ToArray(),GoalObjectives:selected.ReachedGoals.ToArray()):null;
}
