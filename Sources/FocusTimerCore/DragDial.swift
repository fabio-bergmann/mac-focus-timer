import CoreGraphics
import Foundation

/// Turns how far the menu bar item has been pulled onto the screen into a
/// timer length, in whole minutes, or in quarter hours while Command is held.
/// The length grows faster the further the pull goes, so short lengths are
/// the easiest to set exactly.
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
    /// The step, in minutes, while Command is held.
    public static let coarseStep = 15

    /// Where a line from the middle of `item` to `point` leaves it, which is
    /// where a pull is drawn and measured from. Nil while `point` is inside.
    public static func exit(from item: CGRect, toward point: CGPoint) -> CGPoint? {
        let dx = point.x - item.midX
        let dy = point.y - item.midY
        // How far along the line the edge comes, as a share of its length.
        let share = min(
            dx == 0 ? .infinity : item.width / 2 / abs(dx),
            dy == 0 ? .infinity : item.height / 2 / abs(dy)
        )
        guard share < 1 else { return nil }
        return CGPoint(x: item.midX + dx * share, y: item.midY + dy * share)
    }

    /// The timer, in seconds, that a pull of `distance` points sets, rounded
    /// to `step` minutes, or nil within the dead zone.
    public static func seconds(forDistance distance: Double, step: Int = 1) -> Int? {
        guard distance >= deadZone else { return nil }
        let minutes = 60 * pow((distance - deadZone) / hourReach, curve)
        let snapped = Int((minutes / Double(step)).rounded()) * step
        return min(longest, max(step, snapped) * 60)
    }
}
