import Foundation

/// Turns how far the menu bar item has been pulled onto the screen into a
/// timer length. The length grows faster the further the pull goes, and snaps
/// to steps that widen with it: single minutes up to 15, then 5, 15 and 30
/// minute steps, so the lengths set most often need the least precision.
public enum DragDial {
    /// A pull shorter than this sets nothing, so letting go back at the menu
    /// bar cancels.
    public static let deadZone = 16.0
    /// How far past the dead zone a pull goes for an hour. Straight down a
    /// laptop screen, 25 minutes is about a quarter of the way and the bottom
    /// edge is about three and a half hours.
    static let hourReach = 400.0
    /// Above 1, so short pulls change the length slowly and long ones quickly.
    static let curve = 1.6
    public static let longest = 12 * 3600

    /// Each step applies to lengths under its limit, in minutes.
    private static let steps: [(below: Double, minutes: Double)] = [(15, 1), (60, 5), (180, 15), (.infinity, 30)]

    /// The timer, in seconds, that a pull of `distance` points sets, or nil
    /// within the dead zone.
    public static func seconds(forDistance distance: Double) -> Int? {
        guard distance >= deadZone else { return nil }
        let minutes = 60 * pow((distance - deadZone) / hourReach, curve)
        let step = steps.first { minutes < $0.below }?.minutes ?? 30
        // Every limit is a whole number of the steps on both sides of it, so
        // snapping never steps back.
        let snapped = Int((minutes / step).rounded() * step)
        return min(longest, max(1, snapped) * 60)
    }
}
