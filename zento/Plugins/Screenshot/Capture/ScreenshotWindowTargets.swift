import CoreGraphics

// Front-to-back window metadata frozen before presenting the screenshot selection panels.
nonisolated enum ScreenshotWindowTargets {
    struct Surface {
        let id: CGWindowID
        let ownerPID: Int32?
        let layer: Int
        let frame: CGRect
    }

    struct Target {
        let windowID: CGWindowID
        let hitFrame: CGRect
        let captureFrame: CGRect
    }

    static func grouped(_ surfaces: [Surface]) -> [Target] {
        var roots = Array(surfaces.indices)
        // Work from back to front so a submenu can inherit the main window through its parent menu.
        for index in surfaces.indices.reversed() {
            let surface = surfaces[index]
            guard surface.layer > 0, let owner = surface.ownerPID else { continue }
            if let parent = surfaces.indices.dropFirst(index + 1).first(where: {
                let other = surfaces[$0]
                return other.ownerPID == owner && other.layer >= 0 && other.layer <= surface.layer
                    && surfaces[roots[$0]].layer == 0 && other.frame.intersects(surface.frame)
            }) {
                roots[index] = roots[parent]
            }
        }
        var frames: [Int: CGRect] = [:]
        for index in surfaces.indices {
            let root = roots[index]
            frames[root] = (frames[root] ?? .null).union(surfaces[index].frame)
        }
        return surfaces.indices.map { index in
            let root = roots[index]
            return Target(windowID: surfaces[root].id, hitFrame: surfaces[index].frame,
                          captureFrame: frames[root]!)
        }
    }
}
