# Physical-device acceptance checklist

Use a current iPhone on iOS 26 with the current Xcode build. Complete these checks before a real conversation.

## Audio route safety

- [ ] Connect AirPods before starting.
- [ ] Confirm the app reports `iPhone mic` and active `AirPods`.
- [ ] Place a test sound beside the iPhone, then beside the AirPods. The transcript must primarily follow the sound beside the iPhone.
- [ ] Confirm translated speech is audible in AirPods and not the iPhone speaker.
- [ ] Remove the AirPods during spoken output. Speech must stop immediately; captions must continue.
- [ ] Reconnect AirPods. Only new translations should play; stale phrases must not replay.

## Recognition and translation

- [ ] Speak a sentence slowly enough to observe `Live English` updating before the Chinese phrase finalises.
- [ ] Confirm partial English does not accumulate a growing queue when Chinese recognition changes rapidly.
- [ ] Confirm the completed English caption silently replaces any imperfect preview without speaking the phrase twice.
- [ ] In Settings, confirm `Best available` names the highest-quality installed English (UK) voice; download an Enhanced or Premium voice in iOS Settings if only Compact is shown.
- [ ] Test Apple recognition with rapid standard Mandarin.
- [ ] Confirm Apple uses `SpeechTranscriber` when its Simplified-Chinese assets are installed.
- [ ] Exercise the Apple `DictationTranscriber` fallback on a supported device/configuration where `SpeechTranscriber` is unavailable.
- [ ] Test Sherpa with the same speaker position, phrases, frame timing, and learned-vocabulary state.
- [ ] Confirm Sherpa continues Chinese captions in airplane mode.
- [ ] Correct a name, begin the next Sherpa utterance, and confirm the learned hotword is applied without rewriting the caption.
- [ ] Test ElevenLabs with the same speaker, position, phrases, and learned-vocabulary state.
- [ ] Confirm names, numbers, dates, times, and negation in at least ten phrases.
- [ ] Deny or expire an ElevenLabs single-use token. The app must fall back to Apple once without a retry loop.
- [ ] Disconnect the network during ElevenLabs use. The app must fall back to Apple captions once without a retry loop.
- [ ] Exhaust or simulate ElevenLabs quota. The app must fall back to Apple and display a non-sensitive provider error.
- [ ] Disconnect the network during Apple use. Chinese captions should continue; English should show `Translation unavailable`.
- [ ] Disconnect the network during Sherpa use. Chinese captions should continue; English should show `Translation unavailable`.
- [ ] Restore the network and begin a new session successfully.
- [ ] Confirm a Kimi timeout or rate limit does not block recognition or remove the Chinese caption.

## Corrections and learned vocabulary

- [ ] Edit a finalized Chinese caption and save it.
- [ ] Confirm the stale English translation and any unstarted speech for that caption are cancelled.
- [ ] If stale speech is already playing, confirm it stops and the corrected result does not auto-speak a second time.
- [ ] Confirm the corrected Chinese is retranslated and only the latest revision appears.
- [ ] Confirm Replay Last speaks the corrected result.
- [ ] Correct a Chinese name or place and confirm a `Learned term` notice appears.
- [ ] Tap Undo and confirm the new vocabulary entry is removed or its prior frequency is restored.
- [ ] Repeat the correction, start a new recognition connection, and confirm the term is supplied as recognition bias.
- [ ] Confirm learned vocabulary never silently replaces text in a future finalized caption.
- [ ] Confirm more than 100 learned terms evicts the lowest-ranked/oldest eligible term and never grows the store beyond 100.

## Background and interruptions

- [ ] Lock the screen for 15 minutes while the phone remains exposed on a table.
- [ ] Confirm captions and translation resume visibly after unlock.
- [ ] Trigger Siri or accept a short phone call. The app must pause and must not resume recording unexpectedly.
- [ ] Tap Resume and confirm the existing in-memory transcript remains available.
- [ ] Switch from Wi-Fi to cellular during a session.
- [ ] Switch networks during ElevenLabs use and confirm at most one Apple fallback is active.

## Backlog and endurance

- [ ] Play continuous fast Mandarin for two minutes.
- [ ] Confirm all finalized captions remain visible.
- [ ] Confirm stale queued speech is marked caption-only and the spoken delay does not grow without bound.
- [ ] Run a 30-minute session without a crash or steadily increasing memory use in Xcode’s Debug navigator.

## Privacy and export

- [ ] Confirm no audio file appears in the app container.
- [ ] Confirm Sherpa audio remains on the iPhone.
- [ ] Confirm ElevenLabs audio travels directly from the phone rather than through the Cloudflare Worker.
- [ ] Confirm Worker logs contain no token, authorization header, transcript text, or audio.
- [ ] Confirm the learned-vocabulary file uses complete file protection and is excluded from device backup.
- [ ] Stop the session and export the Markdown transcript.
- [ ] Confirm the export contains corrected Chinese and the latest English translation.
- [ ] Dismiss the share sheet and confirm the temporary file is removed from the app’s temporary directory.
- [ ] Discard the transcript and confirm the conversation disappears.
