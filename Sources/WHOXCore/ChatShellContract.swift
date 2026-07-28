import Foundation

public enum ChatBubbleContract {
    public static func maximumWidth(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.8, 480)
    }

    public static func fillsAvailableWidth(role: MessageRole) -> Bool {
        role != .user
    }
}

public enum DrawerSide: Sendable, Equatable {
    case leading
    case trailing
}

public enum DrawerGestureContract {
    public static let edgeActivationWidth: CGFloat = 28

    public static func openingSide(startX: CGFloat, containerWidth: CGFloat) -> DrawerSide? {
        if startX <= edgeActivationWidth { return .leading }
        if startX >= containerWidth - edgeActivationWidth { return .trailing }
        return nil
    }

    public static func shouldCommit(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        width: CGFloat
    ) -> Bool {
        max(abs(translation), abs(predictedTranslation)) >= width * 0.35
    }
}

public enum DirectoryPathContract {
    public static func displayPath(_ relativePath: String) -> String {
        relativePath.isEmpty ? "/" : "/" + relativePath
    }
}
