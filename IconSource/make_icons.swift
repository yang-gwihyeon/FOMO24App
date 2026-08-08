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

func gradient(_ ctx: CGContext, _ top: NSColor, _ bottom: NSColor) {
    let colors = [top.cgColor, bottom.cgColor] as CFArray
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: S/2, y: S), end: CGPoint(x: S/2, y: 0), options: [])
}

func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255,
            blue: CGFloat(v & 0xFF)/255, alpha: a)
}

let tossBlue = 0x3182F6, tossBlueDark = 0x1B64DA, upRed = 0xF04452, navy = 0x16181D, navy2 = 0x232A36

// ── A. 펄스 라인: 다크 네이비 + 상승 라인차트 + 글로우 점 ──────────────
render("icon-A-pulse") { ctx in
    gradient(ctx, hex(navy2), hex(navy))

    // 은은한 그리드
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.05).cgColor)
    ctx.setLineWidth(3)
    for i in 1..<5 {
        let y = S * CGFloat(i) / 5
        ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: S, y: y))
    }
    ctx.strokePath()

    // 상승 폴리라인
    let pts = [CGPoint(x: 130, y: 330), CGPoint(x: 340, y: 500), CGPoint(x: 490, y: 400),
               CGPoint(x: 680, y: 640), CGPoint(x: 830, y: 580), CGPoint(x: 895, y: 700)]
    func path() {
        ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
    }
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    // 글로우
    ctx.setShadow(offset: .zero, blur: 70, color: hex(tossBlue, 0.9).cgColor)
    ctx.setStrokeColor(hex(tossBlue).cgColor)
    ctx.setLineWidth(58)
    path(); ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 끝점 점 (빨강 = 상승 시그널)
    let end = pts.last!
    ctx.setShadow(offset: .zero, blur: 60, color: hex(upRed, 0.95).cgColor)
    ctx.setFillColor(hex(upRed).cgColor)
    ctx.fillEllipse(in: CGRect(x: end.x - 52, y: end.y - 52, width: 104, height: 104))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: end.x - 22, y: end.y - 22, width: 44, height: 44))
}

// ── B. "24" 타이포: 토스 블루 그라데이션 + 흰 라운드 숫자 ──────────────
render("icon-B-24") { ctx in
    gradient(ctx, hex(tossBlue), hex(tossBlueDark))

    // 배경 장식: 큰 은은한 원
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
    ctx.fillEllipse(in: CGRect(x: -260, y: 560, width: 720, height: 720))
    ctx.fillEllipse(in: CGRect(x: 620, y: -300, width: 760, height: 760))

    let desc = NSFont.systemFont(ofSize: 560, weight: .heavy).fontDescriptor.withDesign(.rounded)!
    let font = NSFont(descriptor: desc, size: 560)!
    let attr: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.white, .kern: -20
    ]
    let str = NSAttributedString(string: "24", attributes: attr)
    let size = str.size()
    str.draw(at: CGPoint(x: (S - size.width)/2, y: (S - size.height)/2 + 40))

    // 숫자 아래 상승 언더라인 (빨강 틱)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.setLineWidth(44)
    ctx.move(to: CGPoint(x: 300, y: 235))
    ctx.addLine(to: CGPoint(x: 560, y: 235))
    ctx.strokePath()
    ctx.setStrokeColor(hex(upRed).cgColor)
    ctx.setLineWidth(44)
    ctx.move(to: CGPoint(x: 560, y: 235))
    ctx.addLine(to: CGPoint(x: 724, y: 320))
    ctx.strokePath()
}

// ── C. 캔들 3개: 라이트 배경 + 한국식 빨강/파랑 캔들 ──────────────────
render("icon-C-candles") { ctx in
    gradient(ctx, NSColor.white, hex(0xE9EFF7))

    func candle(x: CGFloat, bodyY: CGFloat, bodyH: CGFloat, wickTop: CGFloat, wickBottom: CGFloat, color: NSColor) {
        let w: CGFloat = 148
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(30)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: x, y: wickBottom)); ctx.addLine(to: CGPoint(x: x, y: wickTop))
        ctx.strokePath()
        ctx.setFillColor(color.cgColor)
        let r = CGRect(x: x - w/2, y: bodyY, width: w, height: bodyH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.fillPath()
        // 캔들 하이라이트
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        let hl = CGRect(x: x - w/2 + 22, y: bodyY + bodyH - 60, width: w - 44, height: 34)
        ctx.addPath(CGPath(roundedRect: hl, cornerWidth: 17, cornerHeight: 17, transform: nil))
        ctx.fillPath()
    }

    // 파랑(하락) — 빨강(상승) — 빨강(더 큰 상승) : 우상향 스토리
    candle(x: 250, bodyY: 380, bodyH: 240, wickTop: 700, wickBottom: 300, color: hex(tossBlue))
    candle(x: 512, bodyY: 430, bodyH: 300, wickTop: 810, wickBottom: 350, color: hex(upRed))
    candle(x: 774, bodyY: 540, bodyH: 340, wickTop: 950, wickBottom: 460, color: hex(upRed))
}
