//
//  FormatoArrayFloat32.swift
//  Role: a FormatoKit array's elements as Float, the way the app's readers hand pixels to the 4D pipeline (H5Reader, DM4Reader),
//        and the same conversion for stored bytes held elsewhere (the resident cube at its stored bit depth, #260).
//

import Foundation
import FormatoCore

extension FormatoArray {
    /// In bounds by construction (mac4DSTEM#300 asked): `FormatoArray.init` refuses bytes that are not exactly `count × byteSize`.
    /// delete at FormatoKit 0.16.0: `FormatoArray.floats()` (colour types become a refusal at the call sites).
    /// Every element as Float, in C order, each converted the way a C cast does (round to nearest even; what `H5Dread` into
    /// `H5T_NATIVE_FLOAT` did): float32 is copied as stored. Nil for a colour type, which no 4D source holds.
    package nonisolated func float32Values() -> [Float]? {
        let n = count
        guard dataType.convertsToFloat32 else { return nil }
        return bytes.withUnsafeBytes { p -> [Float] in
            [Float](unsafeUninitializedCapacity: n) { out, initialized in
                if let base = out.baseAddress { _ = dataType.convertToFloat32(p, count: n, into: base) }
                initialized = n
            }
        }
    }
}

extension FormatoDataType {
    /// Whether ``convertToFloat32(_:count:into:)`` converts this type (every numeric type; not the colour types).
    package nonisolated var convertsToFloat32: Bool {
        switch self {
        case .rgb8, .rgba8, .rgb16, .rgba16: false
        default: true
        }
    }

    /// The types a resident cube holds as stored (#260): every numeric type of at most four bytes. The 8-byte types are held as
    /// Float32, half their size.
    package nonisolated var isHeldAsStored: Bool { convertsToFloat32 && byteSize <= MemoryLayout<Float>.stride }

    /// Converts `count` little-endian elements at the start of `p` (any alignment) to Float into `out`, each the way a C cast
    /// does. The one conversion of `FormatoArray.float32Values()` and of every read out of a stored-type resident cube, so the
    /// two are bit-identical. Returns false (and writes nothing) for a colour type.
    @discardableResult
    package nonisolated func convertToFloat32(
        _ p: UnsafeRawBufferPointer, count n: Int, into out: UnsafeMutablePointer<Float>
    ) -> Bool {
        switch self {
        case .float32:
            for i in 0..<n { out[i] = Float(bitPattern: UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
        case .float64:
            for i in 0..<n { out[i] = Float(Double(bitPattern: UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self)))) }
        case .uint8:
            for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: UInt8.self)) }
        case .int8:
            for i in 0..<n { out[i] = Float(p.loadUnaligned(fromByteOffset: i, as: Int8.self)) }
        case .uint16:
            for i in 0..<n { out[i] = Float(UInt16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: UInt16.self))) }
        case .int16:
            for i in 0..<n { out[i] = Float(Int16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: Int16.self))) }
        case .uint32:
            for i in 0..<n { out[i] = Float(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) }
        case .int32:
            for i in 0..<n { out[i] = Float(Int32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: Int32.self))) }
        case .uint64:
            for i in 0..<n { out[i] = Float(UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self))) }
        case .int64:
            for i in 0..<n { out[i] = Float(Int64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: Int64.self))) }
        case .rgb8, .rgba8, .rgb16, .rgba16:
            return false
        }
        return true
    }
}
