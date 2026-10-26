// FractalEngine.swift — Backend Fixed-Point 3D & Fractal Engine for Fractal3D
// Built with Swift 6.4 (`swift68k`) and `SwiftUI68k` for the Macintosh Plus (System 6.0.8, No FPU).

import MacToolbox
import SwiftUI68k

// MARK: - Reactive Application State

var gScene: Int32 = 0           // 0 = Torus, 1 = Poly, 2 = Mandelbrot, 3 = Julia
var gLastScene: Int32 = 0
var gShadeMode: Int32 = 0       // 0 = Dither, 1 = Wire, 2 = Spec
var gSpin: Int32 = 1
var gCull: Int32 = 1
var gPitch: Int32 = 34          // 0..100
var gYaw: Int32 = 22            // 0..100
var gZoom: Int32 = 68           // 20..100
var gLight: Int32 = 72          // 0..100
var gIter: Int32 = 20           // 8..32
var gCpuLoad: Int32 = 42

let kTagSpin: Int32    = 900
let kTagStep: Int32    = 901
let kTagZoomIn: Int32  = 902
let kTagZoomOut: Int32 = 903

// MARK: - 64-Entry Integer Sine/Cosine Table (-256 ... +256, Q8 Fixed-Point, No FPU)

private func sinQ8(_ idx: Int32) -> Int32 {
    let i = idx & 63
    let half = i & 31
    let q = half <= 16 ? half : (32 &- half)
    let mag: Int32
    switch q {
    case 0:  mag = 0
    case 1:  mag = 25
    case 2:  mag = 50
    case 3:  mag = 74
    case 4:  mag = 98
    case 5:  mag = 121
    case 6:  mag = 142
    case 7:  mag = 162
    case 8:  mag = 181
    case 9:  mag = 198
    case 10: mag = 213
    case 11: mag = 226
    case 12: mag = 237
    case 13: mag = 245
    case 14: mag = 251
    case 15: mag = 255
    default: mag = 256
    }
    return i >= 32 ? -mag : mag
}

private func cosQ8(_ idx: Int32) -> Int32 { sinQ8(idx &+ 16) }

// 4x4 Bayer threshold matrix (0..15) for 1-bit ordered dithering
private func bayer4x4(_ x: Int32, _ y: Int32) -> Int32 {
    let idx = ((y & 3) << 2) | (x & 3)
    switch idx {
    case 0: return 0;  case 1: return 8;  case 2: return 2;  case 3: return 10
    case 4: return 12; case 5: return 4;  case 6: return 14; case 7: return 6
    case 8: return 3;  case 9: return 11; case 10:return 1;  case 11:return 9
    case 12:return 15; case 13:return 7;  case 14:return 13; default:return 5
    }
}

// MARK: - 3D Fixed-Point Projection & Torus / Polyhedron Renderer

private func projectVertex(_ vx: Int32, _ vy: Int32, _ vz: Int32,
                           _ sx: Int32, _ cxRot: Int32, _ sy: Int32, _ cyRot: Int32,
                           _ scale: Int32, _ cx: Int32, _ cy: Int32,
                           _ px: inout Int32, _ py: inout Int32, _ pz: inout Int32) {
    let rx = (vx &* cyRot &+ vz &* sy) >> 8
    let rz1 = (vz &* cyRot &- vx &* sy) >> 8
    let ry = (vy &* cxRot &- rz1 &* sx) >> 8
    let rz = (vy &* sx &+ rz1 &* cxRot) >> 8

    let dist = 420 &- rz
    let d = dist < 140 ? 140 : dist
    px = cx &+ (rx &* scale) / d
    py = cy &+ (ry &* scale) / d
    pz = rz
}

private func torusPoint(_ u: Int32, _ v: Int32,
                        _ sx: Int32, _ cxRot: Int32, _ sy: Int32, _ cyRot: Int32,
                        _ scale: Int32, _ cx: Int32, _ cy: Int32,
                        _ px: inout Int32, _ py: inout Int32, _ pz: inout Int32) {
    let cu = cosQ8(u), su = sinQ8(u)
    let cv = cosQ8(v), sv = sinQ8(v)
    let ringR = 104 &+ ((44 &* cv) >> 8)
    let vx = (ringR &* cu) >> 8
    let vy = (ringR &* su) >> 8
    let vz = (44 &* sv) >> 8
    projectVertex(vx, vy, vz, sx, cxRot, sy, cyRot, scale, cx, cy, &px, &py, &pz)
}

private func drawQuad(_ x0: Int32, _ y0: Int32, _ x1: Int32, _ y1: Int32,
                      _ x2: Int32, _ y2: Int32, _ x3: Int32, _ y3: Int32) {
    MoveTo(Int16(x0), Int16(y0))
    LineTo(Int16(x1), Int16(y1))
    LineTo(Int16(x2), Int16(y2))
    LineTo(Int16(x3), Int16(y3))
    LineTo(Int16(x0), Int16(y0))
}

private func draw3DTorus(_ r: Rect) {
    let cx = (Int32(r.left) &+ Int32(r.right)) / 2
    let cy = (Int32(r.top) &+ Int32(r.bottom)) / 2
    let ax = (gPitch &* 64) / 100
    let ay = (gYaw &* 64) / 100
    let sx = sinQ8(ax), cxRot = cosQ8(ax)
    let sy = sinQ8(ay), cyRot = cosQ8(ay)
    let scale = 165 &+ (gZoom &* 140) / 100
    let lightBias = 80 &- (gLight / 2)

    var x0: Int32 = 0, y0: Int32 = 0, z0: Int32 = 0
    var x1: Int32 = 0, y1: Int32 = 0, z1: Int32 = 0
    var x2: Int32 = 0, y2: Int32 = 0, z2: Int32 = 0
    var x3: Int32 = 0, y3: Int32 = 0, z3: Int32 = 0

    var iu: Int32 = 0
    while iu < 16 {
        let u0 = (iu &* 4) & 63
        let u1 = ((iu &+ 1) &* 4) & 63
        var iv: Int32 = 0
        while iv < 8 {
            let v0 = (iv &* 8) & 63
            let v1 = ((iv &+ 1) &* 8) & 63

            torusPoint(u0, v0, sx, cxRot, sy, cyRot, scale, cx, cy, &x0, &y0, &z0)
            torusPoint(u1, v0, sx, cxRot, sy, cyRot, scale, cx, cy, &x1, &y1, &z1)
            torusPoint(u1, v1, sx, cxRot, sy, cyRot, scale, cx, cy, &x2, &y2, &z2)
            torusPoint(u0, v1, sx, cxRot, sy, cyRot, scale, cx, cy, &x3, &y3, &z3)

            // 2D screen-space normal (backface culling)
            let cross = (x1 &- x0) &* (y3 &- y0) &- (y1 &- y0) &* (x3 &- x0)
            if gCull == 0 || cross > 0 {
                drawQuad(x0, y0, x1, y1, x2, y2, x3, y3)
                // Specular / Lambertian 1-bit stipple inside bright front-facing facets
                let zAvg = (z0 &+ z2) >> 1
                if gShadeMode != 1 && zAvg > lightBias &- 25 {
                    let mx = (x0 &+ x1 &+ x2 &+ x3) >> 2
                    let my = (y0 &+ y1 &+ y2 &+ y3) >> 2
                    MoveTo(Int16(mx), Int16(my)); LineTo(Int16(mx), Int16(my))
                    if zAvg > lightBias {
                        MoveTo(Int16((mx &+ x0) >> 1), Int16((my &+ y0) >> 1))
                        LineTo(Int16((mx &+ x0) >> 1), Int16((my &+ y0) >> 1))
                        MoveTo(Int16((mx &+ x2) >> 1), Int16((my &+ y2) >> 1))
                        LineTo(Int16((mx &+ x2) >> 1), Int16((my &+ y2) >> 1))
                    }
                }
            }
            iv &+= 1
        }
        iu &+= 1
    }
}

private func draw3DPolyhedron(_ r: Rect) {
    let cx = (Int32(r.left) &+ Int32(r.right)) / 2
    let cy = (Int32(r.top) &+ Int32(r.bottom)) / 2
    let ax = (gPitch &* 64) / 100
    let ay = (gYaw &* 64) / 100
    let sx = sinQ8(ax), cxRot = cosQ8(ax)
    let sy = sinQ8(ay), cyRot = cosQ8(ay)
    let scale = 165 &+ (gZoom &* 140) / 100

    let s: Int32 = 86
    let p: Int32 = 138
    var cx0: Int32 = 0, cy0: Int32 = 0, cz: Int32 = 0
    var cx1: Int32 = 0, cy1: Int32 = 0, cx2: Int32 = 0, cy2: Int32 = 0
    var cx3: Int32 = 0, cy3: Int32 = 0, cx4: Int32 = 0, cy4: Int32 = 0
    var cx5: Int32 = 0, cy5: Int32 = 0, cx6: Int32 = 0, cy6: Int32 = 0
    var cx7: Int32 = 0, cy7: Int32 = 0

    projectVertex(-s, -s, -s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx0, &cy0, &cz)
    projectVertex( s, -s, -s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx1, &cy1, &cz)
    projectVertex( s,  s, -s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx2, &cy2, &cz)
    projectVertex(-s,  s, -s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx3, &cy3, &cz)
    projectVertex(-s, -s,  s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx4, &cy4, &cz)
    projectVertex( s, -s,  s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx5, &cy5, &cz)
    projectVertex( s,  s,  s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx6, &cy6, &cz)
    projectVertex(-s,  s,  s, sx, cxRot, sy, cyRot, scale, cx, cy, &cx7, &cy7, &cz)

    drawQuad(cx0, cy0, cx1, cy1, cx2, cy2, cx3, cy3)
    drawQuad(cx4, cy4, cx5, cy5, cx6, cy6, cx7, cy7)
    MoveTo(Int16(cx0), Int16(cy0)); LineTo(Int16(cx4), Int16(cy4))
    MoveTo(Int16(cx1), Int16(cy1)); LineTo(Int16(cx5), Int16(cy5))
    MoveTo(Int16(cx2), Int16(cy2)); LineTo(Int16(cx6), Int16(cy6))
    MoveTo(Int16(cx3), Int16(cy3)); LineTo(Int16(cx7), Int16(cy7))

    var ox0: Int32 = 0, oy0: Int32 = 0, ox1: Int32 = 0, oy1: Int32 = 0
    var ox2: Int32 = 0, oy2: Int32 = 0, ox3: Int32 = 0, oy3: Int32 = 0
    var ox4: Int32 = 0, oy4: Int32 = 0, ox5: Int32 = 0, oy5: Int32 = 0

    projectVertex( 0, -p,  0, sx, cxRot, sy, cyRot, scale, cx, cy, &ox0, &oy0, &cz)
    projectVertex( 0,  p,  0, sx, cxRot, sy, cyRot, scale, cx, cy, &ox1, &oy1, &cz)
    projectVertex(-p,  0,  0, sx, cxRot, sy, cyRot, scale, cx, cy, &ox2, &oy2, &cz)
    projectVertex( p,  0,  0, sx, cxRot, sy, cyRot, scale, cx, cy, &ox3, &oy3, &cz)
    projectVertex( 0,  0, -p, sx, cxRot, sy, cyRot, scale, cx, cy, &ox4, &oy4, &cz)
    projectVertex( 0,  0,  p, sx, cxRot, sy, cyRot, scale, cx, cy, &ox5, &oy5, &cz)

    drawQuad(ox2, oy2, ox4, oy4, ox3, oy3, ox5, oy5)
    drawQuad(ox0, oy0, ox2, oy2, ox1, oy1, ox3, oy3)
    drawQuad(ox0, oy0, ox4, oy4, ox1, oy1, ox5, oy5)
}

// MARK: - Q4.12 Fixed-Point Mandelbrot & Julia Set Renderer (4x4 Bayer 1-Bit Dither)

private func drawFractal(_ r: Rect, isJulia: Bool) {
    let left = Int32(r.left) &+ 2, right = Int32(r.right) &- 2
    let top = Int32(r.top) &+ 2, bottom = Int32(r.bottom) &- 2
    let w = right &- left
    let h = bottom &- top
    let maxIt = gIter < 8 ? 8 : gIter

    // Q4.12 fixed-point (4096 = 1.0). Zoom scales the complex plane window.
    let spanX = 15200 &- (gZoom &* 100)
    let spanY = (spanX &* h) / w
    let centerCr: Int32 = isJulia ? 0 : -2300
    let centerCi: Int32 = 0
    let juliaCr: Int32 = -2867 &+ (gPitch &- 34) &* 10
    let juliaCi: Int32 = 1106 &+ (gYaw &- 22) &* 10

    var py = top
    while py < bottom {
        let ci0 = centerCi &+ ((py &- top &- (h >> 1)) &* spanY) / h
        var px = left
        var runStart: Int32 = -1
        while px < right {
            let cr0 = centerCr &+ ((px &- left &- (w >> 1)) &* spanX) / w
            var zr = isJulia ? cr0 : 0
            var zi = isJulia ? ci0 : 0
            let cr = isJulia ? juliaCr : cr0
            let ci = isJulia ? juliaCi : ci0

            var it: Int32 = 0
            while it < maxIt {
                let zr2 = (zr &* zr) >> 12
                let zi2 = (zi &* zi) >> 12
                if (zr2 &+ zi2) > 16384 { break } // |z|^2 > 4.0
                zi = ((zr &* zi) >> 11) &+ ci
                zr = zr2 &- zi2 &+ cr
                it &+= 1
            }

            let level = (it &* 16) / maxIt
            var sub: Int32 = 0
            while sub < 2 && (px &+ sub) < right {
                let curX = px &+ sub
                let lit = (it < maxIt) && (gShadeMode == 1 ? ((it & 1) == 1) : (level > bayer4x4(curX, py)))
                if lit {
                    if runStart < 0 { runStart = curX }
                } else if runStart >= 0 {
                    MoveTo(Int16(runStart), Int16(py))
                    LineTo(Int16(curX &- 1), Int16(py))
                    runStart = -1
                }
                sub &+= 1
            }
            px &+= 2
        }
        if runStart >= 0 {
            MoveTo(Int16(runStart), Int16(py))
            LineTo(Int16(right &- 1), Int16(py))
        }
        py &+= 1
    }
}

let drawViewport: CanvasDrawC = { r, _ in
    PenNormal()
    PenPat(&qd.white)
    var box = r
    FrameRect(&box)

    let savedClip = NewRgn()
    GetClip(savedClip)
    var inner = box
    InsetRect(&inner, 1, 1)
    ClipRect(&inner)

    switch gScene {
    case 0: draw3DTorus(r)
    case 1: draw3DPolyhedron(r)
    case 2: drawFractal(r, isJulia: false)
    default:drawFractal(r, isJulia: true)
    }

    SetClip(savedClip)
    DisposeRgn(savedClip)
    PenNormal()
}

// MARK: - Scene Titles & Actions

func sceneTitle(_ s: Int32) -> StaticString {
    switch s {
    case 0: return "3D TORUS (128 QUADS)"
    case 1: return "3D OCTA + CUBE"
    case 2: return "MANDELBROT (Q4.12)"
    default: return "JULIA (-0.70 + 0.27i)"
    }
}

func sceneBadge(_ s: Int32) -> StaticString {
    switch s {
    case 0, 1: return gCull != 0 ? "CULL" : "WIRE"
    default:   return "BAYER"
    }
}

func applyScene(_ s: Int32) {
    gLastScene = s
    withUpdatesBatched {
        Binding(&gScene).value = s
        switch s {
        case 0:
            Binding(&gPitch).value = 34; Binding(&gYaw).value = 22
            Binding(&gZoom).value = 68;  Binding(&gIter).value = 20
            Binding(&gCpuLoad).value = 42
        case 1:
            Binding(&gPitch).value = 28; Binding(&gYaw).value = 38
            Binding(&gZoom).value = 72;  Binding(&gIter).value = 16
            Binding(&gCpuLoad).value = 30
        case 2:
            Binding(&gSpin).value = 0
            Binding(&gPitch).value = 34; Binding(&gYaw).value = 22
            Binding(&gZoom).value = 68;  Binding(&gIter).value = 20
            Binding(&gCpuLoad).value = 78
        default:
            Binding(&gSpin).value = 0
            Binding(&gPitch).value = 34; Binding(&gYaw).value = 22
            Binding(&gZoom).value = 64;  Binding(&gIter).value = 20
            Binding(&gCpuLoad).value = 84
        }
    }
}

func handleAction(_ tag: Int32) {
    switch tag {
    case kTagSpin:
        Binding(&gSpin).value = gSpin == 0 ? 1 : 0
    case kTagStep:
        withUpdatesBatched {
            Binding(&gPitch).value = (gPitch &+ 11) % 100
            Binding(&gYaw).value = (gYaw &+ 17) % 100
        }
    case kTagZoomIn:
        if gZoom <= 90 { Binding(&gZoom).value = gZoom &+ 10 }
    case kTagZoomOut:
        if gZoom >= 30 { Binding(&gZoom).value = gZoom &- 10 }
    default:
        break
    }
}
