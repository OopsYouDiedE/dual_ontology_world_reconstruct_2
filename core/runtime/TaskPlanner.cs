using System.Text.Json;

namespace DuelView.Runtime;

public sealed record TaskPlannerCheckpoint(string? CurrentTask,string? InterruptedTask,string? UrgentNeed,
    string[] CompletedSteps,string Selected,string Reason,string? LastCompletedTask,PhysiologicalRoutesState? Routes=null,string[]? CompletedTasks=null,string? SelectedNeed=null);

/// <summary>A bounded, authored partial-order plan. Its frontier is derived only
/// from the owner's remembered evidence. Physiological arbitration is a separate
/// path; taking a drink or resting never marks a task step complete.</summary>
internal sealed class TaskPlanner
{
    private sealed record Step(string Id,ActionCandidate Action,string[] After,Condition Done);
    private sealed record Task(string Id,string Label,double Priority,double NotBefore,Condition Available,Condition Goal,Step[] Steps);
    private readonly ActorClient actor;
    private readonly ActionCandidate[] catalog;
    private readonly DriveCalculator drives;
    private readonly Func<ActionCandidate,bool> eligible;
    private readonly Func<ActionCandidate,double,double> failurePenalty;
    private readonly Task[] tasks;
    private readonly Dictionary<string,Task> byId;
    private readonly HashSet<string> completed=[];
    private readonly HashSet<string> completedTasks=new(StringComparer.Ordinal);
    private readonly string[] physiological;
    private readonly Dictionary<string,double> critical=[],resume=[];
    private readonly double contentTimeUnit;
    private readonly double taskGuidanceUntil;
    private readonly PhysiologicalRoutes routes;
    private string? current,interrupted,urgent,lastCompleted,selectedNeed;
    private string selected="none",reason="尚未选择行动。";
    internal bool Enabled { get; }
    internal bool DirectedChoice=>selected is "task" or "physiology";

    internal TaskPlanner(ActorClient actor,ActionCandidate[] catalog,DriveCalculator drives,
        Func<ActionCandidate,bool> eligible,double contentTimeUnit,Func<ActionCandidate,double,double>? failurePenalty=null)
    {
        this.actor=actor;this.catalog=catalog;this.drives=drives;this.eligible=eligible;this.contentTimeUnit=contentTimeUnit;
        this.failurePenalty=failurePenalty??((_,_)=>0);
        var planning=actor.Declaration.Get("planning");Enabled=planning.ValueKind==JsonValueKind.Object;
        taskGuidanceUntil=planning.Get("task_guidance_until_game_minutes").Number(double.PositiveInfinity);
        if(double.IsNaN(taskGuidanceUntil)||taskGuidanceUntil<0)throw new InvalidDataException("Invalid task guidance boundary.");
        if(catalog.Length>4096)throw new InvalidDataException("Actor action catalog exceeds the planning budget.");
        var candidates=catalog.ToDictionary(a=>a.Id,StringComparer.Ordinal);
        var built=new List<Task>();var stepCount=0;
        foreach(var item in planning.Get("tasks").Items())
        {
            if(built.Count>=32)throw new InvalidDataException("Task planning supports at most 32 authored tasks per actor.");
            var id=item.Get("id").Text();var label=item.Get("label").Text();
            var priority=item.Get("priority").Number(1);var notBefore=item.Get("not_before_game_minutes").Number();
            if(string.IsNullOrWhiteSpace(id)||string.IsNullOrWhiteSpace(label)||!double.IsFinite(priority)||priority<0||!double.IsFinite(notBefore)||notBefore<0)
                throw new InvalidDataException("Invalid task identity, priority or public time gate.");
            if(item.Get("available_when").ValueKind!=JsonValueKind.Object||item.Get("goal").ValueKind!=JsonValueKind.Object)
                throw new InvalidDataException("Task requires an authored knowledge admission and completion condition: "+id);
            var steps=new List<Step>();
            foreach(var entry in item.Get("steps").Items())
            {
                if(steps.Count>=32||++stepCount>512)throw new InvalidDataException("Task step budget exceeded.");
                var stepId=entry.Get("id").Text();var actionId=entry.Get("action").Text();
                if(string.IsNullOrWhiteSpace(stepId)||!candidates.TryGetValue(actionId,out var action)||action.Declaration.Get("manual_only").Flag()||action.Declaration.Get("physiology_route_only").Flag())
                    throw new InvalidDataException("Task step must name an owned autonomous action: "+id+"/"+stepId);
                var after=entry.Get("after").Items().Select(v=>v.Text()).ToArray();
                if(after.Length>32||after.Distinct(StringComparer.Ordinal).Count()!=after.Length||entry.Get("done_when").ValueKind!=JsonValueKind.Object)
                    throw new InvalidDataException("Task step needs finite dependencies and an observed completion condition.");
                steps.Add(new(stepId,action,after,Condition.Compile(entry.Get("done_when"),actor.Id)));
            }
            if(steps.Count==0||steps.Select(s=>s.Id).Distinct(StringComparer.Ordinal).Count()!=steps.Count)
                throw new InvalidDataException("Task needs uniquely identified steps: "+id);
            var pending=steps.ToDictionary(s=>s.Id,s=>s.After.ToHashSet(StringComparer.Ordinal),StringComparer.Ordinal);
            if(pending.Values.Any(deps=>deps.Any(dep=>!pending.ContainsKey(dep))))throw new InvalidDataException("Task dependency references an unknown step.");
            var resolved=new HashSet<string>(StringComparer.Ordinal);
            while(resolved.Count<steps.Count)
            {
                var ready=pending.Where(p=>!resolved.Contains(p.Key)&&p.Value.All(resolved.Contains)).Select(p=>p.Key).ToArray();
                if(ready.Length==0)throw new InvalidDataException("Task dependency cycle: "+id);
                resolved.UnionWith(ready);
            }
            built.Add(new(id,label,priority,notBefore,Condition.Compile(item.Get("available_when"),actor.Id),Condition.Compile(item.Get("goal"),actor.Id),steps.ToArray()));
        }
        if(built.Select(t=>t.Id).Distinct(StringComparer.Ordinal).Count()!=built.Count)throw new InvalidDataException("Duplicate task identity.");
        tasks=built.ToArray();byId=tasks.ToDictionary(t=>t.Id,StringComparer.Ordinal);
        physiological=planning.Get("physiology").Get("needs").Items().Select(v=>v.Text()).ToArray();
        if(physiological.Length>16||physiological.Distinct(StringComparer.Ordinal).Count()!=physiological.Length)throw new InvalidDataException("Invalid physiological need vocabulary.");
        var values=drives.Snapshot(0);
        foreach(var need in physiological)
        {
            var low=planning.Get("physiology").Get("critical_below").Get(need).Number(double.NaN);
            var high=planning.Get("physiology").Get("resume_above").Get(need).Number(double.NaN);
            if(!values.ContainsKey(need)||!double.IsFinite(low)||!double.IsFinite(high)||low<0||high>100||high<=low)
                throw new InvalidDataException("Physiology requires a declared need and distinct critical/recovery thresholds: "+need);
            critical.Add(need,low);resume.Add(need,high);
        }
        routes=new(actor,catalog,drives,resume,contentTimeUnit);
    }

    private string Key(Task task,Step step)=>task.Id+"/"+step.Id;
    private bool Admitted(Task task,double now)=>now/contentTimeUnit<taskGuidanceUntil&&now/contentTimeUnit>=task.NotBefore&&task.Available.Evaluate(actor.Recall)==Truth.True;
    private void Refresh(double now)
    {
        if(!Enabled)return;
        if(now/contentTimeUnit>=taskGuidanceUntil){current=null;interrupted=null;}
        // Goals such as reaching a room may stop being true after the actor
        // leaves. Latch only admitted, personally known achievements, including
        // goals reached while another task was current. They stay complete.
        foreach(var task in tasks)
            if(!completedTasks.Contains(task.Id)&&Admitted(task,now)&&task.Goal.Evaluate(actor.Recall)==Truth.True)
                completedTasks.Add(task.Id);
        if(current is { } id && completedTasks.Contains(id))
        {lastCompleted=id;current=null;if(interrupted==id)interrupted=null;}
        if(interrupted is { } finished&&completedTasks.Contains(finished))interrupted=null;
        if(!routes.Active&&current is { } retained && !Admitted(byId[retained],now))current=null;
        if(!routes.Active&&current is null)
            current=tasks.Where(t=>!completedTasks.Contains(t.Id)&&Admitted(t,now))
                .OrderByDescending(t=>t.Priority).Select(t=>t.Id).FirstOrDefault();
        if(current is { } active)
        {
            var task=byId[active];
            for(var pass=0;pass<task.Steps.Length;pass++)
            {
                var changed=false;
                foreach(var step in task.Steps)
                    if(step.After.All(dep=>completed.Contains(task.Id+"/"+dep))&&step.Done.Evaluate(actor.Recall)==Truth.True)
                        changed|=completed.Add(Key(task,step));
                if(!changed)break;
            }
        }
        var values=drives.Snapshot(now);
        if(urgent is { } old&&values[old]>=resume[old])urgent=null;
        urgent??=physiological.Where(n=>values[n]<critical[n]).OrderBy(n=>values[n]/Math.Max(critical[n],1)).FirstOrDefault();
        if(!routes.Active&&urgent is null&&interrupted is { } paused)
        {
            if(!completedTasks.Contains(paused)&&Admitted(byId[paused],now))current=paused;
            interrupted=null;
        }
    }

    internal ActionCandidate[] Frontier(double now)
    {
        Refresh(now);
        var supplies=routes.Active?routes.Candidates(urgent):CriticalNeeds(now).SelectMany(need=>routes.Candidates(need)).ToArray();
        return supplies.Concat(TaskFrontier()).DistinctBy(a=>a.Id).ToArray();
    }
    private string[] CriticalNeeds(double now)
    {
        var values=drives.Snapshot(now);
        return (urgent is null?Array.Empty<string>():new[]{urgent!})
            .Concat(physiological.Where(n=>n!=urgent&&values[n]<critical[n]).OrderBy(n=>values[n]/Math.Max(critical[n],1))).ToArray();
    }
    private ActionCandidate[] TaskFrontier()
    {
        if(current is not { } id)return [];
        var task=byId[id];
        return task.Steps.Where(s=>!completed.Contains(Key(task,s))&&s.After.All(dep=>completed.Contains(task.Id+"/"+dep)))
            .Select(s=>s.Action).DistinctBy(a=>a.Id).ToArray();
    }

    private double NeedScore(ActionCandidate action,double now,string? specificNeed=null)
    {
        var evaluation=drives.Evaluate(action,now);
        // Base priorities, social motives, emotions and task rewards are not
        // physiological utility. This path only ranks actual need improvement.
        return (specificNeed??urgent) is { } need?Math.Max(0,evaluation.NeedContributions.GetValueOrDefault(need)):
            physiological.Sum(name=>Math.Max(0,evaluation.NeedContributions.GetValueOrDefault(name)));
    }

    internal ActionCandidate? Choose(IEnumerable<ActionCandidate> admitted,ActionCandidate? daily,double now,bool remember=true)
    {
        if(!Enabled)return daily;
        Refresh(now);
        var frontier=TaskFrontier().Select(a=>a.Id).ToHashSet(StringComparer.Ordinal);
        double Utility(ActionCandidate action)=>drives.Score(action,now)+actor.GoalScore(action,now/contentTimeUnit)-failurePenalty(action,now);
        var choices=admitted.Where(a=>!a.Declaration.Get("manual_only").Flag()&&a.Recognition.Evaluate(actor.Recall)==Truth.True&&eligible(a))
            .Where(a=>failurePenalty(a,now)==0||Utility(a)>0).ToArray();
        var task=choices.Where(a=>frontier.Contains(a.Id)).OrderByDescending(Utility).FirstOrDefault();
        var physical=choices.Where(a=>!a.Declaration.Get("physiology_route_only").Flag()).Select(a=>(action:a,score:NeedScore(a,now))).Where(p=>p.score>0)
            .OrderByDescending(p=>p.score).Select(p=>p.action).FirstOrDefault();
        var routeAction=routes.Choose(choices,urgent,current,now);
        var physicalNeed=urgent;
        // An unavailable meal must not suppress an actually reachable water
        // source. Retain the original urgent need and its recovery threshold;
        // try another critical need only if the first has no legal recovery.
        if(!routes.Active&&physical is null&&urgent is not null)
            foreach(var alternative in CriticalNeeds(now).Where(n=>n!=urgent))
            {
                routeAction=routes.Choose(choices,alternative,current,now);
                if(routes.Active){physicalNeed=alternative;break;}
                physical=choices.Where(a=>!a.Declaration.Get("physiology_route_only").Flag()&&drives.CompletedEffect(a,alternative)>0)
                    .Select(a=>(action:a,score:NeedScore(a,now,alternative))).Where(p=>p.score>0)
                    .OrderByDescending(p=>p.score).Select(p=>p.action).FirstOrDefault();
                if(physical is not null){physicalNeed=alternative;break;}
            }
        string path,why;ActionCandidate? choice;
        if(routes.Active)
        {
            choice=routeAction;path="physiology";why=routeAction is null?"补给往返正在等待合法的通路或恢复条件。":routes.Explanation;
            if(remember&&current is not null)interrupted=current;
        }
        else if(urgent is not null&&physical is not null)
        {
            choice=physical;path="physiology";why=physicalNeed!=urgent?
                "最紧迫的身体需要暂未找到合法恢复行动，先处理同样低于临界值的"+NeedLabel(physicalNeed!)+"。":
                NeedLabel(urgent)+"低于临界值，先处理身体需要"+(current is null?"。":"，保留当前任务。");
            if(remember&&current is not null)interrupted=current;
        }
        else if(task is not null){choice=task;path="task";why="已满足已知前置步骤，推进当前任务的依赖前沿。";if(remember)interrupted=null;}
        else if(physical is not null&&current is not null){choice=physical;path="physiology";why="任务暂待新的现场条件，先完成当前可用的身体照护。";if(remember)interrupted=current;}
        else {choice=daily;path=daily is null?"none":"daily";why=urgent is not null?"身体需要紧迫，当前尚无可用的恢复行动。":current is not null?"任务正在等待已知前置步骤或现场条件。":"当前没有已解锁任务，继续日常判断。";}
        if(remember){selected=path;reason=why;selectedNeed=path=="physiology"?routes.Need??physicalNeed:null;}
        return choice;
    }

    internal object View(double now,bool autonomous)
    {
        var checkpoint=SaveState();
        try{return Project(now,autonomous);}
        finally{RestoreState(checkpoint);}
    }
    private object Project(double now,bool autonomous)
    {
        Refresh(now);
        var frontier=TaskFrontier();
        // This read-only advice is bounded by the authored catalog. It never
        // starts an execution or supplies evidence for a manual deduction.
        var allowed=catalog.Where(a=>!a.Declaration.Get("manual_only").Flag()&&a.Recognition.Evaluate(actor.Recall)==Truth.True&&eligible(a)).ToArray();
        var defaultAction=allowed.Where(a=>!a.Declaration.Get("physiology_route_only").Flag()).OrderByDescending(a=>drives.Score(a,now)+actor.GoalScore(a,now/contentTimeUnit)).FirstOrDefault();
        var priorInterrupted=interrupted;
        var hadRoute=routes.Active;
        Choose(allowed,defaultAction,now);
        if(!autonomous)interrupted=priorInterrupted;
        var values=drives.Snapshot(now);var frontierIds=frontier.Select(a=>a.Id).ToHashSet(StringComparer.Ordinal);
        var taskRecommendations=allowed.Where(a=>frontierIds.Contains(a.Id)).Take(3)
            .Select(a=>new {id=a.Id,label=a.Declaration.Get("label").Text(a.Id),reason="本人已知前提成立，且前序步骤已有完成证据。"}).ToArray();
        var adviceNeed=selected=="physiology"?selectedNeed??urgent:urgent;
        var routeIds=routes.Candidates(adviceNeed).Select(a=>a.Id).ToHashSet(StringComparer.Ordinal);
        var physiologicalRecommendations=allowed.Select(a=>(action:a,score:NeedScore(a,now,adviceNeed),route:routeIds.Contains(a.Id))).Where(p=>p.route||p.score>0&&!p.action.Declaration.Get("physiology_route_only").Flag())
            .OrderByDescending(p=>p.route).ThenByDescending(p=>p.score).Take(3)
            .Select(p=>new {id=p.action.Id,label=p.action.Declaration.Get("label").Text(p.action.Id),reason=p.route?routes.Explanation:"预计改善当前身体需要。",utility=p.score}).ToArray();
        var active=current is { } id?byId[id]:null;
        return new {
            controller=autonomous?"ai":"player",selected,reason,
            completed_tasks=new {count=completedTasks.Count,ids=completedTasks.OrderBy(id=>id,StringComparer.Ordinal).ToArray()},
            task=new {id=active?.Id??"",label=active?.Label??"尚无已解锁任务",status=active is null?"none":interrupted==active.Id?"interrupted":taskRecommendations.Length>0?"active":"blocked",
                reason=active is null?"通过实际观察和交流解锁任务。":interrupted==active.Id?"处理身体需要后继续原计划。":taskRecommendations.Length>0?"当前依赖前沿可执行。":"等待已知前置步骤或现场条件。",
                completed_steps=active is null?0:active.Steps.Count(s=>completed.Contains(Key(active,s))),total_steps=active?.Steps.Length??0,
                recommended_actions=taskRecommendations,blockers=active is not null&&taskRecommendations.Length==0?new[]{"当前没有同时满足本人认知与现场条件的任务步骤。"}:Array.Empty<string>()},
            physiology=new {status=routes.Active?hadRoute?"in_progress":"recommended":urgent is null?"satisfied":physiologicalRecommendations.Length>0?"urgent":"unavailable",
                needs=physiological.Select(n=>new{id=n,label=NeedLabel(n),value=values[n],critical_below=critical[n],resume_above=resume[n],urgency=urgent==n||values[n]<critical[n]?"urgent":values[n]<resume[n]?"low":"normal"}).ToArray(),
                recommended_actions=physiologicalRecommendations,route=routes.View(),route_is_preview=routes.Active&&!hadRoute,recent_routes=routes.Receipts()}
        };
    }
    private static string NeedLabel(string id)=>id switch {"energy"=>"精力","hunger"=>"饱食","thirst"=>"水分","hygiene"=>"清洁","comfort"=>"舒适","social"=>"陪伴",_=>id};

    internal DecisionIntent Intent(string action,bool manual=false)=>new(manual?"player":Enabled?selected:"daily",current,
        current is { } id?byId[id].Steps.FirstOrDefault(step=>step.Action.Id==action)?.Id:null,routes.Need??selectedNeed??urgent,
        manual?"玩家根据当前合法选项亲自选择。":reason,routes.ActiveId,routes.StepId);
    internal void Completed(Decision decision,double now)=>routes.Complete(decision,now);
    internal void ManualChoice(string action,double now)
    {
        Refresh(now);
        routes.ManualChoice(action,current,now);
        selectedNeed=routes.Need;
        if(routes.Active&&current is not null)interrupted=current;
    }

    internal TaskPlannerCheckpoint SaveState()=>new(current,interrupted,urgent,completed.OrderBy(v=>v,StringComparer.Ordinal).ToArray(),selected,reason,lastCompleted,routes.Save(),completedTasks.OrderBy(id=>id,StringComparer.Ordinal).ToArray(),selectedNeed);
    internal void RestoreState(TaskPlannerCheckpoint? state)
    {
        if(state is null){if(Enabled)throw new InvalidDataException("A new task plan requires a new game.");return;}
        if(Enabled&&state.CompletedTasks is null)throw new InvalidDataException("Saved task planning lacks persistent completion records; start a new game.");
        var done=state.CompletedTasks??[];
        var keys=tasks.SelectMany(t=>t.Steps.Select(s=>Key(t,s))).ToHashSet(StringComparer.Ordinal);
        if(new[]{state.CurrentTask,state.InterruptedTask,state.LastCompletedTask}.Any(id=>id is not null&&!byId.ContainsKey(id))||
           state.UrgentNeed is { } need&&!critical.ContainsKey(need)||state.SelectedNeed is { } chosen&&!critical.ContainsKey(chosen)||state.CompletedSteps is null||state.CompletedSteps.Any(key=>!keys.Contains(key))||
           done.Any(id=>!byId.ContainsKey(id))||done.Distinct(StringComparer.Ordinal).Count()!=done.Length||
           state.CurrentTask is { } currentId&&done.Contains(currentId,StringComparer.Ordinal)||state.InterruptedTask is { } interruptedId&&done.Contains(interruptedId,StringComparer.Ordinal)||
           state.CompletedSteps.Distinct(StringComparer.Ordinal).Count()!=state.CompletedSteps.Length||state.Selected is not ("none" or "daily" or "task" or "physiology"))
            throw new InvalidDataException("Incompatible saved task or physiological path.");
        current=state.CurrentTask;interrupted=state.InterruptedTask;urgent=state.UrgentNeed;lastCompleted=state.LastCompletedTask;selectedNeed=state.SelectedNeed;
        completed.Clear();completed.UnionWith(state.CompletedSteps);selected=state.Selected;reason=state.Reason;
        completedTasks.Clear();completedTasks.UnionWith(done);
        routes.Restore(state.Routes);
    }
}
