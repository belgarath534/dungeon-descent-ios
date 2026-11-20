import Foundation
#if canImport(OnnxRuntimeC)
import OnnxRuntimeC

/// Kokoro's model run by ONNX Runtime, through its C API: open the model once,
/// then run it with Lewis's phonemes and style to get 24 kHz speech.
/// Used only on the voice thread.
final class OrtRunner {
    struct Failure: Error, CustomStringConvertible { let description: String }

    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?
    private var session: OpaquePointer?
    private var memory: OpaquePointer?

    init(modelPath: String, threads: Int32) throws {
        guard let base = OrtGetApiBase(), let a = base.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            throw Failure(description: "ONNX Runtime didn't start")
        }
        api = a
        try check(api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "lewis", &env))
        var options: OpaquePointer?
        try check(api.pointee.CreateSessionOptions(&options))
        defer { api.pointee.ReleaseSessionOptions(options) }
        try check(api.pointee.SetIntraOpNumThreads(options, threads))
        try check(api.pointee.SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL))
        try check(api.pointee.CreateSession(env, modelPath, options, &session))
        try check(api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory))
    }

    deinit {
        if let memory { api.pointee.ReleaseMemoryInfo(memory) }
        if let session { api.pointee.ReleaseSession(session) }
        if let env { api.pointee.ReleaseEnv(env) }
    }

    /// Speech for these phoneme numbers (already wrapped in 0s), one row of
    /// Lewis's style (256 numbers) and a speed (1 is normal).
    func speak(ids: [Int64], style: [Float], speed: Float) throws -> [Float] {
        var buffers: [UnsafeMutableRawPointer] = []
        var inputs: [OpaquePointer?] = []
        defer {
            for v in inputs { api.pointee.ReleaseValue(v) }
            for b in buffers { b.deallocate() }
        }
        inputs.append(try tensor(ids, [1, Int64(ids.count)], ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &buffers))
        inputs.append(try tensor(style, [1, Int64(style.count)], ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &buffers))
        inputs.append(try tensor([speed], [1], ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &buffers))

        let labels: [String] = ["tokens", "style", "speed", "audio"]
        let names: [UnsafeMutablePointer<CChar>?] = labels.map { strdup($0) }
        defer { names.forEach { free($0) } }
        let inNamePtrs: [UnsafePointer<CChar>?] = names[0..<3].map { $0.map { UnsafePointer($0) } }
        let outNamePtrs: [UnsafePointer<CChar>?] = [names[3].map { UnsafePointer($0) }]
        let inputValues: [OpaquePointer?] = inputs
        var outputs: [OpaquePointer?] = [nil]
        try check(api.pointee.Run(session, nil, inNamePtrs, inputValues, 3, outNamePtrs, 1, &outputs))
        guard let audio = outputs[0] else { throw Failure(description: "the model gave no audio back") }
        defer { api.pointee.ReleaseValue(audio) }

        var info: OpaquePointer?
        try check(api.pointee.GetTensorTypeAndShape(audio, &info))
        var count = 0
        let counted = api.pointee.GetTensorShapeElementCount(info, &count)
        api.pointee.ReleaseTensorTypeAndShapeInfo(info)
        try check(counted)
        var data: UnsafeMutableRawPointer?
        try check(api.pointee.GetTensorMutableData(audio, &data))
        guard let data, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
    }

    /// A tensor over a copy of the numbers (kept in `buffers` until the run ends).
    private func tensor<T>(_ values: [T], _ shape: [Int64], _ type: ONNXTensorElementDataType,
                           _ buffers: inout [UnsafeMutableRawPointer]) throws -> OpaquePointer? {
        let bytes = values.count * MemoryLayout<T>.stride
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: max(bytes, 16), alignment: 16)
        buffers.append(buffer)
        values.withUnsafeBytes { if let b = $0.baseAddress { buffer.copyMemory(from: b, byteCount: bytes) } }
        var value: OpaquePointer?
        try check(api.pointee.CreateTensorWithDataAsOrtValue(memory, buffer, bytes, shape, shape.count, type, &value))
        return value
    }

    /// Throws ONNX Runtime's own message when a call failed.
    private func check(_ status: OpaquePointer?) throws {
        guard let status else { return }
        let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "unknown error"
        api.pointee.ReleaseStatus(status)
        throw Failure(description: message)
    }
}
#endif
