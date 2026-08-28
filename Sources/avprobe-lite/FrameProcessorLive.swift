//
// FrameProcessorLive.swift
// avprobe-lite
//
// Unit 04 — the REAL VTFrameProcessor pipeline. ProcessPath decides capability; when a
// capability is genuinely available AND serviceable, this runs the actual transform on
// decoded frames and reports measured before/after — never a fabricated result.
//
// Reconciled against the real macOS SDK (verified on macOS 26, Apple silicon):
//   * Frames are decoded to IOSurface-backed CVPixelBuffers via AVAssetReader, because
//     VTFrameProcessorFrame requires an IOSurface-backed pixel buffer.
//   * The frame-rate converter is fully live here (macOS 15.4+): two consecutive source
//     frames -> one interpolated destination frame.
//   * Super-resolution (macOS 26.0+) requires an ML model download + a specific scale
//     factor; denoise (macOS 26.0+) requires a high-bit-depth 4:2:2/4:4:4 source. When a
//     given source cannot service those, we report an honest `supported:false` with a
//     concrete reason (exit 0) rather than fabricating a transform.
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

enum FrameProcessorLive {

    /// 4:2:0 full-range bi-planar — the typical decoded output of an 8-bit H.264 source.
    static let sourcePixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

    // MARK: Decode

    /// Decode up to `count` consecutive pixel buffers off the first video track,
    /// requesting IOSurface-backed buffers. Throws a contract error if decoding fails,
    /// so we never emit a success envelope for an unreadable source.
    static func decodePixelBuffers(_ asset: AVAsset, count: Int) async throws -> [CVPixelBuffer] {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.usage("no video track found; `process` requires a video stream")
        }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AppError.contract("could not create AVAssetReader: \(String(describing: error))")
        }
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: sourcePixelFormat
        ])
        output.alwaysCopiesSampleData = false
        if reader.canAdd(output) { reader.add(output) }
        if !reader.startReading() {
            throw AppError.contract("AVAssetReader failed to start (status \(reader.status.rawValue))")
        }

        var buffers: [CVPixelBuffer] = []
        while buffers.count < count {
            guard let sample = output.copyNextSampleBuffer() else { break }
            if let pb = CMSampleBufferGetImageBuffer(sample) {
                buffers.append(pb)
            }
        }
        guard !buffers.isEmpty else {
            throw AppError.contract("could not decode any pixel buffers from the video track")
        }
        return buffers
    }

    /// Create an IOSurface-backed destination pixel buffer of the given dimensions.
    static func makeDestination(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, sourcePixelFormat, attrs, &pb)
        guard status == kCVReturnSuccess else { return nil }
        return pb
    }

    // MARK: Frame-rate conversion (macOS 15.4+)

    /// Live frame-rate conversion: interpolate one frame between two consecutive source
    /// frames via `VTFrameRateConversionConfiguration` and report measured before/after.
    @available(macOS 15.4, *)
    static func frameRateConversion(_ asset: AVAsset) async throws -> EffectCapability {
        let buffers = try await decodePixelBuffers(asset, count: 2)
        guard buffers.count >= 2 else {
            return EffectCapability(
                effect: "frc", supported: false, os: "macOS 15.4",
                soc: nil, applied: "none",
                reason: "not enough video frames for interpolation (need 2)",
                before: nil, after: nil)
        }

        let w = CVPixelBufferGetWidth(buffers[0])
        let h = CVPixelBufferGetHeight(buffers[0])
        guard w > 0, h > 0, let cfg = VTFrameRateConversionConfiguration(
            frameWidth: w, frameHeight: h,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: .revision1) else {
            return EffectCapability(
                effect: "frc", supported: false, os: "macOS 15.4",
                soc: nil, applied: "none",
                reason: "frame-rate conversion did not accept source dimensions \(w)x\(h)",
                before: nil, after: nil)
        }
        guard let dest = makeDestination(width: w, height: h) else {
            throw AppError.contract("could not allocate destination pixel buffer for frame-rate conversion")
        }

        let t0 = CMTime(value: 0, timescale: 3600)
        let t1 = CMTime(value: 3600, timescale: 3600)
        guard let srcFrame = VTFrameProcessorFrame(buffer: buffers[0], presentationTimeStamp: t0),
              let nextFrame = VTFrameProcessorFrame(buffer: buffers[1], presentationTimeStamp: t1),
              let destFrame = VTFrameProcessorFrame(buffer: dest, presentationTimeStamp: CMTime(value: 1800, timescale: 3600)),
              let params = VTFrameRateConversionParameters(
                sourceFrame: srcFrame, nextFrame: nextFrame,
                opticalFlow: nil,
                interpolationPhase: [0.5],
                submissionMode: .sequential,
                destinationFrames: [destFrame])
        else {
            throw AppError.contract("failed to construct frame-rate conversion parameters")
        }

        let before = EffectStep(
            frameCount: 2, width: w, height: h, averageFrameTimeS: nil)

        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: cfg)
        } catch {
            return EffectCapability(
                effect: "frc", supported: false, os: "macOS 15.4",
                soc: nil, applied: "none",
                reason: "VTFrameProcessor failed to start session: \(error.localizedDescription)",
                before: nil, after: nil)
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await processor.process(parameters: params)
        } catch {
            processor.endSession()
            throw AppError.contract("frame-rate conversion failed: \(error.localizedDescription)")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        processor.endSession()

        let after = EffectStep(
            frameCount: 1, width: w, height: h,
            averageFrameTimeS: elapsed)

        return EffectCapability(
            effect: "frc", supported: true, os: "macOS 15.4",
            soc: nil, applied: ProcessPath.Effect.frc.appliedPipeline,
            reason: nil, before: before, after: after)
    }

    // MARK: Super-resolution (macOS 26.0+)

    @available(macOS 26.0, *)
    static func superResolution(_ asset: AVAsset) async throws -> EffectCapability {
        let supportedScaleFactors = VTSuperResolutionScalerConfiguration.supportedScaleFactors
        guard let supportedScaleFactor = supportedScaleFactors.first, supportedScaleFactor > 0 else {
            return EffectCapability(
                effect: "superres", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "no supported super-resolution scale factor on this device",
                before: nil, after: nil)
        }

        let buffers = try await decodePixelBuffers(asset, count: 1)
        let w = CVPixelBufferGetWidth(buffers[0])
        let h = CVPixelBufferGetHeight(buffers[0])
        guard w > 0, h > 0, let cfg = VTSuperResolutionScalerConfiguration(
            frameWidth: w, frameHeight: h,
            scaleFactor: supportedScaleFactor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: .revision1) else {
            return EffectCapability(
                effect: "superres", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "super-resolution did not accept source dimensions \(w)x\(h) at scale factor \(supportedScaleFactor)",
                before: nil, after: nil)
        }

        if cfg.configurationModelStatus != .ready {
            return EffectCapability(
                effect: "superres", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "super-resolution model not ready (status \(cfg.configurationModelStatus.rawValue)); requires download",
                before: nil, after: nil)
        }

        let dw = w * supportedScaleFactor
        let dh = h * supportedScaleFactor
        guard let dest = makeDestination(width: dw, height: dh) else {
            throw AppError.contract("could not allocate destination pixel buffer for super-resolution")
        }

        let t0 = CMTime(value: 0, timescale: 3600)
        guard let srcFrame = VTFrameProcessorFrame(buffer: buffers[0], presentationTimeStamp: t0),
              let destFrame = VTFrameProcessorFrame(buffer: dest, presentationTimeStamp: t0),
              let params = VTSuperResolutionScalerParameters(
                sourceFrame: srcFrame, previousFrame: nil, previousOutputFrame: nil,
                opticalFlow: nil,
                submissionMode: .random,
                destinationFrame: destFrame)
        else {
            throw AppError.contract("failed to construct super-resolution parameters")
        }

        let before = EffectStep(frameCount: 1, width: w, height: h, averageFrameTimeS: nil)
        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: cfg)
        } catch {
            return EffectCapability(
                effect: "superres", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "VTFrameProcessor failed to start session: \(error.localizedDescription)",
                before: nil, after: nil)
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await processor.process(parameters: params)
        } catch {
            processor.endSession()
            throw AppError.contract("super-resolution failed: \(error.localizedDescription)")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        processor.endSession()

        let after = EffectStep(
            frameCount: 1, width: dw, height: dh,
            averageFrameTimeS: elapsed)

        return EffectCapability(
            effect: "superres", supported: true, os: "macOS 26.0",
            soc: nil, applied: ProcessPath.Effect.superres.appliedPipeline,
            reason: nil, before: before, after: after)
    }

    // MARK: Temporal noise filter / denoise (macOS 26.0+)

    @available(macOS 26.0, *)
    static func temporalNoiseFilter(_ asset: AVAsset) async throws -> EffectCapability {
        // Pre-check the source pixel format against the supported set BEFORE constructing
        // the config, so we never let the SDK log to stderr and we control the reason.
        let supported: [OSType] = VTTemporalNoiseFilterConfiguration.supportedSourcePixelFormats
        guard supported.contains(sourcePixelFormat) else {
            return EffectCapability(
                effect: "denoise", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "temporal noise filter does not accept source pixel format \(FourCC(sourcePixelFormat)) (requires a high-bit-depth 4:2:2/4:4:4 source)",
                before: nil, after: nil)
        }
        let buffers = try await decodePixelBuffers(asset, count: 1)
        let w = CVPixelBufferGetWidth(buffers[0])
        let h = CVPixelBufferGetHeight(buffers[0])
        guard w > 0, h > 0, let cfg = VTTemporalNoiseFilterConfiguration(
            frameWidth: w, frameHeight: h, sourcePixelFormat: sourcePixelFormat) else {
            return EffectCapability(
                effect: "denoise", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "temporal noise filter did not accept source dimensions \(w)x\(h)",
                before: nil, after: nil)
        }
        // Constructing the config succeeded; run the real transform.
        guard let dest = makeDestination(width: w, height: h) else {
            throw AppError.contract("could not allocate destination pixel buffer for denoise")
        }
        let t0 = CMTime(value: 0, timescale: 3600)
        guard let srcFrame = VTFrameProcessorFrame(buffer: buffers[0], presentationTimeStamp: t0),
              let destFrame = VTFrameProcessorFrame(buffer: dest, presentationTimeStamp: t0),
              let params = VTTemporalNoiseFilterParameters(
                sourceFrame: srcFrame, nextFrames: [], previousFrames: [],
                destinationFrame: destFrame,
                filterStrength: 0.5, hasDiscontinuity: true)
        else {
            throw AppError.contract("failed to construct noise-filter parameters")
        }

        let before = EffectStep(frameCount: 1, width: w, height: h, averageFrameTimeS: nil)
        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: cfg)
        } catch {
            return EffectCapability(
                effect: "denoise", supported: false, os: "macOS 26.0",
                soc: nil, applied: "none",
                reason: "VTFrameProcessor failed to start session: \(error.localizedDescription)",
                before: nil, after: nil)
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await processor.process(parameters: params)
        } catch {
            processor.endSession()
            throw AppError.contract("denoise failed: \(error.localizedDescription)")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        processor.endSession()

        let after = EffectStep(
            frameCount: 1, width: w, height: h,
            averageFrameTimeS: elapsed)

        return EffectCapability(
            effect: "denoise", supported: true, os: "macOS 26.0",
            soc: nil, applied: ProcessPath.Effect.denoise.appliedPipeline,
            reason: nil, before: before, after: after)
    }
}

/// Little-endian FourCC decode for honest error messages.
private func FourCC(_ value: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
    return String(decoding: bytes, as: UTF8.self)
}
