# ``DicomCore``

Pure Swift DICOM decoder for iOS and macOS. Read DICOM files, extract medical metadata, and process pixel data without UIKit or Objective-C dependencies.

## Overview

DicomCore is a complete DICOM decoder written in Swift, modernized from a legacy medical viewer. It provides comprehensive support for parsing DICOM files, extracting metadata, processing pixel data, and applying medical image windowing operations.

DICOM (Digital Imaging and Communications in Medicine) is the standard for medical imaging used by CT, MRI, X-ray, ultrasound, and hospital PACS systems. This library is suitable for lightweight DICOM viewers, PACS clients, telemedicine apps, and research tools.

### Key Features

- Complete DICOM file parsing (metadata and pixels)
- Support for 8-bit, 16-bit grayscale and 24-bit RGB images
- Window/level operations with medical presets and GPU acceleration
- Modern async/await APIs for non-blocking operations
- File validation before processing
- Zero external dependencies - uses only Apple frameworks

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:Installation>
- <doc:QuickStart>

### Core Components

- ``DCMDecoder``
- ``DCMWindowingProcessor``
- ``MetalWindowingProcessor``
- ``DicomSeriesLoader``

### Data Models

- ``PatientModel``
- ``StudyModel``
- ``SeriesModel``
- ``ImageModel``
- ``DicomSeriesVolume``

### Value Types

- ``WindowSettings``
- ``PixelSpacing``
- ``RescaleParameters``
- ``DicomTag``

### Services

- ``StudyDataService``
- ``DCMDictionary``

### Error Handling

- ``DICOMError``

### Image Processing

- <doc:WindowingAndLeveling>
- <doc:GPUAcceleration>
- <doc:MedicalPresets>

### Advanced Topics

- <doc:SeriesLoading>
- <doc:GeometryAndOrientation>
- <doc:PerformanceOptimization>

### Reference

- <doc:SupportedFormats>
- <doc:DicomGlossary>
- <doc:Troubleshooting>
