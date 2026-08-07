# Recognition and translation benchmarks

The benchmark has two deliberately separate suites:

- The 24 generated clips in `manifest.json` are deterministic regression fixtures. They exercise names, numbers, dates, negation, rapid delivery, and two macOS system voices, but they are synthetic and must **not** select the production recognizer.
- The private 36-clip human suite is the Apple-versus-ElevenLabs selection benchmark: 24 CC0 Mandarin clips from [Mozilla Common Voice](https://dev.mozilladatacollective.com/datasets/cmj8lv9je00g9nlf6m2fa6z92) and 12 consented recordings made with the target iPhone.

No human audio, reference transcript, or provider result belongs in Git. The entire `benchmarks/private/` directory is ignored.

## Synthetic regression suite

On macOS, regenerate the tracked mono 16-bit/16 kHz WAV files with:

```sh
make benchmark-audio
```

Replay the files through Apple and ElevenLabs after recognizer or audio-framing changes. Evaluate them with the default manifest:

```sh
node benchmarks/evaluate-asr.mjs \
  benchmarks/private/synthetic-apple-results.json \
  benchmarks/private/synthetic-elevenlabs-results.json
```

Treat regressions as implementation warnings. A synthetic result must never override the human selection gate.

## Build the human suite

1. Copy `human-manifest.template.json` to the ignored path `private/human-manifest.json`.
2. Select 24 Mandarin Common Voice clips released under CC0. Use at least 12 distinct speakers; do not choose multiple takes of the same sentence. Record the dataset version and source clip identifier in the manifest.
3. Obtain informed consent for 12 iPhone recordings. Cover rapid standard Mandarin, regional pronunciation, ordinary room noise, names, numbers/dates, negation, and self-correction. Fill `consentRecorded: true` only after consent is documented outside the repository.
4. Convert copies—not source masters—to mono 16-bit/16 kHz PCM. Put them below `benchmarks/private/human-audio/`.
5. Produce a verbatim Simplified-Chinese reference transcript. Review each transcript twice while listening, and resolve unclear speech before testing rather than guessing.
6. Fill `criticalSpans` for every name, number, date, time, and negation whose corruption could alter meaning. Each span accepts one or more equivalent written forms:

```json
{
  "kind": "number",
  "accepted": ["四点二十五分", "4点25分", "16点25分", "16:25"],
  "safetyCritical": true
}
```

`safetyCritical` is required for the designated number and negation safety set. The evaluator refuses to award ElevenLabs the default when critical annotations or safety annotations are absent.

Before running, verify the manifest contains exactly 24 `common_voice_cc0` clips, 12 `consented_private` clips, at least 12 distinct non-empty speaker IDs, and no unfinished reference text. The evaluator validates completeness but the source mix and consent record also require human review.

## Run identical trials

For each provider, replay every file three times in the same order:

- Stream 100 ms frames at realtime speed; do not upload the whole file as a batch.
- Start timing at the known end of speech and stop at the provider’s final/committed event.
- Start each clip with a fresh utterance boundary and the same vocabulary state.
- Capture every displayed partial if available.
- Record all final events. A clip that produces two final events has `finalCount: 2`; a timeout has `finalReceived: false`, `finalCount: 0`, and no latency.
- Do not silently retry a failed trial. Missing finals are part of the result.

One provider result entry has this shape:

```json
{
  "id": "human-cv-001",
  "run": 1,
  "transcript": "识别到的最终文本",
  "finalReceived": true,
  "finalCount": 1,
  "finalizationMs": 930,
  "englishCaptionMs": 2480,
  "spokenAudioStartMs": 3310,
  "partials": [
    { "text": "识别到", "atMs": 310 },
    { "text": "识别到的最终", "atMs": 670 }
  ]
}
```

`partials` and the two English timing fields are optional. Partial churn is the proportion of previously displayed characters withdrawn or rewritten between successive hypotheses; pure suffix growth scores zero. `finalizationMs`, `englishCaptionMs`, and `spokenAudioStartMs` are all measured from utterance end, not from clip start.

Evaluate all 108 trials per provider:

```sh
node benchmarks/evaluate-asr.mjs \
  --manifest benchmarks/private/human-manifest.json \
  benchmarks/private/human-apple-results.json \
  benchmarks/private/human-elevenlabs-results.json \
  > benchmarks/private/human-comparison.json
```

The report includes corpus-weighted Simplified-Chinese CER (plus macro mean CER for diagnosis), missing and extra/false finals, p50/p95 finalization, English-caption and spoken-audio-start latency, critical-token failures by kind, and partial-churn mean/p95 when interim hypotheses are supplied. Every received final must include `finalizationMs`; omitted timing cannot make a provider eligible.

The report also evaluates the end-to-end performance targets. It marks them complete only when all trials include final, English-caption, and spoken-audio-start timing: Chinese final p50 under 1.2 seconds, English p50 under 3 seconds and p95 under 5 seconds, and spoken start p50 under 4 seconds.

## Recognizer selection gate

Apple remains the default unless ElevenLabs passes **every** gate across all three runs:

- At least 10% relative mean-CER improvement over Apple.
- Critical-token error rate no worse than Apple.
- Zero errors in the designated safety-critical negation and number set.
- Finalization p95 no more than 2,000 ms.
- Zero missing finals.

False finals and partial churn are reported for investigation even though they are not independent selection gates. Any false final that creates a misleading translation is a release blocker.

## Vocabulary A/B

Use the human names/place subset for a paired test:

1. Run both recognizers with an empty learned vocabulary.
2. Add only the explicitly corrected names and places, then repeat with identical audio and order.
3. Require improved target-term recall and no increase in CER on clips without those terms.
4. Record the vocabulary snapshot identifier with the result; never edit provider transcripts after capture.

## Kimi translation checks

`translation-cases.json` contains 30 meaning-preservation checks. Run them through the current Kimi request configuration and review the screen and spoken forms. At least 27 must preserve meaning, and the complete set must contain zero reversed negations or corrupted critical numbers before spoken output is considered safe.

## Local checks

```sh
node --check benchmarks/evaluate-asr.mjs
node --test benchmarks/evaluate-asr.test.mjs
node -e 'JSON.parse(require("node:fs").readFileSync("benchmarks/manifest.json")); JSON.parse(require("node:fs").readFileSync("benchmarks/human-manifest.template.json"))'
```
