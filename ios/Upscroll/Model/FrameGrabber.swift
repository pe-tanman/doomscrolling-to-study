import UIKit
import WebKit
import os

private let frameLog = Logger(subsystem: "com.upscroll.app", category: "frame")

/// Screenshot of just the playing video (not YouTube's buttons or account avatar), for the picture question.
/// Sent to the lesson server, which asks Jev what's in it. Only for Shorts with no talking.
enum FrameGrabber {
    /// Longest side sent to Jev (its limits: 280…1568 px per side).
    static let maxSide: CGFloat = 1024
    static let minSide: CGFloat = 280

    @MainActor
    /// `screenRect`: where the captured video area is on screen, so the frame can be laid back over it exactly.
    static func grab(_ web: WKWebView?) async -> (image: UIImage, jpeg: Data, screenRect: CGRect)? {
        guard let web else { return nil }
        // The largest on-screen <video> element, clipped to the viewport (CSS px = points at page zoom 1).
        let js = """
        (() => { let best = null, area = 0;
          for (const v of document.querySelectorAll('video')) {
            const r = v.getBoundingClientRect();
            const l = Math.max(r.left, 0), t = Math.max(r.top, 0);
            const w = Math.min(r.right, innerWidth) - l, h = Math.min(r.bottom, innerHeight) - t;
            if (w > 0 && h > 0 && w * h > area) { area = w * h; best = [l, t, w, h]; }
          }
          return best; })()
        """
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        if let a = (try? await web.evaluateJavaScript(js)) as? [NSNumber], a.count == 4, a[2].doubleValue > 120, a[3].doubleValue > 120 {
            config.rect = CGRect(x: a[0].doubleValue, y: a[1].doubleValue, width: a[2].doubleValue, height: a[3].doubleValue)
        }
        guard let shot = try? await web.takeSnapshot(configuration: config) else {
            frameLog.error("snapshot failed")
            return nil
        }
        // Resize in pixels: longest side ≤ maxSide, shortest side ≥ minSide.
        let px = CGSize(width: shot.size.width * shot.scale, height: shot.size.height * shot.scale)
        var k = min(1, maxSide / max(px.width, px.height))
        k = max(k, minSide / min(px.width, px.height))
        let size = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in shot.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = image.jpegData(compressionQuality: 0.75) else { return nil }
        frameLog.info("frame \(Int(size.width))x\(Int(size.height)) \(jpeg.count / 1024)KB")
        let area = config.rect.isNull || config.rect.isEmpty ? web.bounds : config.rect
        return (image, jpeg, web.convert(area, to: nil))
    }
}
