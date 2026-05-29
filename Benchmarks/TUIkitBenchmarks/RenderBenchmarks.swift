//  🖥️ TUIKit — Terminal UI Kit for Swift
//  RenderBenchmarks.swift
//
//  Created by LAYERED.work
//  License: MIT

import Benchmark
import TUIkit

/// Whole-page render benchmarks. These exercise the full
/// pipeline — measure pass, render pass, modifier chain, focus
/// registration, container chrome — on shapes that look like
/// real pages so regressions on any of those layers surface
/// here.
enum RenderBenchmarks {

    static func register() {
        registerControlBenchmarks()
        registerPageShapeBenchmarks()
    }

    // MARK: - Individual control benchmarks

    /// Tiny single-control renders. These should be cheap;
    /// regressions here usually point at a constant-cost
    /// overhead being added per frame (focus registration,
    /// hover state machine, dispatcher feature requests, etc.).
    private static func registerControlBenchmarks() {
        Benchmark("render/Button (default style)") { benchmark in
            let view = Button("Save") { /* no-op */ }
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: standardContext())
                })
            }
        }

        Benchmark("render/TextField") { benchmark in
            let view = TextField("Search", text: .constant("hello"))
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: standardContext())
                })
            }
        }

        Benchmark("render/Toggle") { benchmark in
            let view = Toggle("Enable", isOn: .constant(true))
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: standardContext())
                })
            }
        }

        Benchmark("render/Slider") { benchmark in
            let view = Slider(value: .constant(0.5), in: 0...1, step: 0.01)
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: standardContext())
                })
            }
        }

        Benchmark("render/Stepper") { benchmark in
            let view = Stepper("Quantity", value: .constant(5), in: 0...10)
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: standardContext())
                })
            }
        }
    }

    // MARK: - Page-shape benchmarks

    /// A realistic 'form' page — heading, several labelled
    /// rows mixing TextField / Toggle / Slider, two action
    /// buttons. This is the shape most real pages take, and
    /// the page-render hot path TUIkit apps spend most of
    /// their time in.
    private static func registerPageShapeBenchmarks() {
        Benchmark("render/Mixed-form page") { benchmark in
            let view = VStack(alignment: .leading) {
                Text("Settings").bold().underline()
                HStack {
                    Text("Username:")
                    TextField("user", text: .constant("alice"))
                }
                HStack {
                    Text("Notifications:")
                    Toggle("On", isOn: .constant(true))
                }
                HStack {
                    Text("Volume:")
                    Slider(value: .constant(0.7), in: 0...1)
                }
                HStack {
                    Text("Retries:")
                    Stepper("Retries", value: .constant(3), in: 0...10)
                }
                HStack {
                    Button("Cancel") { }
                    Button("Save") { }
                }
            }
            for _ in benchmark.scaledIterations {
                blackHole(MainActor.assumeIsolated {
                    renderToBuffer(view, context: pageContext())
                })
            }
        }
    }
}
