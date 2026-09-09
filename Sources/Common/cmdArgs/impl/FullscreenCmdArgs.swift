public struct FullscreenCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .fullscreen,
        help: fullscreen_help_generated,
        flags: [
            "--no-outer-gaps": trueBoolFlag(\.noOuterGaps),
            "--centered": trueBoolFlag(\.centered),
            "--width": centeredFullscreenPercentFlag(\.widthPercent, "--width"),
            "--height": centeredFullscreenPercentFlag(\.heightPercent, "--height"),
            "--animation": centeredFullscreenAnimationFlag(),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [ArgParser(\.toggle, parseToggleEnum)],
    )

    public var toggle: ToggleEnum = .toggle
    public var noOuterGaps: Bool = false
    public var centered: Bool = false
    public var widthPercent: Double?
    public var heightPercent: Double?
    public var animation: Bool?
    public var failIfNoop: Bool = false

    public var effectiveWidthPercent: Double { widthPercent ?? 50 }
    public var effectiveHeightPercent: Double { heightPercent ?? 50 }
}

func parseFullscreenCmdArgs(_ args: StrArrSlice) -> ParsedCmd<FullscreenCmdArgs> {
    parseSpecificCmdArgs(FullscreenCmdArgs(rawArgs: args), args)
        .filterNot("--no-outer-gaps is incompatible with 'off' argument") { $0.toggle == .off && $0.noOuterGaps }
        .filterNot("--centered is incompatible with 'off' argument") { $0.toggle == .off && $0.centered }
        .filter("--width requires --centered") { $0.centered || $0.widthPercent == nil }
        .filter("--height requires --centered") { $0.centered || $0.heightPercent == nil }
        .filter("--animation requires --centered") { $0.centered || $0.animation == nil }
        .filter("--fail-if-noop requires 'on' or 'off' argument") { $0.failIfNoop.implies($0.toggle == .on || $0.toggle == .off) }
}

private func centeredFullscreenPercentFlag(
    _ keyPath: SendableWritableKeyPath<FullscreenCmdArgs, Double?>,
    _ flag: String,
) -> SubArgParser<FullscreenCmdArgs, Double?> {
    singleValueSubArgParser(keyPath, "<percent>") { rawValue in
        guard rawValue.hasSuffix("%") else {
            return .failure("\(flag) must be a percentage ending in '%'")
        }
        let number = String(rawValue.dropLast())
        guard let percent = Double(number), percent.isFinite, percent > 0, percent <= 100 else {
            return .failure("\(flag) must be greater than 0% and no greater than 100%")
        }
        return .success(percent)
    }
}

private func centeredFullscreenAnimationFlag() -> SubArgParser<FullscreenCmdArgs, Bool?> {
    singleValueSubArgParser(\.animation, "(on|off)") { rawValue in
        switch rawValue {
            case "on": .success(true)
            case "off": .success(false)
            default: .failure("--animation accepts only 'on' or 'off'")
        }
    }
}
