using DuelView.Dv;
using System.Text.Json;

internal static class SpatialPublication
{
    public static int Run(string[] args)
    {
        if (args.Length != 3) throw new ArgumentException("--export-spatial-data <DV source> <generated JSON>");
        var output = Path.GetFullPath(args[2]);
        var generated = Path.GetFullPath(".runtime") + Path.DirectorySeparatorChar;
        if (!output.StartsWith(generated, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Compiled spatial data belongs in .runtime.");
        var document = DvScriptReader.Parse(File.ReadAllText(args[1]));
        var value = document.GetProperty("data").GetProperty("space.configurable_building").GetProperty("value");
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.WriteAllText(output, value.GetRawText());
        Console.WriteLine(output);
        return 0;
    }
}
