import Foundation

internal final class SpecificCharacterSetTagHandler: TagHandler {
    func handle(
        tag: Int,
        reader: DCMBinaryReader,
        location: inout Int,
        parser: DCMTagParser,
        context: DecoderContext,
        addInfo: (Int, String?) -> Void,
        addInfoInt: (Int, Int) -> Void
    ) -> Bool {
        let value = reader.readString(length: parser.currentElementLength, location: &location)
        context.specificCharacterSet = DicomSpecificCharacterSet(value)
        addInfo(tag, value)
        return true
    }
}
