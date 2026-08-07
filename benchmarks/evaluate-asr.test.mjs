import assert from "node:assert/strict";
import test from "node:test";

import {
  evaluate,
  partialRevisionRatios,
  scoreProvider
} from "./evaluate-asr.mjs";

const fixtures = [
  {
    id: "a",
    text: "我不是说三十。",
    criticalSpans: [
      {
        kind: "negation",
        accepted: ["不是"],
        safetyCritical: true
      },
      {
        kind: "number",
        accepted: ["三十", "30"],
        safetyCritical: true
      }
    ]
  },
  {
    id: "b",
    text: "王经理明天到。",
    criticalSpans: [
      {
        kind: "name",
        accepted: ["王经理"]
      }
    ]
  }
];

test("purely appended partial text has no churn", () => {
  assert.deepEqual(
    partialRevisionRatios(["麻烦", "麻烦你"], "麻烦你坐下"),
    [0, 0]
  );
});

test("rewritten partial text reports the withdrawn proportion", () => {
  assert.deepEqual(partialRevisionRatios(["今天"], "今夭"), [0.5]);
});

test("missing results count as missing finals and critical failures", () => {
  const score = scoreProvider(fixtures, [], "test");
  assert.equal(score.missingFinals, 2);
  assert.equal(score.criticalTokens.errors, 3);
  assert.equal(score.finalizationLatencyMs.p95, null);
});

test("extra final events are reported", () => {
  const score = scoreProvider(
    fixtures,
    fixtures.map((fixture) => ({
      id: fixture.id,
      transcript: fixture.text,
      finalCount: fixture.id === "a" ? 2 : 1,
      finalizationMs: 1_000
    })),
    "test"
  );
  assert.equal(score.falseFinalizations, 1);
});

test("a received final must include utterance-end latency", () => {
  assert.throws(
    () => scoreProvider(
      fixtures,
      fixtures.map((fixture) => ({
        id: fixture.id,
        transcript: fixture.text
      })),
      "test"
    ),
    /needs finalizationMs/
  );
});

test("timing cannot put English or speech before their prerequisites", () => {
  assert.throws(
    () => scoreProvider(
      fixtures,
      fixtures.map((fixture) => ({
        id: fixture.id,
        transcript: fixture.text,
        finalizationMs: 900,
        englishCaptionMs: 800,
        spokenAudioStartMs: 1_000
      })),
      "test"
    ),
    /English before/
  );
});

test("caption and spoken-audio timing are reported from utterance end", () => {
  const score = scoreProvider(
    fixtures,
    fixtures.map((fixture, index) => ({
      id: fixture.id,
      transcript: fixture.text,
      finalizationMs: 800 + index * 100,
      englishCaptionMs: 2_100 + index * 500,
      spokenAudioStartMs: 3_200 + index * 600
    })),
    "test"
  );
  assert.deepEqual(score.englishCaptionLatencyMs, {
    samples: 2,
    p50: 2_100,
    p95: 2_600
  });
  assert.deepEqual(score.spokenAudioStartLatencyMs, {
    samples: 2,
    p50: 3_200,
    p95: 3_800
  });
  assert.equal(score.performanceTargets.completeTiming, true);
  assert.equal(score.performanceTargets.allMet, true);
});

test("ElevenLabs wins only when every selection gate passes", () => {
  const apple = [
    {
      id: "a",
      transcript: "我说三十。",
      finalizationMs: 900,
      partials: ["我说", "我说三十"]
    },
    {
      id: "b",
      transcript: "王明天到。",
      finalizationMs: 1_100
    }
  ];
  const elevenLabs = [
    {
      id: "a",
      transcript: "我不是说三十。",
      finalizationMs: 1_400,
      partials: ["我不是", "我不是说三十"]
    },
    {
      id: "b",
      transcript: "王经理明天到。",
      finalizationMs: 1_900
    }
  ];

  const report = evaluate(fixtures, apple, elevenLabs);
  assert.equal(report.comparison.selectedDefault, "elevenlabs");
  assert.ok(Object.values(report.comparison.gates).every(Boolean));
  assert.equal(report.elevenLabs.partialChurn.meanRevisionRatio, 0);
});

test("a missing ElevenLabs final keeps Apple as default", () => {
  const perfect = fixtures.map((fixture) => ({
    id: fixture.id,
    transcript: fixture.text,
    finalizationMs: 1_000
  }));
  const missing = [perfect[0]];
  const report = evaluate(fixtures, perfect, missing);

  assert.equal(report.comparison.gates.noMissingFinals, false);
  assert.equal(report.comparison.selectedDefault, "apple");
});

test("a designated number error keeps Apple as default despite better CER", () => {
  const apple = [];
  const elevenLabs = [
    {
      id: "a",
      transcript: "我不是说。",
      finalizationMs: 1_000
    },
    {
      id: "b",
      transcript: fixtures[1].text,
      finalizationMs: 1_000
    }
  ];
  const report = evaluate(fixtures, apple, elevenLabs);

  assert.equal(report.comparison.gates.relativeCERImprovementAtLeast10Percent, true);
  assert.equal(report.comparison.gates.criticalTokenErrorRateNoWorse, true);
  assert.equal(report.comparison.gates.zeroSafetyNegationOrNumberErrors, false);
  assert.equal(report.comparison.selectedDefault, "apple");
});
