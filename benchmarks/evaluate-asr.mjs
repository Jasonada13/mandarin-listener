import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const benchmarkDirectory = dirname(fileURLToPath(import.meta.url));

export function normalize(value = "") {
  return Array.from(String(value).normalize("NFKC").toLowerCase()).filter(
    (character) => !/[\s\p{P}\p{S}]/u.test(character)
  );
}

export function editDistance(expected, actual) {
  let previous = Array.from({ length: actual.length + 1 }, (_, index) => index);

  for (let row = 0; row < expected.length; row += 1) {
    const current = [row + 1];
    for (let column = 0; column < actual.length; column += 1) {
      current[column + 1] = Math.min(
        previous[column + 1] + 1,
        current[column] + 1,
        previous[column] + (expected[row] === actual[column] ? 0 : 1)
      );
    }
    previous = current;
  }

  return previous.at(-1);
}

export function cer(referenceText, hypothesisText) {
  const expected = normalize(referenceText);
  const actual = normalize(hypothesisText);
  if (expected.length === 0) {
    return actual.length === 0 ? 0 : 1;
  }
  return editDistance(expected, actual) / expected.length;
}

export function percentile(values, quantile) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.min(sorted.length - 1, Math.ceil(sorted.length * quantile) - 1);
  return sorted[index];
}

function average(values) {
  if (values.length === 0) {
    return null;
  }
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function asText(partial) {
  return typeof partial === "string" ? partial : partial?.text ?? "";
}

export function partialRevisionRatios(partials, finalTranscript) {
  if (!Array.isArray(partials) || partials.length === 0) {
    return [];
  }

  const hypotheses = [...partials.map(asText), finalTranscript]
    .map(normalize)
    .filter((value) => value.length > 0);
  const ratios = [];

  for (let index = 1; index < hypotheses.length; index += 1) {
    const previous = hypotheses[index - 1];
    const current = hypotheses[index];
    let commonPrefixLength = 0;
    while (
      commonPrefixLength < previous.length &&
      commonPrefixLength < current.length &&
      previous[commonPrefixLength] === current[commonPrefixLength]
    ) {
      commonPrefixLength += 1;
    }

    // Pure suffix growth is stable. This ratio measures how much already-shown
    // text was withdrawn or rewritten at each subsequent hypothesis.
    ratios.push((previous.length - commonPrefixLength) / previous.length);
  }

  return ratios;
}

function acceptedForms(span) {
  if (Array.isArray(span.accepted) && span.accepted.length > 0) {
    return span.accepted;
  }
  return span.text ? [span.text] : [];
}

function containsAcceptedForm(transcript, span) {
  const normalizedTranscript = normalize(transcript).join("");
  return acceptedForms(span).some((form) =>
    normalizedTranscript.includes(normalize(form).join(""))
  );
}

function validateManifest(rawManifest, path) {
  const fixtures = Array.isArray(rawManifest) ? rawManifest : rawManifest.clips;
  if (!Array.isArray(fixtures) || fixtures.length === 0) {
    throw new Error(`${path} must be an array or contain a non-empty "clips" array`);
  }

  const identifiers = new Set();
  for (const fixture of fixtures) {
    const referenceText = fixture.referenceText ?? fixture.text;
    if (!fixture.id || typeof referenceText !== "string" || referenceText.trim() === "") {
      throw new Error(`${path} contains an unfinished fixture; every clip needs id and referenceText/text`);
    }
    if (identifiers.has(fixture.id)) {
      throw new Error(`${path} contains duplicate id ${fixture.id}`);
    }
    identifiers.add(fixture.id);
  }

  if (!Array.isArray(rawManifest) && rawManifest.requirements) {
    const requirements = rawManifest.requirements;
    const commonVoice = fixtures.filter(
      (fixture) => fixture.sourceType === "common_voice_cc0"
    );
    const consented = fixtures.filter(
      (fixture) => fixture.sourceType === "consented_private"
    );
    const commonVoiceSpeakers = new Set(
      commonVoice.map((fixture) => fixture.speakerId?.trim()).filter(Boolean)
    );

    if (commonVoice.length !== requirements.commonVoiceClips) {
      throw new Error(
        `${path} contains ${commonVoice.length} Common Voice clips; expected ${requirements.commonVoiceClips}`
      );
    }
    if (consented.length !== requirements.consentedClips) {
      throw new Error(
        `${path} contains ${consented.length} consented clips; expected ${requirements.consentedClips}`
      );
    }
    if (commonVoiceSpeakers.size < requirements.minimumDistinctSpeakers) {
      throw new Error(
        `${path} contains ${commonVoiceSpeakers.size} distinct Common Voice speakers; expected at least ${requirements.minimumDistinctSpeakers}`
      );
    }
    if (
      typeof rawManifest.commonVoiceDatasetVersion !== "string" ||
      rawManifest.commonVoiceDatasetVersion.trim() === ""
    ) {
      throw new Error(`${path} needs commonVoiceDatasetVersion`);
    }
    if (
      fixtures.some(
        (fixture) => typeof fixture.audioFile !== "string" || fixture.audioFile.trim() === ""
      )
    ) {
      throw new Error(`${path} contains a clip without audioFile`);
    }
    if (
      commonVoice.some(
        (fixture) => typeof fixture.sourceId !== "string" || fixture.sourceId.trim() === ""
      )
    ) {
      throw new Error(`${path} contains a Common Voice clip without sourceId`);
    }
    if (consented.some((fixture) => fixture.consentRecorded !== true)) {
      throw new Error(`${path} contains a private recording without recorded consent`);
    }
  }
  const repetitions = Array.isArray(rawManifest)
    ? 1
    : rawManifest.requirements?.repetitionsPerProvider ?? 1;
  if (!Number.isInteger(repetitions) || repetitions < 1) {
    throw new Error(`${path} repetitionsPerProvider must be a positive integer`);
  }
  return { fixtures, repetitions };
}

function validateResults(rawResults, provider, fixtureIds, repetitions) {
  if (!Array.isArray(rawResults)) {
    throw new Error(`${provider} results must be a JSON array`);
  }

  const results = new Map();
  for (const result of rawResults) {
    if (!result?.id || !fixtureIds.has(result.id)) {
      throw new Error(`${provider} results contain unknown or missing id ${result?.id ?? "<missing>"}`);
    }
    const run = result.run ?? (repetitions === 1 ? 1 : null);
    if (!Number.isInteger(run) || run < 1 || run > repetitions) {
      throw new Error(
        `${provider} result ${result.id} needs run between 1 and ${repetitions}`
      );
    }
    const key = `${result.id}:${run}`;
    if (results.has(key)) {
      throw new Error(`${provider} results contain duplicate id/run ${key}`);
    }
    if (
      result.finalizationMs != null &&
      (!Number.isFinite(result.finalizationMs) || result.finalizationMs < 0)
    ) {
      throw new Error(`${provider} result ${result.id} has invalid finalizationMs`);
    }
    const finalReceived =
      result.finalReceived ??
      (typeof result.transcript === "string" && result.transcript.trim().length > 0);
    if (
      finalReceived &&
      (typeof result.transcript !== "string" || result.transcript.trim().length === 0)
    ) {
      throw new Error(
        `${provider} result ${result.id} cannot mark an empty transcript final`
      );
    }
    if (finalReceived && !Number.isFinite(result.finalizationMs)) {
      throw new Error(
        `${provider} result ${result.id} needs finalizationMs when a final was received`
      );
    }
    for (const field of ["englishCaptionMs", "spokenAudioStartMs"]) {
      if (
        result[field] != null &&
        (!Number.isFinite(result[field]) || result[field] < 0)
      ) {
        throw new Error(`${provider} result ${result.id} has invalid ${field}`);
      }
    }
    if (
      Number.isFinite(result.englishCaptionMs) &&
      result.englishCaptionMs < result.finalizationMs
    ) {
      throw new Error(
        `${provider} result ${result.id} shows English before the Chinese final`
      );
    }
    if (
      Number.isFinite(result.spokenAudioStartMs) &&
      (
        !Number.isFinite(result.englishCaptionMs) ||
        result.spokenAudioStartMs < result.englishCaptionMs
      )
    ) {
      throw new Error(
        `${provider} result ${result.id} has invalid spoken-audio timing order`
      );
    }
    results.set(key, result);
  }
  return results;
}

export function scoreProvider(fixtures, rawResults, provider, repetitions = 1) {
  const fixtureIds = new Set(fixtures.map((fixture) => fixture.id));
  const results = validateResults(rawResults, provider, fixtureIds, repetitions);
  const characterErrors = [];
  let totalCharacterEdits = 0;
  let totalReferenceCharacters = 0;
  const finalizationLatencies = [];
  const englishCaptionLatencies = [];
  const spokenAudioStartLatencies = [];
  const churnRatios = [];
  const criticalFailures = [];
  const criticalTotalsByKind = {};
  const criticalErrorsByKind = {};
  let missingFinals = 0;
  let falseFinalizations = 0;
  let partialUtterances = 0;

  for (const fixture of fixtures) {
    for (let run = 1; run <= repetitions; run += 1) {
      const result = results.get(`${fixture.id}:${run}`);
      const transcript = typeof result?.transcript === "string" ? result.transcript : "";
      const finalReceived = result?.finalReceived ?? transcript.trim().length > 0;
      const referenceText = fixture.referenceText ?? fixture.text;
      const criticalSpans = fixture.criticalSpans ?? [];

      const expectedCharacters = normalize(referenceText);
      const actualCharacters = normalize(finalReceived ? transcript : "");
      const characterEditCount = editDistance(
        expectedCharacters,
        actualCharacters
      );
      characterErrors.push(
        expectedCharacters.length === 0
          ? actualCharacters.length === 0 ? 0 : 1
          : characterEditCount / expectedCharacters.length
      );
      totalCharacterEdits += characterEditCount;
      totalReferenceCharacters += expectedCharacters.length;
      if (!finalReceived) {
        missingFinals += 1;
      } else if (Number.isFinite(result?.finalizationMs)) {
        finalizationLatencies.push(result.finalizationMs);
      }
      if (Number.isFinite(result?.englishCaptionMs)) {
        englishCaptionLatencies.push(result.englishCaptionMs);
      }
      if (Number.isFinite(result?.spokenAudioStartMs)) {
        spokenAudioStartLatencies.push(result.spokenAudioStartMs);
      }

      const finalCount = Number.isInteger(result?.finalCount)
        ? result.finalCount
        : finalReceived
          ? 1
          : 0;
      falseFinalizations += Math.max(0, finalCount - 1);

      const utteranceChurn = finalReceived
        ? partialRevisionRatios(result?.partials, transcript)
        : [];
      if (utteranceChurn.length > 0) {
        partialUtterances += 1;
        churnRatios.push(...utteranceChurn);
      }

      for (const span of criticalSpans) {
        const forms = acceptedForms(span);
        if (forms.length === 0) {
          throw new Error(`${fixture.id} has a criticalSpan without text or accepted forms`);
        }
        const kind = span.kind ?? "other";
        criticalTotalsByKind[kind] = (criticalTotalsByKind[kind] ?? 0) + 1;
        if (!finalReceived || !containsAcceptedForm(transcript, span)) {
          criticalErrorsByKind[kind] = (criticalErrorsByKind[kind] ?? 0) + 1;
          criticalFailures.push({
            id: fixture.id,
            run,
            kind,
            accepted: forms,
            safetyCritical: span.safetyCritical === true
          });
        }
      }
    }
  }

  const criticalTokenCount = Object.values(criticalTotalsByKind).reduce(
    (sum, count) => sum + count,
    0
  );
  const criticalTokenErrors = criticalFailures.length;

  const trials = fixtures.length * repetitions;
  const performanceTargets = {
    completeTiming:
      finalizationLatencies.length === trials &&
      englishCaptionLatencies.length === trials &&
      spokenAudioStartLatencies.length === trials,
    chineseFinalP50Under1200:
      finalizationLatencies.length === trials &&
      percentile(finalizationLatencies, 0.5) < 1_200,
    englishCaptionP50Under3000:
      englishCaptionLatencies.length === trials &&
      percentile(englishCaptionLatencies, 0.5) < 3_000,
    englishCaptionP95Under5000:
      englishCaptionLatencies.length === trials &&
      percentile(englishCaptionLatencies, 0.95) < 5_000,
    spokenAudioStartP50Under4000:
      spokenAudioStartLatencies.length === trials &&
      percentile(spokenAudioStartLatencies, 0.5) < 4_000
  };
  performanceTargets.allMet = Object.values(performanceTargets).every(Boolean);

  return {
    clips: fixtures.length,
    repetitions,
    trials,
    meanCER:
      totalReferenceCharacters === 0
        ? average(characterErrors)
        : totalCharacterEdits / totalReferenceCharacters,
    macroMeanCER: average(characterErrors),
    missingFinals,
    falseFinalizations,
    finalizationLatencyMs: {
      samples: finalizationLatencies.length,
      p50: percentile(finalizationLatencies, 0.5),
      p95: percentile(finalizationLatencies, 0.95)
    },
    englishCaptionLatencyMs: {
      samples: englishCaptionLatencies.length,
      p50: percentile(englishCaptionLatencies, 0.5),
      p95: percentile(englishCaptionLatencies, 0.95)
    },
    spokenAudioStartLatencyMs: {
      samples: spokenAudioStartLatencies.length,
      p50: percentile(spokenAudioStartLatencies, 0.5),
      p95: percentile(spokenAudioStartLatencies, 0.95)
    },
    performanceTargets,
    criticalTokens: {
      total: criticalTokenCount,
      errors: criticalTokenErrors,
      errorRate: criticalTokenCount === 0 ? null : criticalTokenErrors / criticalTokenCount,
      totalsByKind: criticalTotalsByKind,
      errorsByKind: criticalErrorsByKind,
      failures: criticalFailures
    },
    partialChurn: churnRatios.length === 0
      ? null
      : {
          utterances: partialUtterances,
          transitions: churnRatios.length,
          meanRevisionRatio: average(churnRatios),
          p95RevisionRatio: percentile(churnRatios, 0.95)
        }
  };
}

export function evaluate(
  manifest,
  appleResults,
  elevenLabsResults,
  { repetitions = 1 } = {}
) {
  const apple = scoreProvider(manifest, appleResults, "apple", repetitions);
  const elevenLabs = scoreProvider(
    manifest,
    elevenLabsResults,
    "elevenlabs",
    repetitions
  );
  const relativeCERImprovement = apple.meanCER === 0
    ? null
    : (apple.meanCER - elevenLabs.meanCER) / apple.meanCER;
  const safetyFailures = elevenLabs.criticalTokens.failures.filter(
    (failure) =>
      failure.safetyCritical &&
      (failure.kind === "negation" || failure.kind === "number")
  );
  const hasCriticalAnnotations = elevenLabs.criticalTokens.total > 0;
  const hasSafetyAnnotations = manifest.some((fixture) =>
    (fixture.criticalSpans ?? []).some(
      (span) =>
        span.safetyCritical === true &&
        (span.kind === "negation" || span.kind === "number")
    )
  );

  const gates = {
    relativeCERImprovementAtLeast10Percent:
      relativeCERImprovement != null && relativeCERImprovement >= 0.1,
    criticalTokenErrorRateNoWorse:
      hasCriticalAnnotations &&
      elevenLabs.criticalTokens.errorRate <= apple.criticalTokens.errorRate,
    zeroSafetyNegationOrNumberErrors: hasSafetyAnnotations && safetyFailures.length === 0,
    p95FinalizationAtMost2000Ms:
      elevenLabs.finalizationLatencyMs.p95 != null &&
      elevenLabs.finalizationLatencyMs.p95 <= 2_000,
    noMissingFinals: elevenLabs.missingFinals === 0
  };
  const elevenLabsEligible = Object.values(gates).every(Boolean);

  return {
    apple,
    elevenLabs,
    comparison: {
      elevenLabsRelativeCERImprovement: relativeCERImprovement,
      gates,
      selectedDefault: elevenLabsEligible ? "elevenlabs" : "apple"
    },
    decisionRule:
      "ElevenLabs requires >=10% relative CER improvement, critical-token error rate no worse than Apple, zero designated safety negation/number errors, <=2000ms p95 finalization, and no missing finals."
  };
}

function parseArguments(arguments_) {
  const positionals = [];
  let manifestPath = join(benchmarkDirectory, "manifest.json");
  for (let index = 0; index < arguments_.length; index += 1) {
    if (arguments_[index] === "--manifest") {
      manifestPath = arguments_[index + 1];
      index += 1;
    } else {
      positionals.push(arguments_[index]);
    }
  }

  if (!manifestPath || positionals.length !== 2) {
    console.error(
      "Usage: node benchmarks/evaluate-asr.mjs [--manifest manifest.json] apple-results.json elevenlabs-results.json"
    );
    process.exit(2);
  }
  return { manifestPath, applePath: positionals[0], elevenLabsPath: positionals[1] };
}

function main() {
  const { manifestPath, applePath, elevenLabsPath } = parseArguments(process.argv.slice(2));
  const rawManifest = JSON.parse(readFileSync(resolve(manifestPath), "utf8"));
  const { fixtures, repetitions } = validateManifest(rawManifest, manifestPath);
  const appleResults = JSON.parse(readFileSync(resolve(applePath), "utf8"));
  const elevenLabsResults = JSON.parse(readFileSync(resolve(elevenLabsPath), "utf8"));
  console.log(
    JSON.stringify(
      evaluate(fixtures, appleResults, elevenLabsResults, { repetitions }),
      null,
      2
    )
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
