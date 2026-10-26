// SynthEngine.swift — Backend DSP, Sound Manager PCM & Canvas Renderers for SynthPlus
// Built with Swift 6.4 (`swift68k`) and `SwiftUI68k` for the Macintosh Plus (System 6.0.8).

import MacToolbox
import SwiftUI68k

// MARK: - Synthesizer & Sequencer State (Static 68k Storage, Zero Heap Allocation)

var gPreset: Int32 = 0          // 0 = Lead, 1 = Bass, 2 = Acid, 3 = Bell
var gLastPreset: Int32 = 0
var gWave: Int32 = 2            // 0 = Sine, 1 = Square, 2 = Saw, 3 = FM
var gPlaying: Int32 = 1
var gBPM: Int32 = 120
var gCutoff: Int32 = 78
var gReso: Int32 = 45
var gVU: Int32 = 82
var gChorus: Int32 = 1
var gSub: Int32 = 0
var gTab: Int32 = 0             // 0 = Sequencer, 1 = Envelope
var gStepSel: Int32 = 0
var gPhase: Int32 = 14
var gAttack: Int32 = 18
var gDecay: Int32 = 55
var gSustain: Int32 = 68
var gRelease: Int32 = 42

let kTagPlay: Int32 = 810
let kTagRand: Int32 = 811
let kTagSemiDown: Int32 = 812
let kTagSemiUp: Int32 = 813

// MARK: - Integer 68000 Waveform Synthesis (No FPU)

private func sin32(_ idx: Int32) -> Int32 {
    switch idx & 31 {
    case 0: return 0;    case 1: return 20;   case 2: return 38;   case 3: return 56
    case 4: return 71;   case 5: return 83;   case 6: return 92;   case 7: return 98
    case 8: return 100;  case 9: return 98;   case 10: return 92;  case 11: return 83
    case 12: return 71;  case 13: return 56;  case 14: return 38;  case 15: return 20
    case 16: return 0;   case 17: return -20; case 18: return -38; case 19: return -56
    case 20: return -71; case 21: return -83; case 22: return -92; case 23: return -98
    case 24: return -100;case 25: return -98; case 26: return -92; case 27: return -83
    case 28: return -71; case 29: return -56; case 30: return -38; default: return -20
    }
}

private func evalSample(_ x: Int32, _ phase: Int32) -> Int32 {
    let p = (x &+ phase) & 63
    let s1 = sin32(p >> 1)
    let s2 = sin32(p)
    let s3 = sin32((p &* 3) >> 1)
    var y: Int32 = 0
    switch gWave {
    case 0: // Sine + resonant 2nd harmonic
        y = s1 &+ ((s2 &* gReso) / 180)
    case 1: // Square + resonant acid edge ringing
        let pulse: Int32 = (p < 32) ? 78 : -78
        y = pulse &+ ((s3 &* gReso) / 140)
    case 2: // Sawtooth + filter resonance peak
        let saw = ((p &* 160) / 63) &- 80
        y = saw &+ ((s2 &* gReso) / 150)
    default: // 2-Operator FM (carrier + modulator)
        let mod = (s2 &* (30 &+ gReso)) / 100
        y = sin32(((p >> 1) &+ (mod >> 3)) & 31)
    }
    if gSub != 0 {
        y = (y &* 3 &+ sin32(p >> 2) &* 2) / 4
    }
    let scale = 35 &+ (gCutoff &* 65) / 100
    return (y &* scale) / 100
}

// MARK: - Classic Mac Sound Manager Real-Time PCM Synthesizer (`SndPlay`)

private let kPcmSamples: Int = 1200     // ~108 ms per note at 11.127 kHz
private let kSndHdrBytes: Int = 42      // Format 1 'snd ' header (20B) + SoundHeader (22B)
private var gSndHandle: Handle? = nil
private var gSndChannel: SndChannelPtr? = nil
private var gStepPitch: InlineArray<8, Int32> = [20, 24, 30, 40, 36, 30, 27, 24]

private func writeU16(_ p: UnsafeMutablePointer<UInt8>, _ off: Int, _ v: UInt16) {
    p[off]     = UInt8((v >> 8) & 0xFF)
    p[off + 1] = UInt8(v & 0xFF)
}

private func writeU32(_ p: UnsafeMutablePointer<UInt8>, _ off: Int, _ v: UInt32) {
    p[off]     = UInt8((v >> 24) & 0xFF)
    p[off + 1] = UInt8((v >> 16) & 0xFF)
    p[off + 2] = UInt8((v >> 8) & 0xFF)
    p[off + 3] = UInt8(v & 0xFF)
}

func playSynthStep(_ step: Int32) {
    if gSndHandle == nil {
        gSndHandle = NewHandle(Size(kSndHdrBytes + kPcmSamples))
    }
    guard let h = gSndHandle else { return }
    if let old = gSndChannel {
        SndDisposeChannel(old, 1)
        gSndChannel = nil
    }
    HLock(h)
    guard let rawPtr = h.pointee else { HUnlock(h); return }
    let p = UnsafeMutableRawPointer(rawPtr).assumingMemoryBound(to: UInt8.self)

    // Format 1 'snd ' resource header + SoundHeader (11,127 Hz mono 8-bit offset binary)
    writeU16(p, 0, 1)                   // format = 1
    writeU16(p, 2, 1)                   // 1 data type
    writeU16(p, 4, 5)                   // sampledSynth = 5
    writeU32(p, 6, 0x0000_0080)         // initMono
    writeU16(p, 10, 1)                  // 1 sound command
    writeU16(p, 12, 0x8051)             // bufferCmd | dataOffsetFlag
    writeU16(p, 14, 0)                  // param1 = 0
    writeU32(p, 16, 20)                 // param2 = offset 20 to SoundHeader
    writeU32(p, 20, 0)                  // samplePtr = nil (inline sampleArea)
    writeU32(p, 24, UInt32(kPcmSamples))// length
    writeU32(p, 28, 0x2B77_45D1)        // sampleRate = rate11khz (11127.27 Hz)
    writeU32(p, 32, 0)                  // loopStart
    writeU32(p, 36, 0)                  // loopEnd
    p[40] = 0                           // encode = stdSH
    p[41] = 60                          // baseFrequency = kMiddleC

    // Render 8-bit PCM samples using the current waveform, filter, chorus & ADSR envelope
    let pitch = gStepPitch[Int(step & 7)]
    let attSamples = max(16, Int(gAttack) * 4)
    let relStart = kPcmSamples - max(64, Int(gRelease) * 6)
    var phaseAcc: Int32 = 0
    var i = 0
    while i < kPcmSamples {
        let ph = (phaseAcc >> 4) & 63
        var s = evalSample(ph, 0)
        if gChorus != 0 {
            let s2 = evalSample(((phaseAcc &* 65) >> 10) & 63, 9)
            s = (s &+ s2) / 2
        }
        var env: Int32 = 100
        if i < attSamples {
            env = Int32(i * 100 / attSamples)
        } else if i > relStart {
            let rem = kPcmSamples - i
            let span = kPcmSamples - relStart
            env = (gSustain &* Int32(rem)) / Int32(max(1, span))
        } else {
            env = gSustain &+ ((100 &- gSustain) &* Int32(kPcmSamples - i)) / Int32(kPcmSamples)
        }
        let pcm = 128 &+ ((s &* env) / 110)
        p[kSndHdrBytes + i] = UInt8(truncatingIfNeeded: max(8, min(248, pcm)))
        phaseAcc &+= pitch
        i &+= 1
    }

    var chan: SndChannelPtr? = nil
    if SndNewChannel(&chan, 0, 0, nil) == noErr, let c = chan {
        gSndChannel = c
        _ = SndPlay(c, SndListHandle(OpaquePointer(h)), 1)
    }
}

func stopSynthSound() {
    if let old = gSndChannel {
        SndDisposeChannel(old, 1)
        gSndChannel = nil
    }
    if let h = gSndHandle { HUnlock(h) }
}

// MARK: - CRT Oscilloscope & ADSR Envelope Canvases

let drawOscilloscope: CanvasDrawC = { r, _ in
    PenNormal()
    PenPat(&qd.white)
    var box = r
    FrameRect(&box)

    let left = Int32(r.left) &+ 2, right = Int32(r.right) &- 2
    let top = Int32(r.top) &+ 2, bottom = Int32(r.bottom) &- 2
    let midY = (top &+ bottom) / 2
    let halfH = (bottom &- top) / 2 &- 3

    // CRT graticule ticks & dotted zero-crossing axis
    var gx = left &+ 6
    while gx < right &- 4 {
        if (gx & 7) == 0 { MoveTo(Int16(gx), Int16(midY)); LineTo(Int16(gx), Int16(midY)) }
        if (gx &- left) % 36 == 0 {
            MoveTo(Int16(gx), Int16(top)); LineTo(Int16(gx), Int16(top &+ 2))
            MoveTo(Int16(gx), Int16(bottom &- 2)); LineTo(Int16(gx), Int16(bottom))
        }
        gx &+= 2
    }

    // Secondary detuned chorus trace (1px) when Chorus is active
    if gChorus != 0 {
        PenSize(1, 1)
        var x = left &+ 2, prevY = midY
        while x < right &- 2 {
            if (x & 1) == 0 {
                let s = evalSample(x &- left, gPhase &+ 9)
                let py = max(top &+ 2, min(bottom &- 2, midY &- (s &* halfH) / 100))
                if x > left &+ 2 { MoveTo(Int16(x &- 2), Int16(prevY)); LineTo(Int16(x), Int16(py)) }
                prevY = py
            }
            x &+= 1
        }
    }

    // Primary synthesized waveform trace (2px vertical beam)
    PenSize(1, 2)
    var x = left &+ 1, prevY = midY
    while x < right &- 2 {
        let s = evalSample(x &- left, gPhase)
        let py = max(top &+ 2, min(bottom &- 3, midY &- (s &* halfH) / 100))
        if x > left &+ 1 { MoveTo(Int16(x &- 1), Int16(prevY)); LineTo(Int16(x), Int16(py)) }
        prevY = py
        x &+= 1
    }
    PenNormal()
}

let drawEnvelopeCurve: CanvasDrawC = { r, _ in
    PenNormal()
    var box = r
    FrameRect(&box)

    let left = Int32(r.left) &+ 4, right = Int32(r.right) &- 4
    let top = Int32(r.top) &+ 4, bottom = Int32(r.bottom) &- 4
    let w = right &- left
    let h = bottom &- top

    let ax = left &+ (w &* max(5, gAttack)) / 320
    let dx = ax &+ (w &* max(8, gDecay)) / 320
    let sy = bottom &- (h &* gSustain) / 100
    let sx = right &- (w &* max(8, gRelease)) / 320

    PenSize(2, 2)
    MoveTo(Int16(left), Int16(bottom))
    LineTo(Int16(ax), Int16(top))
    LineTo(Int16(dx), Int16(sy))
    LineTo(Int16(sx), Int16(sy))
    LineTo(Int16(right), Int16(bottom))
    PenNormal()
}

// MARK: - Presets & 8-Step Sequencer Row Renderer

func presetTitle(_ p: Int32) -> StaticString {
    switch p {
    case 0: return "PATCH A1 — LEAD"
    case 1: return "PATCH A2 — BASS"
    case 2: return "PATCH B1 — ACID"
    default: return "PATCH B2 — BELL"
    }
}

func presetSubtitle(_ p: Int32) -> StaticString {
    switch p {
    case 0: return "A3 • 440 Hz • 4-Voice Poly"
    case 1: return "C3 • 262 Hz • 2-Op FM"
    case 2: return "F2 • 175 Hz • Filter"
    default: return "G4 • 784 Hz • 11.1 kHz PCM"
    }
}

func waveBadge(_ w: Int32) -> StaticString {
    switch w {
    case 0: return "SINE"
    case 1: return "SQUARE"
    case 2: return "SAW"
    default: return "FM"
    }
}

func drawStepRow(_ row: Int32, _ rect: Rect) {
    let notes: StaticString = (gPreset == 2)
        ? (row == 0 ? "01  F2"  : row == 1 ? "02  F3"  : row == 2 ? "03  D#3" : row == 3 ? "04  F2"
         : row == 4 ? "05  G#2" : row == 5 ? "06  C3"  : row == 6 ? "07  F3"  :            "08  D#3")
        : (row == 0 ? "01  A3"  : row == 1 ? "02  C4"  : row == 2 ? "03  E4"  : row == 3 ? "04  A4"
         : row == 4 ? "05  G4"  : row == 5 ? "06  E4"  : row == 6 ? "07  D4"  :            "08  C4")
    let gates: Int16 = (row == 0 || row == 7) ? 58 : (row == 2 ? 50 : (row == 5 ? 26 : 42))
    let tag: StaticString = (row == 0 || row == 3 || row == 7) ? "ACC" : (row == 2 || row == 4 ? "LEG" : "GATE")

    let leftCol = Rect(top: rect.top, left: rect.left, bottom: rect.bottom, right: rect.left + 72)
    drawRowText(notes.utf8Start, leftCol)

    PenNormal()
    let barLeft: Int16 = rect.left + 72, barTop: Int16 = rect.top + 3, barBot: Int16 = rect.bottom - 3
    var track = Rect(top: barTop, left: barLeft, bottom: barBot, right: barLeft + 62)
    FrameRect(&track)
    var fill = Rect(top: barTop + 2, left: barLeft + 2, bottom: barBot - 2, right: barLeft + gates)
    PaintRect(&fill)

    let tagRect = Rect(top: rect.top, left: rect.left + 140, bottom: rect.bottom, right: rect.right - 2)
    drawRowText(tag.utf8Start, tagRect)
}

func applyPreset(_ p: Int32) {
    gLastPreset = p
    withUpdatesBatched {
        Binding(&gPreset).value = p
        switch p {
        case 0: // Analog Lead
            Binding(&gWave).value = 2; Binding(&gCutoff).value = 78; Binding(&gReso).value = 45
            Binding(&gBPM).value = 120; Binding(&gChorus).value = 1
            Binding(&gSub).value = 0; Binding(&gVU).value = 82
        case 1: // FM Bass
            Binding(&gWave).value = 3; Binding(&gCutoff).value = 65; Binding(&gReso).value = 70
            Binding(&gBPM).value = 128; Binding(&gChorus).value = 0
            Binding(&gSub).value = 1; Binding(&gVU).value = 75
        case 2: // Acid 303
            Binding(&gWave).value = 1; Binding(&gCutoff).value = 52; Binding(&gReso).value = 90
            Binding(&gBPM).value = 136; Binding(&gChorus).value = 0
            Binding(&gSub).value = 1; Binding(&gVU).value = 92
        default: // Chip Bell
            Binding(&gWave).value = 0; Binding(&gCutoff).value = 88; Binding(&gReso).value = 30
            Binding(&gBPM).value = 144; Binding(&gChorus).value = 1
            Binding(&gSub).value = 1; Binding(&gVU).value = 86
        }
    }
    playSynthStep(gStepSel)
}

func handleSynthAction(_ tag: Int32) {
    switch tag {
    case kTagPlay:
        let next = gPlaying == 0 ? Int32(1) : Int32(0)
        Binding(&gPlaying).value = next
        if next != 0 { playSynthStep(gStepSel) } else { stopSynthSound() }
    case kTagRand:
        Binding(&gPhase).value = (gPhase &+ 19) & 63
        Binding(&gStepSel).value = (gStepSel &+ 3) & 7
        playSynthStep(gStepSel)
    case kTagSemiDown:
        if gStepSel > 0 { Binding(&gStepSel).value = gStepSel &- 1 }
        let idx = Int(gStepSel & 7)
        if gStepPitch[idx] > 12 { gStepPitch[idx] &-= 2 }
        playSynthStep(gStepSel)
    case kTagSemiUp:
        if gStepSel < 7 { Binding(&gStepSel).value = gStepSel &+ 1 }
        let idx = Int(gStepSel & 7)
        if gStepPitch[idx] < 56 { gStepPitch[idx] &+= 2 }
        playSynthStep(gStepSel)
    default:
        break
    }
}
