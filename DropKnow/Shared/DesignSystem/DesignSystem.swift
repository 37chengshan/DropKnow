import SwiftUI

public struct DesignSystem {
    public init() {}
}

extension DesignSystem {
    static let colors = DesignColors.self
    static let spacing = DesignSpacing.self
    static let cornerRadius = DesignCornerRadius.self
    static let typography = DesignTypography.self
    static let animation = DesignAnimation.self
}
