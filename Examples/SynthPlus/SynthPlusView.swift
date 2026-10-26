// SynthPlusView.swift — Declarative SwiftUI68k UI for SynthPlus
// Built with Swift 6.4 (`swift68k`) and `SwiftUI68k` for the Macintosh Plus (System 6.0.8).

import SwiftUI68k

// MARK: - Declarative View Hierarchy (`492 × 276` Macintosh Plus Window)

struct SynthPlusView: View {
    var scopeKey: UInt32 {
        UInt32(bitPattern: (gPreset << 24) ^ (gWave << 20) ^ (gCutoff << 12) ^ (gReso << 4) ^ gPhase ^ (gChorus << 2) ^ gSub)
    }

    var envKey: UInt32 {
        UInt32(bitPattern: (gAttack << 24) ^ (gDecay << 16) ^ (gSustain << 8) ^ gRelease)
    }

    var body: some View {
        VStack(spacing: 6, alignment: .leading) {
            // Top Bar: Preset SegmentedPicker + Checkboxes + Tempo Stepper + Classic Mac Push Button
            HStack(.fit, spacing: 6) {
                SegmentedPicker(selection: Binding(&gPreset)) {
                    Text("Lead").font(.bundledGeneva(9).bold())
                    Text("Bass").font(.bundledGeneva(9).bold())
                    Text("Acid").font(.bundledGeneva(9).bold())
                    Text("Bell").font(.bundledGeneva(9).bold())
                }
                Toggle("Chorus", isOn: Binding(ptr: &gChorus))
                Toggle("Sub",    isOn: Binding(ptr: &gSub))
                Spacer()
                Stepper(value: Binding(&gBPM), in: 60...180, step: 4)
                NumberText(gBPM, suffix: " BPM").font(.bundledGeneva(9).bold()).aligned(.leading)
                Button(gPlaying != 0 ? "Stop" : "Play", tag: kTagPlay).defaultButton()
            }

            // Main Split Workstation Deck
            HStack(.fit, spacing: 10) {
                // Left Pane: Dark CRT Oscilloscope Card + Oscillator & Filter Controls
                VStack(spacing: 6, alignment: .leading) {
                    Card(.dark, padding: 6, spacing: 4) {
                        HStack(.fit, spacing: 4) {
                            Text(presetTitle(gPreset)).font(.bundledGeneva(9).bold()).aligned(.leading)
                            Spacer()
                            Badge(waveBadge(gWave))
                            if gChorus != 0 { Badge("CHORUS") } else if gSub != 0 { Badge("SUB") }
                        }
                        Text(presetSubtitle(gPreset)).font(.bundledGeneva(9)).aligned(.leading)
                        Canvas(224, 82, key: scopeKey, draw: drawOscilloscope)
                    }

                    SegmentedPicker(selection: Binding(&gWave)) {
                        Text("Sine").font(.bundledGeneva(9).bold())
                        Text("Square").font(.bundledGeneva(9).bold())
                        Text("Saw").font(.bundledGeneva(9).bold())
                        Text("FM").font(.bundledGeneva(9).bold())
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Cutoff").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gCutoff), in: 0...100, live: true, width: 138)
                        NumberText(gCutoff, suffix: "%").font(.bundledGeneva(9).bold()).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Reson.").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gReso), in: 0...100, live: true, width: 138)
                        NumberText(gReso, suffix: "%").font(.bundledGeneva(9).bold()).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Output").font(.bundledGeneva(9).bold()).aligned(.leading)
                        LevelMeter(value: gVU, segments: 12)
                        NumberText(gVU, suffix: " dB").font(.bundledGeneva(9)).aligned(.trailing)
                    }
                }

                Divider()

                // Right Pane: 8-Step Sequencer & ADSR Envelope Tabs
                VStack(spacing: 6, alignment: .leading) {
                    TabView(selection: Binding(&gTab)) {
                        Tab("Sequencer") {
                            List(rowCount: 8, rowHeight: 17, selection: Binding(&gStepSel), rows: 8,
                                 key: UInt32(bitPattern: gPreset)) { row, rect in
                                drawStepRow(row, rect)
                            }
                        }
                        Tab("Envelope") {
                            VStack(spacing: 5, alignment: .leading) {
                                Canvas(198, 42, key: envKey, draw: drawEnvelopeCurve)
                                HStack(.fit, spacing: 6) {
                                    Text("Attack").font(.bundledGeneva(9).bold()).aligned(.leading)
                                    Slider(value: Binding(&gAttack), in: 0...100, live: true, width: 108)
                                    NumberText(gAttack, suffix: " ms").font(.bundledGeneva(9)).aligned(.trailing)
                                }
                                HStack(.fit, spacing: 6) {
                                    Text("Decay ").font(.bundledGeneva(9).bold()).aligned(.leading)
                                    Slider(value: Binding(&gDecay), in: 0...100, live: true, width: 108)
                                    NumberText(gDecay, suffix: " ms").font(.bundledGeneva(9)).aligned(.trailing)
                                }
                                HStack(.fit, spacing: 6) {
                                    Text("Sust. ").font(.bundledGeneva(9).bold()).aligned(.leading)
                                    Slider(value: Binding(&gSustain), in: 0...100, live: true, width: 108)
                                    NumberText(gSustain, suffix: "%").font(.bundledGeneva(9)).aligned(.trailing)
                                }
                                HStack(.fit, spacing: 6) {
                                    Text("Rel.  ").font(.bundledGeneva(9).bold()).aligned(.leading)
                                    Slider(value: Binding(&gRelease), in: 0...100, live: true, width: 108)
                                    NumberText(gRelease, suffix: " ms").font(.bundledGeneva(9)).aligned(.trailing)
                                }
                            }
                        }
                    }

                    HStack(.equal, spacing: 6) {
                        Button("Random",  tag: kTagRand)
                        Button("-1 Semi", tag: kTagSemiDown)
                        Button("+1 Semi", tag: kTagSemiUp)
                    }
                }
            }
        }
    }
}

// MARK: - Application Entry Point (`@main`)

@main
struct SynthPlusApp: App {
    init() {
        _ = Timer(every: 18) {
            if gPreset != gLastPreset {
                applyPreset(gPreset)
                return
            }
            if gPlaying != 0 {
                let nextStep = (gStepSel &+ 1) & 7
                withUpdatesBatched {
                    Binding(&gStepSel).value = nextStep
                    Binding(&gPhase).value = (gPhase &+ 7) & 63
                    Binding(&gVU).value = (nextStep & 1) == 0 ? 86 : 68
                }
                playSynthStep(nextStep)
            }
        }
    }

    var body: some Scene {
        Menu(appleMenuTitle, id: 128) {
            MenuItem("About SynthPlus...") {
                alert("SynthPlus 1.0 — 1-Bit Synthesizer & 8-Step Sequencer in Swift 6.4 (SwiftUI68k) for Macintosh Plus.")
            }
        }
        Menu("File", id: 129) {
            MenuItem("Play / Stop", shortcut: "P") { handleSynthAction(kTagPlay) }
            MenuItem("Randomize Pattern", shortcut: "R") { handleSynthAction(kTagRand) }
            MenuSeparator()
            MenuItem("Quit", shortcut: "Q") { stopSynthSound(); SynthPlusApp.quit() }
        }
        Menu("Presets", id: 130) {
            MenuItem("A1 — Analog Lead", shortcut: "1") { applyPreset(0) }
            MenuItem("A2 — FM Bass",     shortcut: "2") { applyPreset(1) }
            MenuItem("B1 — Acid 303",    shortcut: "3") { applyPreset(2) }
            MenuItem("B2 — Chip Bell",   shortcut: "4") { applyPreset(3) }
        }
        Window("SynthPlus", size: .fixed(492, 276), nodes: 128, arena: 768, onAction: handleSynthAction) {
            SynthPlusView()
        }
    }
}
