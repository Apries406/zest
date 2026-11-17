import Foundation

/// 终端列表的快照。附带命令行和光标索引，Shell 可丢弃已经过期的异步结果。
public enum TerminalMenu {
    public static func format(_ state: CompletionController.State) -> String {
        let count = state.visible ? min(5, state.items.count) : 0
        let start = max(0, min(state.selected - 2, state.items.count - count))
        let rows = state.items.dropFirst(start).prefix(count).map { item in
            let description = item.description.map { "  " + displayText($0) } ?? ""
            return displayText(item.name) + description
        }
        let fields = ["menu", state.session, String(state.line?.cursor ?? 0),
                      String(count == 0 ? 0 : state.selected - start), String(count)]
            + rows + [ShellProtocol.encodeNewlines(state.line?.buffer ?? "")]
        return fields.joined(separator: String(ShellProtocol.fieldSeparator)) + "\n"
    }

    /// 文件名及规格描述不能向终端注入控制序列或伪造协议字段。
    private static func displayText(_ text: String) -> String {
        String(String.UnicodeScalarView(text.prefix(200).unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : scalar
        }))
    }
}
