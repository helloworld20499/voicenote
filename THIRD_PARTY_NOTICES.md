# Third-party components

- sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx — Apache-2.0; revision 040afe360a38e25daaa325ce8889abf93ea02609.
- ONNX Runtime: https://github.com/microsoft/onnxruntime — MIT; distributed by sherpa-onnx's pinned Swift package dependency.
- SenseVoiceSmall: https://github.com/QwenAudio/SenseVoice — model conversion from https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17, revision 2365baeacb507f821a0c8120fcee3d484dba7a07. Verify upstream model terms before commercial distribution.

The dependency manager retains upstream source licenses. This prototype uses no Argmax Pro SDK or paid transcription API.

- GoogleSignIn-iOS: https://github.com/google/GoogleSignIn-iOS — Apache-2.0; pinned version 9.2.0. Its Xcode SwiftPM dependency graph (including AppAuth and GTMAppAuth) is locked in the Xcode workspace Package.resolved; retain upstream licenses when distributing.
