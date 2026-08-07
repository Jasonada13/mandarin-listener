#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
IOS_DIR="$REPOSITORY_DIR/ios"
DOWNLOAD_DIR="$IOS_DIR/.local-deps/downloads"
STAGING_DIR="$IOS_DIR/.local-deps/staging"
FRAMEWORK_DIR="$IOS_DIR/ThirdParty"
MODEL_ROOT="$IOS_DIR/MandarinListener/Resources/SpeechModels"
MODEL_NAME="sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30"

RUNTIME_ARCHIVE="$DOWNLOAD_DIR/sherpa-onnx-ios.tar.bz2"
MODEL_ARCHIVE="$DOWNLOAD_DIR/sherpa-onnx-zh-model.tar.bz2"
RUNTIME_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.36/sherpa-onnx-v1.12.36-ios-no-tts.tar.bz2"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$MODEL_NAME.tar.bz2"
RUNTIME_SHA256="b404e390eac94da3b602562850b4af51c17bd6e59c5a3fde8656a78c868f4aaa"
MODEL_SHA256="5a2832047ea1f97dd0dc595b816c230c4bafad65cfc0341fa57517cadc50afd0"

mkdir -p "$DOWNLOAD_DIR" "$STAGING_DIR" "$FRAMEWORK_DIR" "$MODEL_ROOT"

download_and_verify() {
    destination=$1
    source_url=$2
    expected_sha256=$3

    if [ -f "$destination" ]; then
        actual_sha256=$(shasum -a 256 "$destination" | awk '{print $1}')
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            return
        fi
    fi

    curl --fail --location --continue-at - --output "$destination" "$source_url"
    actual_sha256=$(shasum -a 256 "$destination" | awk '{print $1}')
    if [ "$actual_sha256" != "$expected_sha256" ]; then
        echo "Checksum verification failed for $destination" >&2
        exit 1
    fi
}

download_and_verify "$RUNTIME_ARCHIVE" "$RUNTIME_URL" "$RUNTIME_SHA256"
download_and_verify "$MODEL_ARCHIVE" "$MODEL_URL" "$MODEL_SHA256"

runtime_staging="$STAGING_DIR/runtime"
model_staging="$STAGING_DIR/model"
rm -rf "$runtime_staging" "$model_staging"
mkdir -p "$runtime_staging" "$model_staging"
tar -xjf "$RUNTIME_ARCHIVE" -C "$runtime_staging"
tar -xjf "$MODEL_ARCHIVE" -C "$model_staging"

rm -rf \
    "$FRAMEWORK_DIR/sherpa-onnx.xcframework" \
    "$FRAMEWORK_DIR/onnxruntime.xcframework" \
    "$MODEL_ROOT/$MODEL_NAME"

cp -R \
    "$runtime_staging/build-ios-no-tts/sherpa-onnx.xcframework" \
    "$FRAMEWORK_DIR/sherpa-onnx.xcframework"
cp -R \
    "$runtime_staging/build-ios-no-tts/ios-onnxruntime/1.17.1/onnxruntime.xcframework" \
    "$FRAMEWORK_DIR/onnxruntime.xcframework"

mkdir -p "$MODEL_ROOT/$MODEL_NAME"
for model_file in encoder.int8.onnx decoder.onnx joiner.int8.onnx tokens.txt; do
    cp \
        "$model_staging/$MODEL_NAME/$model_file" \
        "$MODEL_ROOT/$MODEL_NAME/$model_file"
done

echo "sherpa-onnx iOS runtime and Mandarin model are ready."
