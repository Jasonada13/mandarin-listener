.PHONY: bootstrap check relay-check core-test benchmark-test generate-project benchmark-audio sherpa-assets open-project

bootstrap:
	./scripts/bootstrap-macos.sh

check: relay-check core-test benchmark-test

relay-check:
	cd relay && npm run check && npm test

core-test:
	cd ios/MandarinListenerCore && swift test

benchmark-test:
	node --test benchmarks/evaluate-asr.test.mjs

generate-project:
	cd ios && xcodegen generate

benchmark-audio:
	node benchmarks/generate-audio.mjs

sherpa-assets:
	./scripts/fetch-sherpa-onnx-ios.sh

open-project: generate-project
	open ios/MandarinListener.xcodeproj
