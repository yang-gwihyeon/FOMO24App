import AppKit

let S: CGFloat = 1024

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    let dir = FileManager.default.currentDirectoryPath
    try! png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    print("wrote \(name).png")
}

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255,
            blue: CGFloat(v & 0xFF)/255, alpha: a)
}

func linearGradient(_ ctx: CGContext, _ c1: NSColor, _ c2: NSColor,
                    from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [c1.cgColor, c2.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

let tossBlue = 0x3182F6, tossBlueDark = 0x1B64DA, upRed = 0xF04452, navy = 0x16181D, navy2 = 0x242B38

/// 하트 패스 (unit 100, y-up, 아래가 뾰족).
func heartPath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x/100 * rect.width, y: rect.minY + y/100 * rect.height)
    }
    p.move(to: pt(50, 8))
    p.addCurve(to: pt(4, 70), control1: pt(20, 36), control2: pt(4, 52))
    p.addCurve(to: pt(26, 96), control1: pt(4, 86), control2: pt(14, 96))
    p.addCurve(to: pt(50, 78), control1: pt(36, 96), control2: pt(45, 89))
    p.addCurve(to: pt(74, 96), control1: pt(55, 89), control2: pt(64, 96))
    p.addCurve(to: pt(96, 70), control1: pt(86, 96), control2: pt(96, 86))
    p.addCurve(to: pt(50, 8), control1: pt(96, 52), control2: pt(80, 36))
    p.closeSubpath()
    return p
}

/// 번개 패스 (unit 100, y-up).
func boltPath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x/100 * rect.width, y: rect.minY + y/100 * rect.height)
    }
    p.move(to: pt(58, 100))
    p.addLine(to: pt(22, 42))
    p.addLine(to: pt(45, 42))
    p.addLine(to: pt(38, 0))
    p.addLine(to: pt(78, 56))
    p.addLine(to: pt(53, 56))
    p.closeSubpath()
    return p
}

// ── A. 볼트하트: 토스블루 그라데이션 + 흰 하트에 번개 컷아웃 ──────────
render("icon2-A-boltheart") { ctx in
    linearGradient(ctx, hex(tossBlue), hex(tossBlueDark),
                   from: CGPoint(x: S/2, y: S), to: CGPoint(x: S/2, y: 0))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
    ctx.fillEllipse(in: CGRect(x: -240, y: -240, width: 700, height: 700))
    ctx.fillEllipse(in: CGRect(x: 600, y: 580, width: 720, height: 720))

    // 하트 (그림자) + 번개 구멍 (even-odd)
    let heartRect = CGRect(x: 172, y: 180, width: 680, height: 640)
    let boltRect = CGRect(x: 392, y: 350, width: 240, height: 330)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60,
                  color: hex(0x0F3D8F, 0.45).cgColor)
    ctx.addPath(heartPath(in: heartRect))
    ctx.addPath(boltPath(in: boltRect))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath(using: .evenOdd)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

// ── B. 네온 하트: 다크 네이비 + 빨→파 그라데이션 하트 스트로크 + 상승 라인 ──
render("icon2-B-neonheart") { ctx in
    linearGradient(ctx, hex(navy2), hex(navy),
                   from: CGPoint(x: S/2, y: S), to: CGPoint(x: S/2, y: 0))

    let heartRect = CGRect(x: 182, y: 190, width: 660, height: 620)
    let stroked = heartPath(in: heartRect).copy(strokingWithWidth: 64, lineCap: .round,
                                                lineJoin: .round, miterLimit: 10)
    // 글로우
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 90, color: hex(upRed, 0.55).cgColor)
    ctx.addPath(stroked)
    ctx.setFillColor(hex(upRed, 0.28).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    // 그라데이션 스트로크 (포모 빨강 → 역포모 파랑)
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    linearGradient(ctx, hex(upRed), hex(tossBlue),
                   from: CGPoint(x: 250, y: 850), to: CGPoint(x: 800, y: 220))
    ctx.restoreGState()

    // 하트를 관통하는 흰 상승 라인 + 점
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(46)
    ctx.move(to: CGPoint(x: 330, y: 430))
    ctx.addLine(to: CGPoint(x: 470, y: 560))
    ctx.addLine(to: CGPoint(x: 560, y: 480))
    ctx.addLine(to: CGPoint(x: 700, y: 620))
    ctx.strokePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: 700 - 40, y: 620 - 40, width: 80, height: 80))
}

// ── C. 감정 스플릿: 대각 빨강/파랑 + 😭😌 컨셉의 미니멀 두 반쪽 하트 ────
render("icon2-C-split") { ctx in
    // 대각 스플릿 배경 (위-왼 빨강 = 포모, 아래-오른 파랑 = 역포모)
    ctx.setFillColor(hex(upRed).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    ctx.move(to: CGPoint(x: S, y: S))
    ctx.addLine(to: CGPoint(x: 0, y: 0))
    ctx.addLine(to: CGPoint(x: S, y: 0))
    ctx.closePath()
    ctx.setFillColor(hex(tossBlue).cgColor)
    ctx.fillPath()

    // 중앙 흰 하트 + 번개 컷아웃
    let heartRect = CGRect(x: 212, y: 220, width: 600, height: 570)
    let boltRect = CGRect(x: 407, y: 370, width: 210, height: 290)
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 70,
                  color: NSColor.black.withAlphaComponent(0.30).cgColor)
    ctx.addPath(heartPath(in: heartRect))
    ctx.addPath(boltPath(in: boltRect))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath(using: .evenOdd)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}
