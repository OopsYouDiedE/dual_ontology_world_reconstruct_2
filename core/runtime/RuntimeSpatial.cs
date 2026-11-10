namespace DuelView.Runtime;

public sealed record SpatialNavigationCheckpoint(long Execution,string FromRoom,string ToRoom,string Authority,string Phase,
    double StartedAt,double Elapsed,double? DueAt,double RemainingDistance,double Speed,PathPoint? Target,bool PureMovement);
public sealed record SpatialAuthorityCheckpoint(bool Enabled,string VisibleRoom,SpatialNavigationCheckpoint[] Navigation);

public sealed partial class RuntimeSession
{
    private sealed class SpatialNavigation(Decision decision,string from,string to,bool pureMovement)
    {
        internal readonly Decision Decision=decision;
        internal readonly string FromRoom=from,ToRoom=to;
        internal readonly bool PureMovement=pureMovement;
        internal string Authority="godot",Phase="approaching";
        internal double StartedAt=decision.StartedAt,Elapsed,RemainingDistance,Speed=2.4;
        internal double? DueAt;
        internal PathPoint? Target;
    }
    private readonly Dictionary<long,SpatialNavigation> spatialNavigation=[];
    private bool spatialAuthorityEnabled,physicalClockInput;
    private string visibleRoom="";
    public bool HasHostNavigation=>spatialNavigation.Values.Any(n=>n.Authority=="godot"&&n.Phase=="approaching"&&Current(n.Decision,out var run)&&!run!.CancelRequested);
    public string VisibleRoom=>visibleRoom;

    /// <summary>The host declares residency, never actor location. Leaving a
    /// streamed room transfers only remaining navigation work to Core.</summary>
    public void ConfigureVisibleRoom(string room)
    {
        if(room is null)throw new ArgumentNullException(nameof(room));
        spatialAuthorityEnabled=true;visibleRoom=room;
        foreach(var nav in spatialNavigation.Values)
        {
            if(nav.Phase!="approaching"||!Current(nav.Decision,out _))continue;
            var present=World.Read(new(nav.Decision.Actor,"state","room"))?.Value.Text()==room&&room.Length>0;
            if(nav.Authority=="godot"&&!present)
            {
                nav.Authority="core";
                // A registered path supplies actual remaining metres. Before a
                // target is assembled, the author's finite logical approach
                // duration is the offscreen fallback, never a host completion.
                var remaining=nav.Target is not null?nav.RemainingDistance/nav.Speed:
                    nav.Decision.Action.Declaration.Get("offscreen_approach_seconds").Number(1);
                if(!double.IsFinite(remaining)||remaining<0)throw new InvalidDataException("Invalid logical approach duration.");
                nav.DueAt=Clock.Now+remaining;
            }
            else if(nav.Authority=="core"&&present)
            {
                nav.RemainingDistance=Math.Max(0,(nav.DueAt??Clock.Now)-Clock.Now)*nav.Speed;
                nav.Authority="godot";nav.DueAt=null;
                Clock.ClearUnsimulatedFastForward();
            }
        }
    }

    private bool BeginSpatialNavigation(Execution execution)
    {
        var decision=execution.Decision;var declaration=decision.Action.Declaration;
        // Legacy physical adapters retain their explicit HostElapsed contract.
        // The streamed campaign adapter owns ordinary focused interactions.
        if(!spatialAuthorityEnabled||execution.HostRequired||declaration.Get("focus").Text().Length==0)return false;
        var from=World.Read(new(decision.Actor,"state","room"))?.Value.Text()??"";
        if(from.Length==0)return false;
        var destination=execution.Effects.FirstOrDefault(e=>e.Key==new FieldKey(decision.Actor,"state","room")&&!e.Increment)?.Value.Text()??from;
        var pure=(declaration.Get("kind").Text() is "walk" or "travel")&&destination==from;
        var navigation=new SpatialNavigation(decision,from,destination,pure);
        if(from!=visibleRoom)
        {
            var logicalApproach=declaration.Get("offscreen_approach_seconds").Number();
            if(!double.IsFinite(logicalApproach)||logicalApproach<0)throw new InvalidDataException("Invalid logical approach duration.");
            navigation.Authority="core";navigation.DueAt=Clock.Now+logicalApproach;
        }
        spatialNavigation.Add(decision.Execution,navigation);
        execution.WorkStartedAt=null;execution.DueAt=double.PositiveInfinity;
        if(navigation.Authority=="godot")Clock.ClearUnsimulatedFastForward();
        return true;
    }

    public bool SetNavigationTarget(Decision decision,string room,double x,double y,double z,double remainingDistance,double speed)
    {
        if(!spatialNavigation.TryGetValue(decision.Execution,out var nav)||!Current(decision,out var execution)||execution!.CancelRequested||
           nav.Authority!="godot"||nav.Phase!="approaching"||room!=visibleRoom||room!=nav.FromRoom)return false;
        if(!double.IsFinite(x)||!double.IsFinite(y)||!double.IsFinite(z)||!double.IsFinite(remainingDistance)||remainingDistance<0||remainingDistance>10000||
           !double.IsFinite(speed)||speed<=0||speed>100)throw new InvalidDataException("Invalid real navigation target or path measurement.");
        nav.Target=new(x,y,z);nav.RemainingDistance=remainingDistance;nav.Speed=speed;
        return true;
    }

    public bool ReportNavigationProgress(Decision decision,double x,double y,double z,double remainingDistance)
    {
        if(!spatialNavigation.TryGetValue(decision.Execution,out var nav)||nav.Authority!="godot"||nav.Phase!="approaching"||
           nav.FromRoom!=visibleRoom||!Current(decision,out var execution)||execution!.CancelRequested)return false;
        if(!double.IsFinite(remainingDistance)||remainingDistance<0||remainingDistance>10000)throw new InvalidDataException("Invalid remaining navigation path.");
        var prior=Placement(decision.Actor);
        ReportPlacement(decision.Actor,x,y,z,prior?.Yaw??0,nav.FromRoom);nav.RemainingDistance=remainingDistance;
        return true;
    }

    public bool Arrive(Decision decision,double x,double y,double z)
    {
        if(!spatialNavigation.TryGetValue(decision.Execution,out var nav)||nav.Authority!="godot"||nav.Phase!="approaching"||nav.Target is not { } target||
           !Current(decision,out var execution)||execution!.CancelRequested||visibleRoom!=nav.FromRoom||
           World.Read(new(decision.Actor,"state","room"))?.Value.Text()!=nav.FromRoom||!PhysicalActionPermitted(decision))return false;
        if(!double.IsFinite(x)||!double.IsFinite(y)||!double.IsFinite(z)||target.DistanceTo(new(x,y,z))>0.4)return false;
        ReportNavigationProgress(decision,x,y,z,0);
        BeginSpatialWork(nav,execution);
        return true;
    }

    private void BeginSpatialWork(SpatialNavigation nav,Execution execution)
    {
        nav.Authority="core";nav.Phase=nav.ToRoom!=nav.FromRoom?"transit":"working";nav.DueAt=null;
        execution.WorkStartedAt=Clock.Now;
        execution.DueAt=nav.PureMovement?Clock.Now:Clock.Now+execution.Decision.Action.Duration;
        if(strategyBindings.TryGetValue(execution.Decision.Action.Id,out var strategy))
            strategy.Activity.Begin(Clock.Now,execution.Decision.Action.Duration/contentTimeUnit);
        completions.Enqueue(execution,execution.DueAt);
    }

    public void StepPhysical(double actualGameSeconds,bool paused=false,string? playerActor=null)
    {
        if(paused)return;
        Clock.SubmitPhysicalSeconds(actualGameSeconds);
        physicalClockInput=true;
        try{Step(0,false,false,playerActor);}
        finally{physicalClockInput=false;}
    }
    public void StepLogical(double gameSeconds,string? playerActor=null)
    {
        if(HasHostNavigation)throw new InvalidOperationException("Visible navigation needs actual Godot simulation time.");
        Clock.SubmitLogicalSeconds(gameSeconds);Step(0,false,false,playerActor);
    }

    private void AdvanceSpatialNavigation()
    {
        foreach(var nav in spatialNavigation.Values.ToArray())
        {
            if(!Current(nav.Decision,out var execution)){spatialNavigation.Remove(nav.Decision.Execution);continue;}
            if(nav.Phase=="approaching"&&nav.Authority=="core"&&nav.DueAt is { } due&&Clock.Now>=due&&!execution!.CancelRequested)
                BeginSpatialWork(nav,execution!);
        }
    }
    private double NextSpatialTime()=>spatialNavigation.Values.Where(n=>n.Phase=="approaching"&&n.Authority=="core"&&n.DueAt.HasValue)
        .Select(n=>n.DueAt!.Value).DefaultIfEmpty(double.PositiveInfinity).Min();
    private void ElapseSpatialNavigation(double seconds)
    {
        if(seconds<=0)return;
        foreach(var nav in spatialNavigation.Values.Where(n=>n.Phase=="approaching"))
        {
            nav.Elapsed+=seconds;
            if(nav.Authority=="core")nav.RemainingDistance=Math.Max(0,nav.RemainingDistance-seconds*nav.Speed);
        }
    }
    public object? ActorActivity(string actor)
    {
        if(!running.TryGetValue(actor,out var execution))return null;
        var decision=execution.Decision;
        if(spatialNavigation.TryGetValue(decision.Execution,out var nav))return new {
            execution=decision.Execution,action=decision.Action.Id,phase=execution.CancelRequested?"cancelling":nav.Phase,authority=nav.Authority,
            from_room=nav.FromRoom,to_room=nav.ToRoom,remaining_seconds=nav.Phase=="approaching"?nav.Authority=="core"?Math.Max(0,(nav.DueAt??Clock.Now)-Clock.Now):nav.RemainingDistance/nav.Speed:Math.Max(0,execution.DueAt-Clock.Now),
            requires_arrival=nav.Phase=="approaching"&&nav.Authority=="godot",navigation_elapsed_seconds=nav.Elapsed,
            work_started_at=execution.WorkStartedAt,work_ends_at=double.IsFinite(execution.DueAt)?(double?)execution.DueAt:null
        };
        var room=World.Read(new(actor,"state","room"))?.Value.Text()??"";
        var to=execution.Effects.FirstOrDefault(e=>e.Key==new FieldKey(actor,"state","room")&&!e.Increment)?.Value.Text()??room;
        return new {execution=decision.Execution,action=decision.Action.Id,phase=execution.CancelRequested?"cancelling":to!=room?"transit":"working",authority=execution.HostRequired?"godot":"core",
            from_room=room,to_room=to,remaining_seconds=double.IsFinite(execution.DueAt)?Math.Max(0,execution.DueAt-Clock.Now):0,
            requires_arrival=false,navigation_elapsed_seconds=0.0,work_started_at=execution.WorkStartedAt,work_ends_at=double.IsFinite(execution.DueAt)?(double?)execution.DueAt:null};
    }
    private SpatialAuthorityCheckpoint SaveSpatial()=>new(spatialAuthorityEnabled,visibleRoom,spatialNavigation.Values.Select(n=>new SpatialNavigationCheckpoint(
        n.Decision.Execution,n.FromRoom,n.ToRoom,n.Authority,n.Phase,n.StartedAt,n.Elapsed,n.DueAt,n.RemainingDistance,n.Speed,n.Target,n.PureMovement)).ToArray());
    private void RestoreSpatial(SpatialAuthorityCheckpoint? state,IReadOnlyDictionary<long,Decision> decisions)
    {
        spatialNavigation.Clear();spatialAuthorityEnabled=state?.Enabled??false;visibleRoom=state?.VisibleRoom??"";
        if(state is null)return;
        if(state.Navigation is null||state.Navigation.Select(n=>n.Execution).Distinct().Count()!=state.Navigation.Length)throw new InvalidDataException("Invalid saved navigation authority.");
        foreach(var saved in state.Navigation)
        {
            if(!decisions.TryGetValue(saved.Execution,out var decision)||!Current(decision,out _)||saved.Authority is not ("godot" or "core")||saved.Phase is not ("approaching" or "working" or "transit")||
               !double.IsFinite(saved.StartedAt)||saved.StartedAt<0||!double.IsFinite(saved.Elapsed)||saved.Elapsed<0||!double.IsFinite(saved.RemainingDistance)||saved.RemainingDistance<0||
               !double.IsFinite(saved.Speed)||saved.Speed<=0||saved.DueAt is { } due&&(!double.IsFinite(due)||due<0)||saved.Target is { } point&&(!double.IsFinite(point.X)||!double.IsFinite(point.Y)||!double.IsFinite(point.Z)))
                throw new InvalidDataException("Invalid saved navigation execution.");
            spatialNavigation.Add(saved.Execution,new(decision,saved.FromRoom,saved.ToRoom,saved.PureMovement){Authority=saved.Authority,Phase=saved.Phase,StartedAt=saved.StartedAt,
                Elapsed=saved.Elapsed,DueAt=saved.DueAt,RemainingDistance=saved.RemainingDistance,Speed=saved.Speed,Target=saved.Target});
        }
    }
}
