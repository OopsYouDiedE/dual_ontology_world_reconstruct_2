namespace DuelView.Runtime;

public readonly record struct ReservationOwner(string Actor,long Execution);
public sealed record ReservationCheckpoint(ReservationOwner Owner,string[] Resources);

/// <summary>Session-owned standing/resource leases, independent of scene nodes.
/// One actor may retain a posture lease while its next execution acquires a slot.</summary>
public sealed class SlotReservations
{
    private sealed class Slot(int capacity)
    {
        internal readonly int Capacity=capacity;
        internal readonly Dictionary<string,HashSet<long>> Actors=new(StringComparer.Ordinal);
    }
    private readonly Dictionary<string,Slot> slots=new(StringComparer.Ordinal);
    private readonly Dictionary<ReservationOwner,HashSet<string>> owners=[];
    public ReservationCheckpoint[] SaveState()=>owners.Select(pair=>new ReservationCheckpoint(pair.Key,pair.Value.ToArray())).ToArray();
    public void RestoreState(ReservationCheckpoint[] state)
    {
        if(state is null || state.Select(item=>item.Owner).Distinct().Count()!=state.Length)throw new InvalidDataException("Invalid reservation checkpoint.");
        var counts=new Dictionary<string,HashSet<string>>(StringComparer.Ordinal);
        foreach(var item in state)
        {
            if(string.IsNullOrWhiteSpace(item.Owner.Actor)||item.Owner.Execution<0||item.Resources is null||item.Resources.Distinct(StringComparer.Ordinal).Count()!=item.Resources.Length)
                throw new InvalidDataException("Invalid reservation owner checkpoint.");
            foreach(var id in item.Resources)
            {
                if(!slots.ContainsKey(id))throw new InvalidDataException("Checkpoint references missing reservation: "+id);
                if(!counts.TryGetValue(id,out var actors))counts[id]=actors=new(StringComparer.Ordinal);
                actors.Add(item.Owner.Actor);
            }
        }
        if(counts.Any(item=>item.Value.Count>slots[item.Key].Capacity))throw new InvalidDataException("Checkpoint exceeds reservation capacity.");
        foreach(var slot in slots.Values)slot.Actors.Clear();owners.Clear();
        foreach(var item in state)if(!TryAcquire(item.Owner,item.Resources))throw new InvalidDataException("Cannot restore reservation checkpoint.");
    }

    public void Define(string id,int capacity)
    {
        if(string.IsNullOrWhiteSpace(id)||capacity<1)throw new ArgumentException("A standing resource needs an identity and positive capacity.");
        slots.Add(id,new(capacity));
    }

    public bool TryAcquire(ReservationOwner owner,IEnumerable<string> resources)
    {
        if(string.IsNullOrWhiteSpace(owner.Actor)||owner.Execution<0)throw new ArgumentException("A reservation needs an actor and execution identity.");
        var requested=resources.Distinct(StringComparer.Ordinal).ToArray();
        foreach(var id in requested)
        {
            var slot=slots[id];
            if(!slot.Actors.ContainsKey(owner.Actor)&&slot.Actors.Count>=slot.Capacity)return false;
        }
        if(!owners.TryGetValue(owner,out var held))owners.Add(owner,held=new(StringComparer.Ordinal));
        foreach(var id in requested)
        {
            var slot=slots[id];
            if(!slot.Actors.TryGetValue(owner.Actor,out var tickets))slot.Actors.Add(owner.Actor,tickets=[]);
            tickets.Add(owner.Execution);held.Add(id);
        }
        return true;
    }
    public bool CanAcquire(string actor,IEnumerable<string> resources)
    {
        foreach(var id in resources.Distinct(StringComparer.Ordinal))
        {
            if(!slots.TryGetValue(id,out var slot))throw new InvalidDataException("Unknown reservation slot: "+id);
            if(!slot.Actors.ContainsKey(actor)&&slot.Actors.Count>=slot.Capacity)return false;
        }
        return true;
    }
    public string[] Blocked(string actor,IEnumerable<string> resources)=>resources.Distinct(StringComparer.Ordinal)
        .Where(id=>!slots[id].Actors.ContainsKey(actor)&&slots[id].Actors.Count>=slots[id].Capacity).ToArray();

    public void Release(ReservationOwner owner)
    {
        if(!owners.Remove(owner,out var held))return;
        foreach(var id in held)
        {
            var occupants=slots[id].Actors;
            var tickets=occupants[owner.Actor];tickets.Remove(owner.Execution);
            if(tickets.Count==0)occupants.Remove(owner.Actor);
        }
    }

    public void Retain(ReservationOwner execution)
    {
        if(!owners.TryGetValue(execution,out var held))return;
        if(!TryAcquire(new(execution.Actor,0),held))throw new InvalidOperationException("An actor cannot lose its own occupied standing slot.");
        Release(execution);
    }

    public IReadOnlyCollection<string> Held(ReservationOwner owner)=>owners.TryGetValue(owner,out var held)?held.ToArray():[];
    public int Occupants(string id)=>slots[id].Actors.Count;
}
