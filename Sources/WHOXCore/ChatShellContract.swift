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

public enum DrawerAccessContract {
    public static func canOpen(_ side: DrawerSide, role: String?) -> Bool {
        side == .leading || role == "owner"
    }
}

public enum DirectoryPathContract {
    public static func displayPath(_ relativePath: String) -> String {
        relativePath.isEmpty ? "/" : "/" + relativePath
    }
}

public enum DrawerPresentationContract {
    public static func width(containerWidth: CGFloat) -> CGFloat {
        min(containerWidth * 0.78, 390)
    }

    public static func mainOffset(side: DrawerSide, progress: CGFloat, width: CGFloat) -> CGFloat {
        let amount = min(max(progress, 0), 1) * width
        return side == .leading ? amount : -amount
    }

    public static func opacity(progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    public static func scrimOpacity(progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1) * 0.09
    }
}

public enum LinkReferenceContract {
    public static let maximumLinks = 20

    public static func validLinks(from input: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawLine in input.components(separatedBy: .newlines) {
            let candidate = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty,
                  let components = URLComponents(string: candidate),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false else { continue }
            let key = candidate.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
            if result.count == maximumLinks { break }
        }
        return result
    }

    public static func messageText(draft: String, links: [String]) -> String {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !links.isEmpty else { return text }
        let context = "Reference links:\n" + links.map { "- \($0)" }.joined(separator: "\n")
        return text.isEmpty ? context : text + "\n\n" + context
    }
}

public enum PreviewFilenameContract {
    public static func safeFilename(_ candidate: String) -> String? {
        guard !candidate.isEmpty,
              candidate != ".", candidate != "..",
              !candidate.contains("/"), !candidate.contains("\\"),
              candidate.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return candidate
    }
}
