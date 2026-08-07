import { mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"));
const outputDirectory = join(root, "audio");
mkdirSync(outputDirectory, { recursive: true });

for (const fixture of manifest) {
  const intermediate = join(outputDirectory, `${fixture.id}.aiff`);
  const output = join(outputDirectory, `${fixture.id}.wav`);

  const speech = spawnSync(
    "say",
    ["-v", fixture.voice, "-r", String(fixture.rate), "-o", intermediate, fixture.text],
    { stdio: "inherit" }
  );
  if (speech.status !== 0) {
    throw new Error(`Could not synthesize ${fixture.id}`);
  }

  const conversion = spawnSync(
    "afconvert",
    ["-f", "WAVE", "-d", "LEI16@16000", intermediate, output],
    { stdio: "inherit" }
  );
  rmSync(intermediate, { force: true });
  if (conversion.status !== 0) {
    throw new Error(`Could not convert ${fixture.id}`);
  }
}

console.log(`Generated ${manifest.length} deterministic 16 kHz PCM fixtures in ${outputDirectory}`);
