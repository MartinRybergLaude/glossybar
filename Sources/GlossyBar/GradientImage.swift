import AppKit

enum GradientImage {
    /// The gradient plus a near-identical twin: the two differ by one step in
    /// the green channel of the top pixel, which is under the specular hairline
    /// and invisible. `GlossView` alternates them to keep the window out of the
    /// window server's idle path.
    static func makePair(variant: GlossVariant, height: CGFloat,
                         scale: CGFloat) -> (CGImage, CGImage)? {
        guard let a = make(variant: variant, height: height, scale: scale),
              let b = make(variant: variant, height: height, scale: scale, jitterTopPixel: true)
        else { return nil }
        return (a, b)
    }

    /// Builds the 1×N shadow that falls under the bar: black, easing from
    /// `Shadow.peak * strength` to nothing. N is in *device* pixels, same as the
    /// gloss, so the falloff is smooth rather than stepped.
    ///
    /// Premultiplied, so the colour channels stay at zero and track the alpha.
    static func makeShadow(height: CGFloat, scale: CGFloat, strength: CGFloat) -> CGImage? {
        let rows = max(2, Int((height * scale).rounded()))
        let stops = Shadow.falloff

        func sample(_ t: CGFloat) -> CGFloat {
            if t <= stops[0].loc { return stops[0].level }
            for i in 1..<stops.count where t <= stops[i].loc {
                let a = stops[i - 1], b = stops[i]
                let f = b.loc == a.loc ? 0 : (t - a.loc) / (b.loc - a.loc)
                return a.level + (b.level - a.level) * f
            }
            return stops.last!.level
        }

        var bytes = [UInt8](repeating: 0, count: rows * 4)
        for row in 0..<rows {
            let alpha = Shadow.peak * strength * sample(CGFloat(row) / CGFloat(rows - 1))
            bytes[row * 4 + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 1, height: rows,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A pair that draws nothing, alternated in place of the gradient while the
    /// gloss is suspended.
    ///
    /// The keep-alive has to go on running through a transition. Stop nudging
    /// and the window server files the window as idle after about a second — so
    /// a Mission Control that lasts any time at all ends with the filter already
    /// dropped, and the first frame the gradient comes back on is a grey one.
    /// These two differ by a single step of alpha: enough to count as a change,
    /// far too little to see, and invisible whether or not the filter is being
    /// honoured at the time.
    static func makeBlankPair() -> (CGImage, CGImage)? {
        guard let a = blank(alpha: 0), let b = blank(alpha: 1) else { return nil }
        return (a, b)
    }

    private static func blank(alpha: UInt8) -> CGImage? {
        // Premultiplied, so the colour has to be black at these alphas anyway.
        let bytes: [UInt8] = [0, 0, 0, alpha]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 1, height: 1,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Builds the 1×N tone gradient that gets blended into the menu bar. N is in
    /// *device* pixels so the top hairline lands exactly on a pixel instead of
    /// being interpolated into a smudge.
    ///
    /// Row 0 is the top of the bar, matching how the stops read.
    static func make(variant: GlossVariant, height: CGFloat, scale: CGFloat,
                     jitterTopPixel: Bool = false) -> CGImage? {
        let rows = max(2, Int((height * scale).rounded()))
        let stops = variant.tone

        func sample(_ t: CGFloat) -> CGFloat {
            guard !stops.isEmpty else { return GlossVariant.neutral }
            if t <= stops[0].loc { return stops[0].tone }
            for i in 1..<stops.count where t <= stops[i].loc {
                let a = stops[i - 1], b = stops[i]
                let f = b.loc == a.loc ? 0 : (t - a.loc) / (b.loc - a.loc)
                return a.tone + (b.tone - a.tone) * f
            }
            return stops.last!.tone
        }

        var bytes = [UInt8](repeating: 0, count: rows * 4)
        for row in 0..<rows {
            var tone = sample(CGFloat(row) / CGFloat(rows - 1))

            // Specular hairline along the top edge, one device pixel.
            if row == 0 { tone = variant.topHighlight }

            let v = UInt8(max(0, min(255, (tone * 255).rounded())))
            let o = row * 4
            bytes[o] = v; bytes[o + 1] = v; bytes[o + 2] = v; bytes[o + 3] = 255
            if jitterTopPixel, row == 0 {
                bytes[o + 1] = v > 0 ? v - 1 : 1
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 1, height: rows,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
