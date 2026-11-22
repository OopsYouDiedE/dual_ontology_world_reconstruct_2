using DuelView.RogueTopology;
using Godot;

public partial class HouseMap : RefCounted
{
    private const string Start = "foyer", Camp = "camp", Goal = "observatory";
    private static readonly string[] RoomDesigns = ["kitchen", "lecture", "clinic", "dining", "valve_gallery", "service_stair"];
    private static readonly (string Stage, string Lot, string BranchLot)[] Approach =
    [
        ("returns", "clinic", "dining"), ("exchange", "lecture", "valve_gallery"),
        ("wash", "valve_gallery", "clinic"), ("lift", "service_stair", "valve_gallery"),
        ("airlock", "clinic", "dining"), ("shutter", "dining", "service_stair"),
    ];
    private static readonly (string Stage, string Lot, string BranchLot)[] OuterWing =
    [
        ("darkroom", "lecture", "clinic"), ("relay", "valve_gallery", "dining"),
    ];
    private Layout? _layout;

    public bool generate(long seed)
    {
        _layout = CreateLayout(unchecked((ulong)seed));
        return _layout is not null;
    }

    public bool generate_watch(long seed)
    {
        _layout = CreateWatchLayout(unchecked((ulong)seed));
        return _layout is not null;
    }

    // The campaign chart is in map coordinates: columns are watches, rows are lanes.
    // The solver can omit a cross-lane door, but must seat every room and join every fork.
    private static readonly string[][] Chart = [[Camp], ["west_1", "east_1"], ["west_2", "east_2"],
        ["turntable"], ["west_3", "east_3"], [Goal]];
    public int column(string room) => Array.FindIndex(Chart, layer => Array.IndexOf(layer, room) >= 0);
    public string[] forward(string room) => exits(room).Where(id => column(id) == column(room) + 1)
        .OrderBy(id => Array.IndexOf(Chart[column(id)], id)).ToArray();
    public bool generate_expedition(long value)
    {
        ulong seed = unchecked((ulong)value);
        var slots = new List<RoomSlot>();
        var links = new List<RoomLink>();
        for (int d = 0; d < Chart.Length; d++)
        {
            string[] prev = d == 0 ? [] : Chart[d-1], next = d+1 == Chart.Length ? [] : Chart[d+1];
            foreach (string room in Chart[d])
            {
                slots.Add(MakeSlot(room, prev, next));
                foreach (string dest in next)
                    links.Add(new RoomLink(room, dest, dest, room, Required: prev.Length == 0 || Chart[d].Length == 1 || next.Length == 1));
            }
        }
        var graph = TopologySolver.Solve(new TopologyProblem(Camp, Goal, slots, links) { RequireAllRoomsReachable = true }, seed);
        if (graph is null) { _layout = null; return false; }
        var stages = new Dictionary<string,string> { [Camp] = "hall", ["turntable"] = "shutter", [Goal] = "meridian" };
        var lots = new Dictionary<string,string> { [Camp] = "living_hall", ["turntable"] = "dining", [Goal] = "valve_gallery" };
        (string stage,string lot)[] deck = [("returns","clinic"),("exchange","lecture"),("wash","valve_gallery"),
            ("lift","service_stair"),("airlock","clinic"),("darkroom","lecture"),("relay","valve_gallery")];
        var order = Enumerable.Range(0,deck.Length).ToArray();
        new SeededChoices(seed ^ 0xA0761D6478BD642FUL).Shuffle(order);
        int n = 0;
        foreach (string room in Chart.SelectMany(layer => layer).Where(room => !stages.ContainsKey(room)))
            (stages[room], lots[room]) = deck[order[n++]];
        _layout = new Layout(graph,lots,[],stages);
        return true;
    }

    public string start_room() => _layout is null ? "" : _layout.Stages.ContainsKey("turntable") ? Camp : Start;
    public string camp_room() => _layout is null ? "" : Camp;
    public string goal_room() => _layout is null ? "" : Goal;

    // Godot marshals string[] to PackedStringArray. Return copies to isolate the layout.
    public string[] exits(string room) => _layout is { } layout && layout.Templates.ContainsKey(room)
        ? layout.Graph.GetExits(room).Select(exit => exit.DestinationRoomId).ToArray() : [];
    public string template_id(string room) => _layout?.Templates.GetValueOrDefault(room) ?? "";
    public string[] recruit_rooms() => _layout?.Recruits.ToArray() ?? [];

    public string room_stage(string room) => _layout?.Stages.GetValueOrDefault(room) ?? "";

    private sealed record Layout(TopologyLayout Graph, Dictionary<string, string> Templates, string[] Recruits, Dictionary<string, string> Stages);

    private static Layout? CreateLayout(ulong seed)
    {
        var rng = new SeededChoices(seed);
        var templates = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Start] = "foyer", [Camp] = "living_hall",
        };

        // Count both endpoints in this budget. Reserve at least one side room so every seed can branch.
        int arrivalDepth = 11 + rng.Next(9);
        int recruitCount = 1 + rng.Next(2);
        int[] depths = Enumerable.Range(1, arrivalDepth - 2).ToArray();
        rng.Shuffle(depths);
        var recruitDepths = depths.Take(recruitCount).ToHashSet();
        int sideRooms = 1 + rng.Next(Math.Min(20 - arrivalDepth, depths.Length - recruitCount));
        var expandedDepths = depths.Skip(recruitCount).Take(sideRooms).ToHashSet();
        var approach = MakeLayers(Start, Camp, "approach", arrivalDepth - 2, expandedDepths);
        var recruits = recruitDepths.Order().Select(depth => approach[depth][0]).ToArray();
        var stages = new Dictionary<string, string>(StringComparer.Ordinal);
        // Every path to the hall visits all three set pieces, even when a layer branches.
        foreach (string room in approach[3]) stages.Add(room, "echo");
        foreach (string room in approach[5]) stages.Add(room, "rain");
        foreach (string room in approach[7]) stages.Add(room, "rewrite");

        int expeditionDepths = 4 + rng.Next(5);
        int[] expeditionCandidates = Enumerable.Range(1, expeditionDepths).ToArray();
        rng.Shuffle(expeditionCandidates);
        var expedition = MakeLayers(Camp, Goal, "expedition", expeditionDepths,
            expeditionCandidates.Take(1 + rng.Next(3)).ToHashSet());

        // Keep template draws separate from the topology stream so existing seed layouts do not depend on the design catalog.
        var designs = new SeededChoices(seed ^ 0xA0761D6478BD642FUL);
        AssignDesigns(approach);
        AssignDesigns(expedition);
        templates.Add(Goal, designs.Next(2) == 0 ? "lecture" : "valve_gallery");

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
        return graph is null ? null : new Layout(graph, templates, recruits, stages);

        string[][] MakeLayers(string first, string last, string prefix, int depthCount,
            HashSet<int> expanded)
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
                }
            }
            return layers;
        }

        void AssignDesigns(string[][] section)
        {
            // Deal each design once per cycle; avoid a duplicate across the shuffle boundary.
            int[] deck = Enumerable.Range(0, RoomDesigns.Length).ToArray();
            int cursor = deck.Length, last = -1;
            foreach (string room in section.Skip(1).SkipLast(1).SelectMany(layer => layer))
            {
                if (cursor == deck.Length)
                {
                    designs.Shuffle(deck);
                    if (deck[0] == last) (deck[0], deck[1]) = (deck[1], deck[0]);
                    cursor = 0;
                }
                last = deck[cursor++];
                templates.Add(room, RoomDesigns[last]);
            }
        }
    }

    private static Layout? CreateWatchLayout(ulong seed)
    {
        var rng = new SeededChoices(seed);
        var templates = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Start] = "foyer", [Camp] = "living_hall",
        };

        // Recruit gates occupy unbranched layers. All seed routes meet the first survivor
        // before a doctrine conflict; an optional second survivor brings a third edition.
        int recruitCount = 1 + rng.Next(2);
        var eligible = recruitCount == 1 ? new[] { 2, 3, 4, 5, 6 } : [2, 4, 5, 6];
        rng.Shuffle(eligible);
        var expanded = eligible.Take(2 + rng.Next(2)).ToHashSet();
        var approach = MakeLayers(Start, Camp, "approach", Approach.Length, expanded);
        string[] recruits = recruitCount == 1 ? [approach[1][0]] : [approach[1][0], approach[3][0]];
        var expedition = MakeLayers(Camp, Goal, "expedition", OuterWing.Length, [1 + rng.Next(2)]);
        var stages = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Start] = "intake", [Camp] = "hall", [Goal] = "meridian",
        };
        AssignDesigns(approach, Approach);
        AssignDesigns(expedition, OuterWing);
        templates.Add(Goal, rng.Next(2) == 0 ? "lecture" : "valve_gallery");

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
        return graph is null ? null : new Layout(graph, templates, recruits, stages);

        string[][] MakeLayers(string first, string last, string prefix, int depthCount,
            HashSet<int> expanded)
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
                }
            }
            return layers;
        }

        void AssignDesigns(string[][] section, (string Stage, string Lot, string BranchLot)[] design)
        {
            for (int layer = 1; layer <= design.Length; ++layer)
            {
                var (stage, lot, branchLot) = design[layer - 1];
                for (int i = 0; i < section[layer].Length; ++i)
                {
                    string room = section[layer][i];
                    stages.Add(room, stage);
                    templates.Add(room, i == 0 ? lot : branchLot);
                }
            }
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
