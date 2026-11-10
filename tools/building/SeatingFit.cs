using System.Text.Json.Nodes;
using DuelView.Dv;

/// <summary>Author a candidate chair fit through the shared DV parser.</summary>
internal static class SeatingFit
{
    public static int Run(string[] args)
    {
        if(args.Length is not (5 or 6))throw new ArgumentException("--fit-seating SOURCE CHAIR HEIGHT OUTPUT [STAND_DISTANCE]");
        var source=Path.GetFullPath(args[1]);
        var document=DvDocument.Parse(File.ReadAllText(source));
        var root=JsonNode.Parse(document.Root.GetRawText())!;
        var space=root["data"]!["space.configurable_building"]!["value"]!;
        var matches=space["floors"]!.AsArray().SelectMany(floor=>floor!["furniture"]!.AsArray()).Where(item=>item!["id"]!.GetValue<string>()==args[2]).ToArray();
        if(matches.Length!=1||matches[0]!["kind"]!.GetValue<string>()!="chair")throw new InvalidDataException("Expected one authored chair.");
        var chair=matches[0]!;
        var height=double.Parse(args[3],System.Globalization.CultureInfo.InvariantCulture);
        var previous=chair["seat_height_m"]!.GetValue<double>();
        if(!double.IsFinite(height)||height<=.1||height>=chair["size"]![2]!.GetValue<double>())throw new InvalidDataException("Invalid chair seat height.");
        var difference=height-previous;
        var floorZ=chair["position"]![2]!.GetValue<double>();
        var interaction=chair["interaction"]!;
        if(args.Length==6)
        {
            var distance=double.Parse(args[5],System.Globalization.CultureInfo.InvariantCulture);
            if(!double.IsFinite(distance)||distance<=0)throw new InvalidDataException("Invalid standing distance.");
            foreach(var key in new[]{"stand","exit","approach"})interaction[key]![1]=chair["position"]![1]!.GetValue<double>()+distance;
        }
        foreach(var key in new[]{"sit","seat_surface","contact"})interaction[key]![2]=interaction[key]![2]!.GetValue<double>()+difference;
        foreach(var shape in interaction["collision_shapes"]!.AsArray())
        {
            var center=shape!["center"]!;var size=shape["size"]!;
            if(size[0]!.GetValue<double>()<.06&&size[1]!.GetValue<double>()<.06&&size[2]!.GetValue<double>()<previous)
            {size[2]=size[2]!.GetValue<double>()+difference;center[2]=floorZ+size[2]!.GetValue<double>()*.5;}
            else if(center[2]!.GetValue<double>()<floorZ+previous)center[2]=center[2]!.GetValue<double>()+difference;
        }
        chair["seat_height_m"]=height;
        var record=root["data"]!["space.configurable_building"]!.ToJsonString();
        var candidate=DvDocument.Parse("schema \"dv-script-v1\"; data \"space.configurable_building\" "+record+";");
        if(document.Root.GetProperty("data").EnumerateObject().Count()!=1)throw new InvalidDataException("Expected a single spatial declaration.");
        var output=Path.GetFullPath(args[4]);Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.WriteAllText(output,candidate.Source);
        Console.WriteLine($"CANDIDATE {output}\nCHAIR {args[2]} seat {previous:R} -> {height:R}\nSOURCE {document.Hash}\nCANDIDATE_HASH {candidate.Hash}");
        return 0;
    }
}
