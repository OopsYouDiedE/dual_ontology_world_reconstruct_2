using System.Text.Json;

namespace DuelView.Runtime;

/// <summary>Static published geometry without a dynamic leaf must respect its
/// authored initial closure; lack of an animation node is never an open permit.</summary>
public static class PortalPolicy
{
    public static bool OpenWithoutLeaf(JsonElement aperture) =>
        !aperture.TryGetProperty("source_mechanism",out var mechanism) ||
        !mechanism.TryGetProperty("closed_at_start",out var closed) || closed.ValueKind!=JsonValueKind.True;
}
