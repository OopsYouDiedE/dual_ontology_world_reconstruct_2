using DuelView.Dv;
using Godot;

public partial class ModelCatalog : RefCounted
{
    public Godot.Collections.Array<Godot.Collections.Dictionary> ReadRoster()
    {
        var document = DvDocument.Parse(Godot.FileAccess.GetFileAsString("res://assets/data/character_models.dv"));
        var models = document.Definition("layouts", "migrated_character_models").GetProperty("models");
        var roster = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var model in models.EnumerateArray())
        {
            roster.Add(new Godot.Collections.Dictionary
            {
                ["character_id"] = model.GetProperty("character_id").GetString()!,
                ["label"] = model.GetProperty("label").GetString()!,
                ["path"] = model.GetProperty("path").GetString()!,
                ["height"] = model.GetProperty("height").GetDouble(),
                ["yaw_degrees"] = model.GetProperty("yaw_degrees").GetDouble()
            });
        }
        return roster;
    }
}
