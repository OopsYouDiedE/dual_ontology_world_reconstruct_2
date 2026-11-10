using System.Numerics;

namespace DuelView.Runtime;

public readonly record struct RoomSightLink(string From, string To, bool IntersectsView, bool Open);

/// <summary>Metre-space conservative room bounds and exact convex aperture clipping.
/// Planes face inward: dot(normal, point) + D is nonnegative inside the view.
/// The host supplies camera planes and DV-authored aperture vertices.</summary>
public static class RoomVisibility
{
    public static HashSet<string> ReachableRooms(IEnumerable<string> seeds, IReadOnlyList<RoomSightLink> links, bool prepareBehindClosedDoors)
    {
        var result=new HashSet<string>(seeds);
        var frontier=new Queue<string>(result);
        while(frontier.TryDequeue(out var room))
            foreach(var link in links)
                if(link.From==room && link.IntersectsView && (link.Open || prepareBehindClosedDoors) && result.Add(link.To))
                    frontier.Enqueue(link.To);
        return result;
    }

    public static bool IntersectsBounds(Vector3 minimum, Vector3 maximum, IReadOnlyList<Plane> planes)
    {
        ValidatePoint(minimum); ValidatePoint(maximum); ValidatePlanes(planes);
        if (minimum.X > maximum.X || minimum.Y > maximum.Y || minimum.Z > maximum.Z)
            throw new ArgumentException("Bounds must be ordered.");
        foreach (var plane in planes)
        {
            var support = new Vector3(plane.Normal.X >= 0 ? maximum.X : minimum.X,
                plane.Normal.Y >= 0 ? maximum.Y : minimum.Y,
                plane.Normal.Z >= 0 ? maximum.Z : minimum.Z);
            if (Plane.DotCoordinate(plane, support) < 0) return false;
        }
        return true;
    }

    public static IReadOnlyList<Vector3> ClipAperture(IReadOnlyList<Vector3> aperture, IReadOnlyList<Plane> planes)
    {
        ValidatePlanes(planes);
        if (aperture.Count < 3) throw new ArgumentException("An aperture requires a convex polygon.");
        foreach (var point in aperture) ValidatePoint(point);
        var polygon = aperture.ToList();
        foreach (var plane in planes)
        {
            if (polygon.Count == 0) break;
            var output = new List<Vector3>();
            var previous = polygon[^1];
            var previousDistance = Plane.DotCoordinate(plane, previous);
            foreach (var current in polygon)
            {
                var distance = Plane.DotCoordinate(plane, current);
                if ((distance >= 0) != (previousDistance >= 0))
                    output.Add(Vector3.Lerp(previous, current, previousDistance / (previousDistance - distance)));
                if (distance >= 0) output.Add(current);
                previous = current; previousDistance = distance;
            }
            polygon = output;
        }
        return polygon;
    }

    private static void ValidatePoint(Vector3 point)
    {
        if (!float.IsFinite(point.X) || !float.IsFinite(point.Y) || !float.IsFinite(point.Z))
            throw new ArgumentException("Spatial coordinates must be finite.");
    }

    private static void ValidatePlanes(IReadOnlyList<Plane> planes)
    {
        if (planes.Count == 0) throw new ArgumentException("View planes are required.");
        foreach (var plane in planes)
        {
            ValidatePoint(plane.Normal);
            if (!float.IsFinite(plane.D) || plane.Normal.LengthSquared() == 0)
                throw new ArgumentException("View planes must have finite nonzero normals.");
        }
    }
}
