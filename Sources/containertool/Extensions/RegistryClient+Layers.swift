//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftContainerPlugin open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftContainerPlugin project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftContainerPlugin project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import ContainerRegistry

extension ImageSource {
    // A single-architecture image may begin with a manifest;  a multi-architecture
    // image begins with an index which points to one or more manifests.   The client
    // could receive either type of object:
    // * if the registry sends a manifest, this function returns it
    // * if the registry sends an index, this function chooses the
    //   appropriate architecture-specific manifest and returns it.
    func getImageManifest(
        forImage image: ImageReference,
        architecture: String
    ) async throws -> (ImageManifest, ContentDescriptor) {
        do {
            // Try to retrieve a manifest.   If the object with this reference is actually an index, the content-type will not match and
            // an error will be thrown.
            return try await getManifest(repository: image.repository, reference: image.reference)
        } catch {
            // Try again, treating the top level object as an index.
            // This could be more efficient if the exception thrown by getManifest() included the data it was unable to parse
            let index = try await getIndex(repository: image.repository, reference: image.reference)
            guard let manifest = index.manifests.first(where: { $0.platform?.architecture == architecture }) else {
                throw "Could not find a suitable base image for \(architecture)"
            }
            // The index should not point to another index;   if it does, this call will throw a final error to be handled by the caller.
            return try await getManifest(
                repository: image.repository,
                reference: ImageReference.Digest(manifest.digest)
            )
        }
    }
}

extension ImageDestination {
    // A layer is a tarball, optionally compressed using gzip or zstd
    // See https://github.com/opencontainers/image-spec/blob/main/media-types.md
    func uploadLayer(
        repository: ImageReference.Repository,
        contents: [UInt8],
        mediaType: String = "application/vnd.oci.image.layer.v1.tar+gzip"
    ) async throws -> (descriptor: ContentDescriptor, diffID: ImageReference.Digest) {
        // The diffID is the hash of the unzipped layer tarball
        let diffID = ImageReference.Digest(of: contents)
        // The layer blob is the gzipped tarball;  the descriptor is the hash of this gzipped blob
        let blob = Data(gzip(contents))
        let descriptor = try await putBlob(repository: repository, mediaType: mediaType, data: blob)
        return (descriptor: descriptor, diffID: diffID)
    }
}
