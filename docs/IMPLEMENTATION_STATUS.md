# Implementation and verification status

Updated 3 August 2026.

## Implemented

- Native iOS 26 SwiftUI app and generated Xcode project.
- Built-in iPhone microphone capture as mono 16-bit/16 kHz PCM with A2DP output enabled and Bluetooth HFP input excluded.
- Apple `SpeechTranscriber` with live `AnalysisContext`, plus internal `DictationTranscriber` fallback.
- Local sherpa-onnx streaming Mandarin Zipformer with checksum-pinned setup, 0.8-second endpointing, and correction-driven hotwords.
- Direct ElevenLabs Scribe v2 Realtime streaming with single-use relay token, 100 ms frames, Mandarin keyterms, and server VAD.
- Loop-safe three-recognizer fallback that exhausts viable on-device options before failing.
- Kimi K2.6 non-thinking translation with streamed partial previews, authoritative structured finals, prompt caching, corrected rolling context, and no unsupported temperature parameter.
- AirPods-only British-English speech with automatic Premium/Enhanced voice preference, a manual installed-voice picker, stale/out-of-order speech suppression, five-second backlog bound, mute and Replay.
- Revision-safe caption corrections and correction-driven local vocabulary with Undo.
- Protected, non-backed-up vocabulary; in-memory transcripts; protected temporary Markdown export and cleanup.
- Stateless authenticated Cloudflare relay, provider-safe logs, personal rate limits, and no audio path.
- Synthetic fixtures, private 36-clip manifest template, repeat-aware evaluator, critical-token gates, partial churn, corpus CER, and complete latency-target reporting.

## Automated checks completed

- Strict TypeScript check.
- 19 relay tests.
- 13 Swift core tests.
- 10 benchmark evaluator tests.
- Cloudflare Worker dry-run bundle with both rate-limit bindings.
- Cloudflare Worker deployed with rate-limit bindings and a healthy TLS endpoint at `mandarin-listener-relay.jasonadams-mandarin-listener.workers.dev`; the 256-bit client secret is configured and authenticated `/v1/auth/check` passed.
- Kimi secret configured in Cloudflare; a live structured translation returned HTTP 200 in 1.23 seconds (`你好，请坐。` → `Hello, please sit down.`). The temporary local API-key copy was deleted immediately afterward.
- The live Kimi preview endpoint returned HTTP 200 and began streaming in 0.97 seconds. The active Worker deployment has provider-safe observability enabled without transcript or credential logging.
- sherpa-onnx bridge and service type-checked against the published iOS C API.
- Full compatibility build and simulator launch completed with both XCFrameworks and all four model files packaged in the 217 MB app bundle.
- Runtime smoke test loaded the real Zipformer2 model, fell back Apple → Sherpa without a loop, acquired 16 kHz microphone frames, and remained in the active Listening state. This also caught and fixed the model-generation override and audio-tap actor isolation before device installation.
- Xcode project regenerated from `ios/project.yml`.
- Genuine Xcode 26.3 installed with the iOS 26.2 platform and iOS 26.3.1 simulator; the obsolete Xcode 16.4 bundle was permanently deleted.
- Apple Development signing identity and automatic Personal Team provisioning configured. The complete arm64 target compiles, signs, and installs successfully on the target iPhone. The final SDK check also replaced a provisional `AnalyzerInputConverter` dependency with an SDK-compatible streaming `AVAudioConverter` adapter.
- The rolling-preview build compiled, signed, installed, and launched successfully on the target iPhone.
- A fresh Personal Team profile was issued and the travel build was installed on 7 August 2026; iOS requires the one-time on-device trust confirmation before it will launch.
- A portable second-Mac bootstrap and travel handoff recreate all excluded speech dependencies without committing credentials, signing material, or generated binaries.
- Repository scan found no Qwen, Alibaba, DashScope, old ASR relay contracts, real credentials, or transcript/audio logging.

## Requires physical setup or private data

These are release gates, not completed claims:

- Trust the Personal Team developer profile on the target iPhone, then prove iPhone-microphone/AirPods-only routing before conversation use.
- Populate and run the private 36-human-clip benchmark three times per recognizer.
- Review all 30 Kimi cases and record the 27/30 meaning plus zero critical-error result.
- Complete lock-screen, interruption, network, provider-failure, correction, and 30-minute endurance checks.
- Complete three consented real conversations and meet the 80% gist / 4-of-5 usefulness gate.

Apple remains the default until the recorded benchmark demonstrates every ElevenLabs selection gate.
