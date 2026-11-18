using DuelView.RogueTopology;
using Godot;

public partial class HouseMap : RefCounted
{
    private const string Start = "foyer", Camp = "camp", Goal = "observatory";
    private static readonly string[] ApproachTemplates = ["gallery", "library", "kitchen", "conservatory", "stairwell"];
    private static readonly string[] ExpeditionTemplates = ["archive", "reservoir", "greenhouse", "attic", "mirror_hall"];
    private Layout? _layout;

    public bool generate(long seed)
    {
        _layout = CreateLayout(unchecked((ulong)seed));
        return _layout is not null;
    }

    public string start_room() => _layout is null ? "" : Start;
    public string camp_room() => _layout is null ? "" : Camp;
    public string goal_room() => _layout is null ? "" : Goal;

    // Godot marshals string[] to PackedStringArray. Return copies to isolate the layout.
    public string[] exits(string room) => _layout is { } layout && layout.Templates.ContainsKey(room)
        ? layout.Graph.GetExits(room).Select(exit => exit.DestinationRoomId).ToArray() : [];
    public string template_id(string room) => _layout?.Templates.GetValueOrDefault(room) ?? "";
    public string[] recruit_rooms() => _layout?.Recruits.ToArray() ?? [];

    private sealed record Layout(TopologyLayout Graph, Dictionary<string, string> Templates, string[] Recruits);

    private static Layout? CreateLayout(ulong seed)
    {
        var rng = new SeededChoices(seed);
        var templates = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Start] = "foyer", [Camp] = "base_camp", [Goal] = "observatory",
        };

        // Count both endpoints in this budget. Reserve at least one side room so every seed can branch.
        int arrivalDepth = 10 + rng.Next(10);
        int recruitCount = 1 + rng.Next(2);
        int[] depths = Enumerable.Range(1, arrivalDepth - 2).ToArray();
        rng.Shuffle(depths);
        var recruitDepths = depths.Take(recruitCount).ToHashSet();
        int sideRooms = 1 + rng.Next(Math.Min(20 - arrivalDepth, depths.Length - recruitCount));
        var expandedDepths = depths.Skip(recruitCount).Take(sideRooms).ToHashSet();
        var approach = MakeLayers(Start, Camp, "approach", arrivalDepth - 2, expandedDepths, ApproachTemplates);
        var recruits = recruitDepths.Order().Select(depth => approach[depth][0]).ToArray();

        int expeditionDepths = 4 + rng.Next(5);
        int[] expeditionCandidates = Enumerable.Range(1, expeditionDepths).ToArray();
        rng.Shuffle(expeditionCandidates);
        var expedition = MakeLayers(Camp, Goal, "expedition", expeditionDepths,
            expeditionCandidates.Take(1 + rng.Next(3)).ToHashSet(), ExpeditionTemplates);

        // The seed selects layer membership and gate locations, never a door state.
        // Camp is the sole room shared by the sections; only consecutive layers can touch.
        var layers = approach.Concat(expedition.Skip(1)).ToArray();
        var links = new List<RoomLink>();
        var slots = new List<RoomSlot>();
        for (int depth = 0; depth < layers.Length; ++depth)
        {
            string[] previous = depth == 0 ? [] : layers[depth - 1];
            string[] next = depth == layers.Length - 1 ? [] : layers[depth + 1];
            foreach (string room in layers[depth])
            {
                slots.Add(MakeSlot(room, previous, next));
                foreach (string neighbor in next)
                    links.Add(new RoomLink(room, neighbor, neighbor, room, Required: false));
            }
        }
        var problem = new TopologyProblem(Start, Goal, slots, links) { RequireAllRoomsReachable = true };
        var graph = TopologySolver.Solve(problem, seed);
        return graph is null ? null : new Layout(graph, templates, recruits);

        string[][] MakeLayers(string first, string last, string prefix, int depthCount,
            HashSet<int> expanded, string[] catalog)
        {
            var roomIds = Enumerable.Range(1, depthCount + expanded.Count).ToArray();
            rng.Shuffle(roomIds);
            var layers = new string[depthCount + 2][];
            layers[0] = [first];
            layers[^1] = [last];
            int cursor = 0;
            for (int depth = 1; depth <= depthCount; ++depth)
            {
                layers[depth] = new string[expanded.Contains(depth) ? 2 : 1];
                for (int i = 0; i < layers[depth].Length; ++i)
                {
                    string room = FormattableString.Invariant($"{prefix}_{roomIds[cursor++]:00}");
                    layers[depth][i] = room;
                    templates.Add(room, catalog[rng.Next(catalog.Length)]);
                }
            }
            return layers;
        }
    }

    private static RoomSlot MakeSlot(string room, string[] previous, string[] next)
    {
        var neighbors = previous.Concat(next).ToArray();
        int previousMask = (1 << previous.Length) - 1;
        int nextMask = ((1 << next.Length) - 1) << previous.Length;
        var candidates = new List<RoomTemplate>();
        for (int mask = 1; mask < (1 << neighbors.Length); ++mask)
        {
            // Require a predecessor and successor where those layers exist. The solver
            // chooses which neighbors satisfy these constraints by matching both endpoints.
            if ((previousMask != 0 && (mask & previousMask) == 0) ||
                (nextMask != 0 && (mask & nextMask) == 0)) continue;
            var ports = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int i = 0; i < neighbors.Length; ++i)
                if ((mask & (1 << i)) != 0) ports.Add(neighbors[i], "door");
            int weight = 1 << (neighbors.Length - ports.Count);
            candidates.Add(new RoomTemplate(FormattableString.Invariant($"doors_{mask}"), weight, ports));
        }
        return new RoomSlot(room, candidates);
    }

    private sealed class SeededChoices(ulong state)
    {
        public int Next(int count)
        {
            unchecked
            {
                // SplitMix64: all 64 bits of the public seed participate; do not depend on framework RNG versions.
                ulong z = (state += 0x9E3779B97F4A7C15UL);
                z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                return (int)((z ^ (z >> 31)) % (ulong)count);
            }
        }

        public void Shuffle(int[] items)
        {
            for (int i = items.Length - 1; i > 0; --i)
            {
                int j = Next(i + 1);
                (items[i], items[j]) = (items[j], items[i]);
            }
        }
    }
}
