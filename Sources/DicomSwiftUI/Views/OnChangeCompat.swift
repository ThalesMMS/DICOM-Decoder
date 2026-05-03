//
//  OnChangeCompat.swift
//
//  SwiftUI onChange backport for iOS 13/macOS 10.15 using onReceive.
//

import SwiftUI

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        fallback publisher: Published<Value>.Publisher,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 14.0, macOS 11.0, *) {
            self.onChange(of: value, perform: action)
        } else {
            self.onReceive(publisher.removeDuplicates(), perform: action)
        }
    }
}
