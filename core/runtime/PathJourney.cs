namespace DuelView.Runtime;

public readonly record struct PathPoint(double X,double Y,double Z)
{
    public double DistanceTo(PathPoint other)
    {
        var x=X-other.X;var y=Y-other.Y;var z=Z-other.Z;
        return Math.Sqrt(x*x+y*y+z*z);
    }
}
public sealed record PathJourneyState(PathPoint[] Points,double Distance,bool CompletionTaken);

/// <summary>A single host-produced navigation path. Distance, not frame count,
/// is authoritative while an actor is outside the physical simulation range.</summary>
public sealed class PathJourney
{
    private readonly PathPoint[] points;
    private readonly double[] cumulative;
    public double Distance { get; private set; }
    public double Length => cumulative[^1];
    public bool Arrived => Distance>=Length;
    public bool CompletionTaken { get; private set; }
    public PathJourneyState SaveState()=>new(points.ToArray(),Distance,CompletionTaken);
    public static PathJourney RestoreState(PathJourneyState state)
    {
        var journey=new PathJourney(state.Points);
        if(!double.IsFinite(state.Distance)||state.Distance<0||state.Distance>journey.Length || state.CompletionTaken && state.Distance<journey.Length)
            throw new InvalidDataException("Invalid path journey checkpoint.");
        journey.Distance=state.Distance;journey.CompletionTaken=state.CompletionTaken;return journey;
    }

    public PathJourney(IEnumerable<PathPoint> route)
    {
        points=route.ToArray();
        if(points.Length<2 || points.Any(p=>!double.IsFinite(p.X)||!double.IsFinite(p.Y)||!double.IsFinite(p.Z)))
            throw new InvalidDataException("A journey requires a finite navigation path.");
        cumulative=new double[points.Length];
        for(var i=1;i<points.Length;i++)cumulative[i]=cumulative[i-1]+points[i-1].DistanceTo(points[i]);
        if(!double.IsFinite(Length)||Length<=0)throw new InvalidDataException("A journey requires a nonzero path.");
    }

    public PathPoint Position
    {
        get => PositionAt(Distance);
    }
    private PathPoint PositionAt(double distance)
    {
            var i=Array.BinarySearch(cumulative,distance);
            if(i>=0)return points[i];
            i=~i;
            var start=points[i-1];var end=points[i];
            var fraction=(distance-cumulative[i-1])/(cumulative[i]-cumulative[i-1]);
            return new(start.X+(end.X-start.X)*fraction,start.Y+(end.Y-start.Y)*fraction,start.Z+(end.Z-start.Z)*fraction);
    }

    public PathPoint Preview(double elapsedSeconds,double speed)
    {
        if(!double.IsFinite(elapsedSeconds)||elapsedSeconds<0||!double.IsFinite(speed)||speed<=0)
            throw new ArgumentOutOfRangeException(nameof(elapsedSeconds));
        return PositionAt(Math.Min(Length,Distance+elapsedSeconds*speed));
    }

    public void Advance(double elapsedSeconds,double speed)
    {
        if(!double.IsFinite(elapsedSeconds)||elapsedSeconds<0||!double.IsFinite(speed)||speed<=0)
            throw new ArgumentOutOfRangeException(nameof(elapsedSeconds));
        Distance=Math.Min(Length,Distance+elapsedSeconds*speed);
    }

    public bool TakeCompletion()
    {
        if(!Arrived||CompletionTaken)return false;
        CompletionTaken=true;return true;
    }
}
