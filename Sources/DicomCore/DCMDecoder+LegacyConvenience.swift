// MARK: - Convenience Extensions

extension DCMDecoder {

    /// Quick check if this is a valid grayscale image
    public var isGrayscale: Bool {
        return samplesPerPixel == 1
    }

    /// Quick check if this is a color/RGB image
    public var isColorImage: Bool {
        return samplesPerPixel == 3
    }

    /// Quick check if this is a multi-frame image
    public var isMultiFrame: Bool {
        return nImages > 1
    }

    /// Returns image dimensions as a tuple
    public var imageDimensions: (width: Int, height: Int) {
        return (width, height)
    }

    /// Returns pixel spacing as a tuple
    @available(*, deprecated, message: "Use pixelSpacingV2 for type-safe PixelSpacing struct")
    public var pixelSpacing: (width: Double, height: Double, depth: Double) {
        return (pixelWidth, pixelHeight, pixelDepth)
    }

    /// Returns window settings as a tuple
    @available(*, deprecated, message: "Use windowSettingsV2 for type-safe WindowSettings struct")
    public var windowSettings: (center: Double, width: Double) {
        return (windowCenter, windowWidth)
    }

    /// Returns rescale parameters as a tuple
    @available(*, deprecated, message: "Use rescaleParametersV2 for type-safe RescaleParameters struct")
    public var rescaleParameters: (intercept: Double, slope: Double) {
        return synchronized { (rescaleIntercept, rescaleSlope) }
    }

}
