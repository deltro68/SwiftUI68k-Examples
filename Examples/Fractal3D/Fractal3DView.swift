// Fractal3DView.swift — Declarative SwiftUI68k UI for Fractal3D
// Built with Swift 6.4 (`swift68k`) and `SwiftUI68k` for the Macintosh Plus (System 6.0.8).

import SwiftUI68k

// MARK: - Declarative View Hierarchy (`492 × 276` Macintosh Plus Window)

struct Fractal3DView: View {
    var viewKey: UInt32 {
        UInt32(bitPattern: (gScene << 24) ^ (gShadeMode << 20) ^ (gPitch << 12) ^ (gYaw << 6) ^ gZoom ^ (gLight << 3) ^ (gIter << 1) ^ gCull)
    }

    var body: some View {
        VStack(spacing: 6, alignment: .leading) {
            // Top Bar: Scene SegmentedPicker + Checkboxes + Animate/Pause Button
            HStack(.fit, spacing: 6) {
                SegmentedPicker(selection: Binding(&gScene)) {
                    Text("Torus").font(.bundledGeneva(9).bold())
                    Text("Poly").font(.bundledGeneva(9).bold())
                    Text("Mandelbrot").font(.bundledGeneva(9).bold())
                    Text("Julia").font(.bundledGeneva(9).bold())
                }
                Toggle("Cull", isOn: Binding(ptr: &gCull))
                Spacer()
                Button(gSpin != 0 ? "Pause" : "Animate", tag: kTagSpin).defaultButton()
            }

            // Main Split Workstation
            HStack(.fit, spacing: 10) {
                // Left Pane: Dark 1-Bit CRT Viewport Card (3D & Fractal Canvas)
                Card(.dark, padding: 6, spacing: 4) {
                    HStack(.fit, spacing: 4) {
                        Text(sceneTitle(gScene)).font(.bundledGeneva(9).bold()).aligned(.leading)
                        Spacer()
                        Badge(sceneBadge(gScene))
                    }
                    Canvas(244, 180, key: viewKey, draw: drawViewport)
                }

                Divider()

                // Right Pane: Camera, Shader & Iteration Controls
                VStack(spacing: 7, alignment: .leading) {
                    Text("Shader Mode").font(.bundledGeneva(9).bold()).aligned(.leading)
                    SegmentedPicker(selection: Binding(&gShadeMode)) {
                        Text("Dither").font(.bundledGeneva(9).bold())
                        Text("Wire").font(.bundledGeneva(9).bold())
                        Text("Spec").font(.bundledGeneva(9).bold())
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Pitch").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gPitch), in: 0...100, live: true, width: 112)
                        NumberText(gPitch, suffix: "°").font(.bundledGeneva(9)).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Yaw  ").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gYaw), in: 0...100, live: true, width: 112)
                        NumberText(gYaw, suffix: "°").font(.bundledGeneva(9)).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Zoom ").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gZoom), in: 20...100, live: true, width: 112)
                        NumberText(gZoom, suffix: "%").font(.bundledGeneva(9)).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Light").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Slider(value: Binding(&gLight), in: 0...100, live: true, width: 112)
                        NumberText(gLight, suffix: "%").font(.bundledGeneva(9)).aligned(.trailing)
                    }

                    HStack(.fit, spacing: 6) {
                        Text("Detail").font(.bundledGeneva(9).bold()).aligned(.leading)
                        Stepper(value: Binding(&gIter), in: 8...32, step: 4)
                        NumberText(gIter, suffix: " iter").font(.bundledGeneva(9)).aligned(.leading)
                        Spacer()
                        LevelMeter(value: gCpuLoad, segments: 6)
                    }

                    HStack(.equal, spacing: 6) {
                        Button("Step",   tag: kTagStep)
                        Button("Zoom -", tag: kTagZoomOut)
                        Button("Zoom +", tag: kTagZoomIn)
                    }
                }
            }
        }
    }
}

// MARK: - App Scene & Menus (`@main`)

@main
struct Fractal3DApp: App {
    var body: some Scene {
        Menu("File", id: 129) {
            MenuItem("Animate / Pause", shortcut: "P") { handleAction(kTagSpin) }
            MenuItem("Step Rotation", shortcut: "S") { handleAction(kTagStep) }
            MenuDivider()
            MenuItem("Quit", shortcut: "Q") { nextQuit() }
        }
        Menu("Scene", id: 130) {
            MenuItem("1: 3D Torus", shortcut: "1") { applyScene(0) }
            MenuItem("2: 3D Compound Polyhedron", shortcut: "2") { applyScene(1) }
            MenuItem("3: Mandelbrot Set (Q4.12)", shortcut: "3") { applyScene(2) }
            MenuItem("4: Julia Set (Q4.12)", shortcut: "4") { applyScene(3) }
        }
        Timer(every: 12) {
            if gScene != gLastScene {
                applyScene(gScene)
                return
            }
            if gSpin != 0 && gScene < 2 {
                withUpdatesBatched {
                    Binding(&gPitch).value = (gPitch &+ 4) % 100
                    Binding(&gYaw).value = (gYaw &+ 7) % 100
                }
            }
        }
        Window("Fractal3D", size: .fixed(492, 276), nodes: 128, arena: 768, onAction: handleAction) {
            Fractal3DView()
        }
    }
}
