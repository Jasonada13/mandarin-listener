# Three-conversation acceptance log

The MVP product gate is at least 80% gist comprehension and a usefulness score of 4/5 or better across three real conversations.

Do not record another person without their knowledge. This log needs only ratings and error notes, not private audio or full transcript text.

| Session | Setting and accent | Duration | Recognizer | Gist understood | Repetitions requested | Corrections made | Usefulness (1–5) | Critical errors |
|---|---|---:|---|---:|---:|---:|---:|---|
| 1 |  |  | Apple / ElevenLabs |  |  |  |  |  |
| 2 |  |  | Apple / ElevenLabs |  |  |  |  |  |
| 3 |  |  | Apple / ElevenLabs |  |  |  |  |  |

## Go/no-go

- [ ] Average gist comprehension is at least 80%.
- [ ] Average usefulness is at least 4/5.
- [ ] No negation was reversed.
- [ ] No critical name, number, date, or time error caused a misunderstanding.
- [ ] Spoken latency remained useful rather than distracting.
- [ ] Correcting a caption cancelled stale translation/speech and produced only the latest English revision.
- [ ] Learned vocabulary improved a recurring name/place without changing unrelated captions.
- [ ] Benchmark timing was complete and met Chinese-final p50 <1.2s, English-caption p50 <3s/p95 <5s, and spoken-start p50 <4s.
- [ ] The 36-human-clip benchmark was run three times per provider with identical 100 ms realtime framing.
- [ ] If ElevenLabs is preferred, it achieved at least 10% relative CER improvement over Apple.
- [ ] If ElevenLabs is preferred, its critical-token error rate was no worse than Apple, it had zero designated number/negation errors, zero missing finals, and p95 finalization no more than two seconds.
- [ ] If any recognizer produced a misleading false final, the issue was resolved before spoken output was enabled.

If any safety item fails, keep the app caption-first and muted until the prompt, recognizer choice, or audio routing is corrected.
