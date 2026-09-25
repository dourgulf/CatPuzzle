import SwiftUI

/// A full-screen scrim with rounded-rect holes cut over the cells a guided
/// step leaves lit, drawn with an even-odd fill so the holes read as true
/// cutouts rather than a second layer on top. `holes` are in the same
/// coordinate space as whatever draws this shape — see `TutorialScreen`,
/// which resolves them from `BoardView.CellFrameKey` at its own top level so
/// the scrim covers the whole screen, not just the board.
struct TutorialSpotlightMask: Shape {
    var holes: [CGRect]
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for hole in holes {
            path.addPath(Path(roundedRect: hole, cornerRadius: cornerRadius))
        }
        return path
    }
}
