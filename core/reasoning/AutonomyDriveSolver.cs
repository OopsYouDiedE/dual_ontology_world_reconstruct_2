namespace DuelView.Core;

/// <summary>Utility of actor-perceived need changes. No objective outcome or willingness is inferred from an action's name.</summary>
public static class AutonomyDriveSolver
{
    public static double Score(IReadOnlyDictionary<string, double> needs,
        IReadOnlyDictionary<string, double> weights, IReadOnlyDictionary<string, double> perceivedEffects,
        double seconds, double timeCost)
    {
        if (!double.IsFinite(seconds) || seconds <= 0 || !double.IsFinite(timeCost) || timeCost < 0)
            throw new FormatException("Invalid drive duration or time cost");
        double score = -seconds * timeCost;
        foreach (var (need, delta) in perceivedEffects)
        {
            if (!needs.TryGetValue(need, out var level) || !weights.TryGetValue(need, out var weight) ||
                !double.IsFinite(level) || level < 0 || level > 100 || !double.IsFinite(weight) || weight < 0 || !double.IsFinite(delta))
                throw new FormatException("Undeclared or invalid need: " + need);
            // Concave satisfaction: relieving a depleted need matters more than filling an already satisfied one.
            static double Satisfaction(double value) => value - value * value / 200;
            score += weight * (Satisfaction(Math.Clamp(level + delta, 0, 100)) - Satisfaction(level));
        }
        return double.IsFinite(score) ? score : throw new FormatException("Non-finite drive score");
    }
}
