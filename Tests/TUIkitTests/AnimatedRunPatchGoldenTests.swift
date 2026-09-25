//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AnimatedRunPatchGoldenTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// `FrameBuffer.patchingAnimatedCells` and `splicing` used to walk the line
/// three or four times per call; they walk it once now. This pins the bytes
/// they produce, on nine line shapes × five frames × four columns × three
/// widths, to what the four-walk form produced — captured from it before the
/// change as a 64-bit FNV-1a of each output, patch then splice, per
/// (column, width) in order.
///
/// The patch no longer reads the field under a run off the line; it is handed
/// one per cell (the run's ground, in the run loop). Handed the fields the line
/// has under the frame's columns — which is what the four-walk form read off it —
/// it still produces the four-walk bytes, which is what `String.paintedOver(fields:)`
/// promises for a frame over one field.
///
/// The splice no longer paints its span over the field where the span lands
/// (2026-09-24): an opacity span states every field it has, `ESC[49m` included,
/// and painted over the line's field a 49 was filled. So the SPLICE half of the
/// four rows that land a field-less frame on a field — line 3's blue, at column 8,
/// frames 0–3 — was re-captured from the splice that takes its span literally:
/// the frame's bytes between the reset in front and the line's restored styling,
/// with no `ESC[44m` put in. Every other hash, and every patch hash, is the
/// four-walk form's still.
@Suite("The one-walk run patch and splice produce the four-walk bytes")
struct AnimatedRunPatchGoldenTests {

    /// The field `line` has under each of `count` columns from `column`, `nil` for
    /// the terminal's own; a column past the line's end is on whatever the line
    /// leaves in force.
    private static func fields(of line: String, from column: Int, count: Int) -> [SGRState.Colour?] {
        var state = SGRState()
        var cells: [SGRState.Colour?] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character):
                cells += Array(repeating: state.backgroundColour, count: max(1, character.terminalWidth))
            }
        }
        return (column..<(column + count)).map { $0 < cells.count ? cells[$0] : state.backgroundColour }
    }

    private static let esc = "\u{1B}"
    private static let lines: [String] = [
        "plain text line", "", "ab",
        "\(esc)[31mred\(esc)[0m and \(esc)[44mblue bg\(esc)[0m tail",
        "\(esc)[0;1;32mbold green\(esc)[0m x \(esc)[48;5;22mdark\(esc)[49m end",
        "wide \u{1F600} emoji \(esc)[4munder\(esc)[24m",
        "\(esc)]8;;http://x\(esc)\\link\(esc)]8;;\(esc)\\ after",
        "\(esc)[7mreverse\(esc)[27m normal",
        "short\(esc)[31m",
    ]
    private static let frames: [String] = [
        "\(esc)[33m▓\(esc)[0m", "▒▒", "\(esc)[0;35m*\(esc)[0m*", "  ", "\(esc)[42m \(esc)[0m",
    ]
    private static let widths = [1, 2, 3]

    private static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16).leftPadded(to: 16)
    }

    @Test("Every captured case matches")
    func golden() {
        var checked = 0
        for row in Self.goldenRows {
            let parts = row.split(separator: "|")
            let li = Int(parts[0])!
            let fi = Int(parts[1])!
            let column = Int(parts[2])!
            let hashes = parts[3].split(separator: ",").map(String.init)
            var cursor = 0
            do {
                for width in Self.widths {
                    let line = Self.lines[li]
                    let frame = Self.frames[fi]
                    let patched = FrameBuffer.patchingAnimatedCells(
                        in: line, with: frame, atColumn: column, width: width,
                        fields: AnimatedCellRun.GroundFields(
                            bare: Self.fields(of: line, from: column, count: frame.strippedLength),
                            // No frame here states `ESC[49m`, so nothing reads these.
                            underStatedDefault: []))
                    let spliced = FrameBuffer.splicing(frame, into: line, atColumn: column)
                    #expect(Self.fnv1a(patched) == hashes[cursor], "patch line \(li) frame \(fi) col \(column) w \(width): \(patched.debugDescription)")
                    #expect(Self.fnv1a(spliced) == hashes[cursor + 1], "splice line \(li) frame \(fi) col \(column) w \(width): \(spliced.debugDescription)")
                    cursor += 2
                    checked += 2
                }
            }
        }
        #expect(checked == 1080)
    }

    /// `line|frame|column|hashes…` — six hashes per row: patch then splice, per width.
    private static let goldenRows: [String] = [
        "0|0|0|133142d4c3c84f47,133142d4c3c84f47,133142d4c3c84f47,133142d4c3c84f47,133142d4c3c84f47,133142d4c3c84f47",
        "0|0|3|a4abd714455bc73a,a4abd714455bc73a,a4abd714455bc73a,a4abd714455bc73a,a4abd714455bc73a,a4abd714455bc73a",
        "0|0|8|ba088364149f5071,ba088364149f5071,ba088364149f5071,ba088364149f5071,ba088364149f5071,ba088364149f5071",
        "0|0|20|17fe43993680ef81,17fe43993680ef81,45fc7e579d172e93,17fe43993680ef81,033961dfee645a29,17fe43993680ef81",
        "0|1|0|1fdbfabc12fba8c4,1fdbfabc12fba8c4,1fdbfabc12fba8c4,1fdbfabc12fba8c4,1fdbfabc12fba8c4,1fdbfabc12fba8c4",
        "0|1|3|9261eb0a07eccdc3,9261eb0a07eccdc3,9261eb0a07eccdc3,9261eb0a07eccdc3,9261eb0a07eccdc3,9261eb0a07eccdc3",
        "0|1|8|60d9d7c57748be40,60d9d7c57748be40,60d9d7c57748be40,60d9d7c57748be40,60d9d7c57748be40,60d9d7c57748be40",
        "0|1|20|0729b0ce9552687c,0729b0ce9552687c,0729b0ce9552687c,0729b0ce9552687c,7e3fcb07bb075454,0729b0ce9552687c",
        "0|2|0|b4a0c54d6bb7a85b,b4a0c54d6bb7a85b,b4a0c54d6bb7a85b,b4a0c54d6bb7a85b,b4a0c54d6bb7a85b,b4a0c54d6bb7a85b",
        "0|2|3|09867ecd38a56fdc,09867ecd38a56fdc,09867ecd38a56fdc,09867ecd38a56fdc,09867ecd38a56fdc,09867ecd38a56fdc",
        "0|2|8|b2a2b2703acd2401,b2a2b2703acd2401,b2a2b2703acd2401,b2a2b2703acd2401,b2a2b2703acd2401,b2a2b2703acd2401",
        "0|2|20|b1a5233a48b4b41b,b1a5233a48b4b41b,b1a5233a48b4b41b,b1a5233a48b4b41b,904f17098b0e4041,b1a5233a48b4b41b",
        "0|3|0|3fc59533d73fdaa8,3fc59533d73fdaa8,3fc59533d73fdaa8,3fc59533d73fdaa8,3fc59533d73fdaa8,3fc59533d73fdaa8",
        "0|3|3|ecf992d434477bd3,ecf992d434477bd3,ecf992d434477bd3,ecf992d434477bd3,ecf992d434477bd3,ecf992d434477bd3",
        "0|3|8|98be28940605ffc0,98be28940605ffc0,98be28940605ffc0,98be28940605ffc0,98be28940605ffc0,98be28940605ffc0",
        "0|3|20|0abc7aa0138be7ec,0abc7aa0138be7ec,0abc7aa0138be7ec,0abc7aa0138be7ec,ca2c2a0136badfa4,0abc7aa0138be7ec",
        "0|4|0|a157e004cf6e3e5a,a157e004cf6e3e5a,a157e004cf6e3e5a,a157e004cf6e3e5a,a157e004cf6e3e5a,a157e004cf6e3e5a",
        "0|4|3|513755fcebb27ee1,513755fcebb27ee1,513755fcebb27ee1,513755fcebb27ee1,513755fcebb27ee1,513755fcebb27ee1",
        "0|4|8|4c78cb42a69cd14c,4c78cb42a69cd14c,4c78cb42a69cd14c,4c78cb42a69cd14c,4c78cb42a69cd14c,4c78cb42a69cd14c",
        "0|4|20|280e17dc3fa06c5c,280e17dc3fa06c5c,b05f07401d9856b4,280e17dc3fa06c5c,49cfe5f249db1d7c,280e17dc3fa06c5c",
        "1|0|0|e83ce6487daeb13c,e83ce6487daeb13c,4e2c692d8fd6f294,e83ce6487daeb13c,ac696c6b6a3e67dc,e83ce6487daeb13c",
        "1|0|3|bd187c549606e62a,bd187c549606e62a,57814dbaedb8e2fe,bd187c549606e62a,6999f2a1f1297f3a,bd187c549606e62a",
        "1|0|8|6cd6c27fc3656ddc,6cd6c27fc3656ddc,565a7b190559e334,6cd6c27fc3656ddc,15a23f8417bcdafc,6cd6c27fc3656ddc",
        "1|0|20|441275e07c300b6c,441275e07c300b6c,db69987305a33224,441275e07c300b6c,77a00f72944dfccc,441275e07c300b6c",
        "1|1|0|fb3f49fe6fcee685,fb3f49fe6fcee685,fb3f49fe6fcee685,fb3f49fe6fcee685,bb716057fc91ea5f,fb3f49fe6fcee685",
        "1|1|3|08c9aa419ca2b447,08c9aa419ca2b447,08c9aa419ca2b447,08c9aa419ca2b447,9160b47d28788b05,08c9aa419ca2b447",
        "1|1|8|f2547818303f21a5,f2547818303f21a5,f2547818303f21a5,f2547818303f21a5,04a99619fb45f4ff,f2547818303f21a5",
        "1|1|20|219ad5c547b5a355,219ad5c547b5a355,219ad5c547b5a355,219ad5c547b5a355,cfbcb338d9a4bfcf,219ad5c547b5a355",
        "1|2|0|ff66fa4932d5fd54,ff66fa4932d5fd54,ff66fa4932d5fd54,ff66fa4932d5fd54,d1f8be61619dac1c,ff66fa4932d5fd54",
        "1|2|3|39ec377e2e5fdce2,39ec377e2e5fdce2,39ec377e2e5fdce2,39ec377e2e5fdce2,cc3f0d68cce41da6,39ec377e2e5fdce2",
        "1|2|8|c617b49ed3f6e5f4,c617b49ed3f6e5f4,c617b49ed3f6e5f4,c617b49ed3f6e5f4,912dbde22c88873c,c617b49ed3f6e5f4",
        "1|2|20|baf9725f55bf75a4,baf9725f55bf75a4,baf9725f55bf75a4,baf9725f55bf75a4,7552dbfeb454af4c,baf9725f55bf75a4",
        "1|3|0|7233687295598c89,7233687295598c89,7233687295598c89,7233687295598c89,66e723b3c72a032b,7233687295598c89",
        "1|3|3|c2cce7641d5dcbcb,c2cce7641d5dcbcb,c2cce7641d5dcbcb,c2cce7641d5dcbcb,5ff91a1de6618051,c2cce7641d5dcbcb",
        "1|3|8|bfbb0de2d19d8429,bfbb0de2d19d8429,bfbb0de2d19d8429,bfbb0de2d19d8429,685ca16a2ea75b4b,bfbb0de2d19d8429",
        "1|3|20|8bdfb428c8953ad9,8bdfb428c8953ad9,8bdfb428c8953ad9,8bdfb428c8953ad9,425a1a4cd593351b,8bdfb428c8953ad9",
        "1|4|0|2b84fa2bb0121671,2b84fa2bb0121671,050b693c2ebbeba3,2b84fa2bb0121671,4e4f544369512f99,2b84fa2bb0121671",
        "1|4|3|1c98a98036fece1f,1c98a98036fece1f,963643dd72f8750d,1c98a98036fece1f,36aa7e4a5c2f1b77,1c98a98036fece1f",
        "1|4|8|a52154f4aff2f511,a52154f4aff2f511,8a988cc6f9d6a243,a52154f4aff2f511,57d9991a87b5ee39,a52154f4aff2f511",
        "1|4|20|4ec5bbb945c2e561,4ec5bbb945c2e561,9ce33cd18a2b8d73,4ec5bbb945c2e561,c1adab0dc8012409,4ec5bbb945c2e561",
        "2|0|0|4e2cab2d8fd762ba,4e2cab2d8fd762ba,4e2cab2d8fd762ba,4e2cab2d8fd762ba,ad49786b6afc8bae,4e2cab2d8fd762ba",
        "2|0|3|7715cef5183d4e5b,7715cef5183d4e5b,975d2578302c5b01,7715cef5183d4e5b,5fa1cc39db5ed913,7715cef5183d4e5b",
        "2|0|8|f781aacd4f0f343f,f781aacd4f0f343f,a08959dd56d590ad,f781aacd4f0f343f,9ef4401a8ce49f97,f781aacd4f0f343f",
        "2|0|20|4da98d47bd91ce9f,4da98d47bd91ce9f,88e9cfe71ec24e8d,4da98d47bd91ce9f,679af2b9442baff7,4da98d47bd91ce9f",
        "2|1|0|fb3f49fe6fcee685,fb3f49fe6fcee685,fb3f49fe6fcee685,fb3f49fe6fcee685,bb716057fc91ea5f,fb3f49fe6fcee685",
        "2|1|3|2166130cff362862,2166130cff362862,2166130cff362862,2166130cff362862,f69aa115a9066826,2166130cff362862",
        "2|1|8|d76fd50954143c4e,d76fd50954143c4e,d76fd50954143c4e,d76fd50954143c4e,27436cd9de62aeea,d76fd50954143c4e",
        "2|1|20|40e771b1dd7a5dae,40e771b1dd7a5dae,40e771b1dd7a5dae,40e771b1dd7a5dae,c3a3bf3b56ecf84a,40e771b1dd7a5dae",
        "2|2|0|ff66fa4932d5fd54,ff66fa4932d5fd54,ff66fa4932d5fd54,ff66fa4932d5fd54,d1f8be61619dac1c,ff66fa4932d5fd54",
        "2|2|3|db4d67c52148b0a5,db4d67c52148b0a5,db4d67c52148b0a5,db4d67c52148b0a5,ed37d8f78e83f1ff,db4d67c52148b0a5",
        "2|2|8|3d22f905125d7131,3d22f905125d7131,3d22f905125d7131,3d22f905125d7131,3fde349e34c71fe3,3d22f905125d7131",
        "2|2|20|7050ec6a40290091,7050ec6a40290091,7050ec6a40290091,7050ec6a40290091,0282698b05ac2cc3,7050ec6a40290091",
        "2|3|0|7233687295598c89,7233687295598c89,7233687295598c89,7233687295598c89,66e723b3c72a032b,7233687295598c89",
        "2|3|3|a7e6dfd931eeef92,a7e6dfd931eeef92,a7e6dfd931eeef92,a7e6dfd931eeef92,3c3e100fd9014b76,a7e6dfd931eeef92",
        "2|3|8|3c9d7edc34c588ee,3c9d7edc34c588ee,3c9d7edc34c588ee,3c9d7edc34c588ee,c5275e2daba7760a,3c9d7edc34c588ee",
        "2|3|20|1a9ba1b3ae54e94e,1a9ba1b3ae54e94e,1a9ba1b3ae54e94e,1a9ba1b3ae54e94e,8b5d32513a48a5ea,1a9ba1b3ae54e94e",
        "2|4|0|050b2b3c2ebb8249,050b2b3c2ebb8249,050b2b3c2ebb8249,050b2b3c2ebb8249,4d7ce043689e986b,050b2b3c2ebb8249",
        "2|4|3|b9af83289c4b5226,b9af83289c4b5226,d08de40193fc6032,b9af83289c4b5226,5d7a80ae75d73e96,b9af83289c4b5226",
        "2|4|8|6f683b7e1462d1ea,6f683b7e1462d1ea,b0eee13ca3ea7a3e,6f683b7e1462d1ea,9062d80a876d80fa,6f683b7e1462d1ea",
        "2|4|20|186dcbbf0ba41a4a,186dcbbf0ba41a4a,26ab9fa0c7d8e21e,186dcbbf0ba41a4a,8e827c3395886f5a,186dcbbf0ba41a4a",
        "3|0|0|262c504ae4c4c691,262c504ae4c4c691,262c504ae4c4c691,262c504ae4c4c691,262c504ae4c4c691,262c504ae4c4c691",
        "3|0|3|eefb717ea8ab54af,eefb717ea8ab54af,eefb717ea8ab54af,eefb717ea8ab54af,eefb717ea8ab54af,eefb717ea8ab54af",
        "3|0|8|5b24dbdcc8334dcb,28d80e2d9b3b4090,5b24dbdcc8334dcb,28d80e2d9b3b4090,5b24dbdcc8334dcb,28d80e2d9b3b4090",
        "3|0|20|fc4dce9706bb3521,fc4dce9706bb3521,736b0ba0701b10b3,fc4dce9706bb3521,39f5549e7dfd29c9,fc4dce9706bb3521",
        "3|1|0|46208ad454962b03,46208ad454962b03,46208ad454962b03,46208ad454962b03,46208ad454962b03,46208ad454962b03",
        "3|1|3|ef0d45ee007e6dcb,ef0d45ee007e6dcb,ef0d45ee007e6dcb,ef0d45ee007e6dcb,ef0d45ee007e6dcb,ef0d45ee007e6dcb",
        "3|1|8|135446b6ce2f6bce,4f1ff6b649a8a3f3,135446b6ce2f6bce,4f1ff6b649a8a3f3,135446b6ce2f6bce,4f1ff6b649a8a3f3",
        "3|1|20|f099502fd57f751c,f099502fd57f751c,f099502fd57f751c,f099502fd57f751c,53f87d47c79434f4,f099502fd57f751c",
        "3|2|0|8e432fe04b22d9e6,8e432fe04b22d9e6,8e432fe04b22d9e6,8e432fe04b22d9e6,8e432fe04b22d9e6,8e432fe04b22d9e6",
        "3|2|3|816c2b691c475e08,816c2b691c475e08,816c2b691c475e08,816c2b691c475e08,816c2b691c475e08,816c2b691c475e08",
        "3|2|8|efc78404b9ea0d53,005bb736568a4436,efc78404b9ea0d53,005bb736568a4436,efc78404b9ea0d53,005bb736568a4436",
        "3|2|20|c8bcb3a35cf649bb,c8bcb3a35cf649bb,c8bcb3a35cf649bb,c8bcb3a35cf649bb,0eeed996f67f1261,c8bcb3a35cf649bb",
        "3|3|0|624c4a2287eb604f,624c4a2287eb604f,624c4a2287eb604f,624c4a2287eb604f,624c4a2287eb604f,624c4a2287eb604f",
        "3|3|3|329f7eb9f2eb319b,329f7eb9f2eb319b,329f7eb9f2eb319b,329f7eb9f2eb319b,329f7eb9f2eb319b,329f7eb9f2eb319b",
        "3|3|8|3c9781dfa7a1e5f2,4dbbfc0318c10b73,3c9781dfa7a1e5f2,4dbbfc0318c10b73,3c9781dfa7a1e5f2,4dbbfc0318c10b73",
        "3|3|20|afdb4944daa1060c,afdb4944daa1060c,afdb4944daa1060c,afdb4944daa1060c,72a3abff7f9d7cc4,afdb4944daa1060c",
        "3|4|0|4219605749d48c6e,4219605749d48c6e,4219605749d48c6e,4219605749d48c6e,4219605749d48c6e,4219605749d48c6e",
        "3|4|3|f882f55db6785a24,f882f55db6785a24,f882f55db6785a24,f882f55db6785a24,f882f55db6785a24,f882f55db6785a24",
        "3|4|8|566610d74fb7a4ca,1afc68ff563b7809,566610d74fb7a4ca,1afc68ff563b7809,566610d74fb7a4ca,1afc68ff563b7809",
        "3|4|20|8503c03c45619efc,8503c03c45619efc,66fe8269e4e0efd4,8503c03c45619efc,e3678defea37bb9c,8503c03c45619efc",
        "4|0|0|a7b1120afaceb4d6,a7b1120afaceb4d6,a7b1120afaceb4d6,a7b1120afaceb4d6,a7b1120afaceb4d6,a7b1120afaceb4d6",
        "4|0|3|e44cb02d801786f9,e44cb02d801786f9,e44cb02d801786f9,e44cb02d801786f9,e44cb02d801786f9,e44cb02d801786f9",
        "4|0|8|5a19866d28b193aa,5a19866d28b193aa,5a19866d28b193aa,5a19866d28b193aa,5a19866d28b193aa,5a19866d28b193aa",
        "4|0|20|6f9fc91b2bbf4ccd,6f9fc91b2bbf4ccd,6bcfa62b560fb6b7,6f9fc91b2bbf4ccd,418df2a33cb34295,6f9fc91b2bbf4ccd",
        "4|1|0|04d56d1667c1d360,04d56d1667c1d360,04d56d1667c1d360,04d56d1667c1d360,04d56d1667c1d360,04d56d1667c1d360",
        "4|1|3|2f80bb5f50dcbbdc,2f80bb5f50dcbbdc,2f80bb5f50dcbbdc,2f80bb5f50dcbbdc,2f80bb5f50dcbbdc,2f80bb5f50dcbbdc",
        "4|1|8|832aaf5e5379468b,832aaf5e5379468b,832aaf5e5379468b,832aaf5e5379468b,832aaf5e5379468b,832aaf5e5379468b",
        "4|1|20|6e89e1f9d960d430,6e89e1f9d960d430,6e89e1f9d960d430,6e89e1f9d960d430,351f0b8c5f885730,6e89e1f9d960d430",
        "4|2|0|72460e4a188f007f,72460e4a188f007f,72460e4a188f007f,72460e4a188f007f,72460e4a188f007f,72460e4a188f007f",
        "4|2|3|5d64f6cd30a7d939,5d64f6cd30a7d939,5d64f6cd30a7d939,5d64f6cd30a7d939,5d64f6cd30a7d939,5d64f6cd30a7d939",
        "4|2|8|374e44323e6d054c,374e44323e6d054c,374e44323e6d054c,374e44323e6d054c,374e44323e6d054c,374e44323e6d054c",
        "4|2|20|fbfa7624a9e5106f,fbfa7624a9e5106f,fbfa7624a9e5106f,fbfa7624a9e5106f,0fa70f4cb03ab63d,fbfa7624a9e5106f",
        "4|3|0|aaff294f10e4f5f4,aaff294f10e4f5f4,aaff294f10e4f5f4,aaff294f10e4f5f4,aaff294f10e4f5f4,aaff294f10e4f5f4",
        "4|3|3|cf2ee9117dd157e8,cf2ee9117dd157e8,cf2ee9117dd157e8,cf2ee9117dd157e8,cf2ee9117dd157e8,cf2ee9117dd157e8",
        "4|3|8|62a0f8725dee612f,62a0f8725dee612f,62a0f8725dee612f,62a0f8725dee612f,62a0f8725dee612f,62a0f8725dee612f",
        "4|3|20|bf312791a63407b0,bf312791a63407b0,bf312791a63407b0,bf312791a63407b0,148dcc7d6a68d9b0,bf312791a63407b0",
        "4|4|0|13dd7cd02cda1d9b,13dd7cd02cda1d9b,13dd7cd02cda1d9b,13dd7cd02cda1d9b,13dd7cd02cda1d9b,13dd7cd02cda1d9b",
        "4|4|3|2f9c2df1873a862e,2f9c2df1873a862e,2f9c2df1873a862e,2f9c2df1873a862e,2f9c2df1873a862e,2f9c2df1873a862e",
        "4|4|8|f20df68e4990615b,f20df68e4990615b,f20df68e4990615b,f20df68e4990615b,f20df68e4990615b,f20df68e4990615b",
        "4|4|20|3f349ed96998e158,3f349ed96998e158,ff4b636e6ec71ee8,3f349ed96998e158,9438bca63c594dd8,3f349ed96998e158",
        "5|0|0|392c223bfdba80bd,392c223bfdba80bd,392c223bfdba80bd,392c223bfdba80bd,392c223bfdba80bd,392c223bfdba80bd",
        "5|0|3|889fef752cb0c417,889fef752cb0c417,889fef752cb0c417,889fef752cb0c417,889fef752cb0c417,889fef752cb0c417",
        "5|0|8|96b266a22c2903df,96b266a22c2903df,96b266a22c2903df,96b266a22c2903df,96b266a22c2903df,96b266a22c2903df",
        "5|0|20|48a7503a2fc0e040,48a7503a2fc0e040,352db2df24bd4320,48a7503a2fc0e040,19e9f12b6d98d900,48a7503a2fc0e040",
        "5|1|0|2dcbcb9987d3b3e3,2dcbcb9987d3b3e3,2dcbcb9987d3b3e3,2dcbcb9987d3b3e3,2dcbcb9987d3b3e3,2dcbcb9987d3b3e3",
        "5|1|3|c2714fb067ee6c04,c2714fb067ee6c04,c2714fb067ee6c04,c2714fb067ee6c04,c2714fb067ee6c04,c2714fb067ee6c04",
        "5|1|8|6c3cf31a1d1c28c5,6c3cf31a1d1c28c5,6c3cf31a1d1c28c5,6c3cf31a1d1c28c5,6c3cf31a1d1c28c5,6c3cf31a1d1c28c5",
        "5|1|20|f82d56a309481771,f82d56a309481771,f82d56a309481771,f82d56a309481771,fd218808c57f9ea3,f82d56a309481771",
        "5|2|0|cc6945021fd7ad4a,cc6945021fd7ad4a,cc6945021fd7ad4a,cc6945021fd7ad4a,cc6945021fd7ad4a,cc6945021fd7ad4a",
        "5|2|3|5f09240dcf61a413,5f09240dcf61a413,5f09240dcf61a413,5f09240dcf61a413,5f09240dcf61a413,5f09240dcf61a413",
        "5|2|8|3ff64a63572f3604,3ff64a63572f3604,3ff64a63572f3604,3ff64a63572f3604,3ff64a63572f3604,3ff64a63572f3604",
        "5|2|20|6854f857af05bf70,6854f857af05bf70,6854f857af05bf70,6854f857af05bf70,4e214cfe66c414f0,6854f857af05bf70",
        "5|3|0|e0ec57ade6922507,e0ec57ade6922507,e0ec57ade6922507,e0ec57ade6922507,e0ec57ade6922507,e0ec57ade6922507",
        "5|3|3|c0912ae9c8294150,c0912ae9c8294150,c0912ae9c8294150,c0912ae9c8294150,c0912ae9c8294150,c0912ae9c8294150",
        "5|3|8|3b9845c58a727e21,3b9845c58a727e21,3b9845c58a727e21,3b9845c58a727e21,3b9845c58a727e21,3b9845c58a727e21",
        "5|3|20|2571d96c4082d815,2571d96c4082d815,2571d96c4082d815,2571d96c4082d815,234ca7f19e55620f,2571d96c4082d815",
        "5|4|0|3c3731aa69a03dce,3c3731aa69a03dce,3c3731aa69a03dce,3c3731aa69a03dce,3c3731aa69a03dce,3c3731aa69a03dce",
        "5|4|3|3fde662d2fdf7916,3fde662d2fdf7916,3fde662d2fdf7916,3fde662d2fdf7916,3fde662d2fdf7916,3fde662d2fdf7916",
        "5|4|8|6b7ab8ebfd704fe4,6b7ab8ebfd704fe4,6b7ab8ebfd704fe4,6b7ab8ebfd704fe4,6b7ab8ebfd704fe4,6b7ab8ebfd704fe4",
        "5|4|20|e62ebeee3dce8d55,e62ebeee3dce8d55,effbe3d305fa5dcf,e62ebeee3dce8d55,c3620e93286d9d1d,e62ebeee3dce8d55",
        "6|0|0|6dbc5a23cfb68626,6dbc5a23cfb68626,6dbc5a23cfb68626,6dbc5a23cfb68626,6dbc5a23cfb68626,6dbc5a23cfb68626",
        "6|0|3|2bb7c5d5ed56bc62,2bb7c5d5ed56bc62,2bb7c5d5ed56bc62,2bb7c5d5ed56bc62,2bb7c5d5ed56bc62,2bb7c5d5ed56bc62",
        "6|0|8|32465f0e27354d13,32465f0e27354d13,32465f0e27354d13,32465f0e27354d13,a2e0b80c9f922da9,32465f0e27354d13",
        "6|0|20|b743562c36c3a148,b743562c36c3a148,2b0cd5210e6b43b8,b743562c36c3a148,9211bf2b8043db48,b743562c36c3a148",
        "6|1|0|3ffa3326aaa60be8,3ffa3326aaa60be8,3ffa3326aaa60be8,3ffa3326aaa60be8,3ffa3326aaa60be8,3ffa3326aaa60be8",
        "6|1|3|ca3a8813439267a7,ca3a8813439267a7,ca3a8813439267a7,ca3a8813439267a7,ca3a8813439267a7,ca3a8813439267a7",
        "6|1|8|3de89accae97973a,3de89accae97973a,3de89accae97973a,3de89accae97973a,c9d623ccab95c12e,3de89accae97973a",
        "6|1|20|29f1aeda1b14ee99,29f1aeda1b14ee99,29f1aeda1b14ee99,29f1aeda1b14ee99,5a9ad59c0491a45b,29f1aeda1b14ee99",
        "6|2|0|4d48cd73eb24da9d,4d48cd73eb24da9d,4d48cd73eb24da9d,4d48cd73eb24da9d,4d48cd73eb24da9d,4d48cd73eb24da9d",
        "6|2|3|ceb5aebb97f5c4f0,ceb5aebb97f5c4f0,ceb5aebb97f5c4f0,ceb5aebb97f5c4f0,ceb5aebb97f5c4f0,ceb5aebb97f5c4f0",
        "6|2|8|d307da15fd6f6cdd,d307da15fd6f6cdd,d307da15fd6f6cdd,d307da15fd6f6cdd,05c4905da45631e7,d307da15fd6f6cdd",
        "6|2|20|211f41a74478bfb8,211f41a74478bfb8,211f41a74478bfb8,211f41a74478bfb8,c0dc2739592d8f48,211f41a74478bfb8",
        "6|3|0|aad7da105569633c,aad7da105569633c,aad7da105569633c,aad7da105569633c,aad7da105569633c,aad7da105569633c",
        "6|3|3|3e6fca13541cdedb,3e6fca13541cdedb,3e6fca13541cdedb,3e6fca13541cdedb,3e6fca13541cdedb,3e6fca13541cdedb",
        "6|3|8|37da503ea8d2deca,37da503ea8d2deca,37da503ea8d2deca,37da503ea8d2deca,bad54478de50c79e,37da503ea8d2deca",
        "6|3|20|216b63d42bad94fd,216b63d42bad94fd,216b63d42bad94fd,216b63d42bad94fd,770f7e8637f3f387,216b63d42bad94fd",
        "6|4|0|99ccd45bdc82292d,99ccd45bdc82292d,99ccd45bdc82292d,99ccd45bdc82292d,99ccd45bdc82292d,99ccd45bdc82292d",
        "6|4|3|9b01490b1474756f,9b01490b1474756f,9b01490b1474756f,9b01490b1474756f,9b01490b1474756f,9b01490b1474756f",
        "6|4|8|33e1914d59c31a04,33e1914d59c31a04,33e1914d59c31a04,33e1914d59c31a04,eb640a6f86856b2c,33e1914d59c31a04",
        "6|4|20|0e9c0b27b6c5f59d,0e9c0b27b6c5f59d,991cb17b92609027,0e9c0b27b6c5f59d,8c519bf9ba14bbe5,0e9c0b27b6c5f59d",
        "7|0|0|5ce8419acc458d89,5ce8419acc458d89,5ce8419acc458d89,5ce8419acc458d89,5ce8419acc458d89,5ce8419acc458d89",
        "7|0|3|359db85462a14494,359db85462a14494,359db85462a14494,359db85462a14494,359db85462a14494,359db85462a14494",
        "7|0|8|0e798c8bf1db003f,0e798c8bf1db003f,0e798c8bf1db003f,0e798c8bf1db003f,0e798c8bf1db003f,0e798c8bf1db003f",
        "7|0|20|8b17164f041abdd5,8b17164f041abdd5,72f8dd43f970c74f,8b17164f041abdd5,cda76980daa2e19d,8b17164f041abdd5",
        "7|1|0|fdfe939c86e2f777,fdfe939c86e2f777,fdfe939c86e2f777,fdfe939c86e2f777,fdfe939c86e2f777,fdfe939c86e2f777",
        "7|1|3|639bef9f0e2cb05d,639bef9f0e2cb05d,639bef9f0e2cb05d,639bef9f0e2cb05d,639bef9f0e2cb05d,639bef9f0e2cb05d",
        "7|1|8|bd621505794934df,bd621505794934df,bd621505794934df,bd621505794934df,bd621505794934df,bd621505794934df",
        "7|1|20|c01620dfa06c2b98,c01620dfa06c2b98,c01620dfa06c2b98,c01620dfa06c2b98,d1c593fd97ce49a8,c01620dfa06c2b98",
        "7|2|0|5e61710200ec2fa8,5e61710200ec2fa8,5e61710200ec2fa8,5e61710200ec2fa8,5e61710200ec2fa8,5e61710200ec2fa8",
        "7|2|3|f73efc50eb07ed0a,f73efc50eb07ed0a,f73efc50eb07ed0a,f73efc50eb07ed0a,f73efc50eb07ed0a,f73efc50eb07ed0a",
        "7|2|8|5035eaca0635131e,5035eaca0635131e,5035eaca0635131e,5035eaca0635131e,5035eaca0635131e,5035eaca0635131e",
        "7|2|20|de74ee40e3d89d17,de74ee40e3d89d17,de74ee40e3d89d17,de74ee40e3d89d17,d94e0f4329132475,de74ee40e3d89d17",
        "7|3|0|9cfce8b2e766177b,9cfce8b2e766177b,9cfce8b2e766177b,9cfce8b2e766177b,9cfce8b2e766177b,9cfce8b2e766177b",
        "7|3|3|10e6c2cdf933c05d,10e6c2cdf933c05d,10e6c2cdf933c05d,10e6c2cdf933c05d,10e6c2cdf933c05d,10e6c2cdf933c05d",
        "7|3|8|37064d8525ef4273,37064d8525ef4273,37064d8525ef4273,37064d8525ef4273,37064d8525ef4273,37064d8525ef4273",
        "7|3|20|7acdf0adc09e11f8,7acdf0adc09e11f8,7acdf0adc09e11f8,7acdf0adc09e11f8,4a01cf3e4c985208,7acdf0adc09e11f8",
        "7|4|0|6f36579d36ebae30,6f36579d36ebae30,6f36579d36ebae30,6f36579d36ebae30,6f36579d36ebae30,6f36579d36ebae30",
        "7|4|3|46342c92fe632483,46342c92fe632483,46342c92fe632483,46342c92fe632483,46342c92fe632483,46342c92fe632483",
        "7|4|8|658fa4f742fa21e0,658fa4f742fa21e0,658fa4f742fa21e0,658fa4f742fa21e0,658fa4f742fa21e0,658fa4f742fa21e0",
        "7|4|20|65dbac2237fb52a0,65dbac2237fb52a0,0f97fe25200d2f80,65dbac2237fb52a0,8c7479157667ece0,65dbac2237fb52a0",
        "8|0|0|e736f6fe8acf8fcc,e736f6fe8acf8fcc,e736f6fe8acf8fcc,e736f6fe8acf8fcc,e736f6fe8acf8fcc,e736f6fe8acf8fcc",
        "8|0|3|17e144fb19756a3b,17e144fb19756a3b,17e144fb19756a3b,17e144fb19756a3b,093251ac42834be1,17e144fb19756a3b",
        "8|0|8|f59a51c80ae38698,f59a51c80ae38698,38bfaeea809deaa8,f59a51c80ae38698,0ba0c0788c558518,f59a51c80ae38698",
        "8|0|20|08f4a7b0270f3778,08f4a7b0270f3778,46f048525edb0a88,08f4a7b0270f3778,65558bf72e331b78,08f4a7b0270f3778",
        "8|1|0|75aa31042f01a46d,75aa31042f01a46d,75aa31042f01a46d,75aa31042f01a46d,75aa31042f01a46d,75aa31042f01a46d",
        "8|1|3|c10262f3cdb506e0,c10262f3cdb506e0,c10262f3cdb506e0,c10262f3cdb506e0,ac14e4468a9a7840,c10262f3cdb506e0",
        "8|1|8|5e6449993ee599ff,5e6449993ee599ff,5e6449993ee599ff,5e6449993ee599ff,4a02ee65e02475ed,5e6449993ee599ff",
        "8|1|20|ac36a32f0d19415f,ac36a32f0d19415f,ac36a32f0d19415f,ac36a32f0d19415f,ba18c7f341ea4acd,ac36a32f0d19415f",
        "8|2|0|e4a03f0f3c410d04,e4a03f0f3c410d04,e4a03f0f3c410d04,e4a03f0f3c410d04,e4a03f0f3c410d04,e4a03f0f3c410d04",
        "8|2|3|ecfca22ddc8a102b,ecfca22ddc8a102b,ecfca22ddc8a102b,ecfca22ddc8a102b,3b579eedbe9942b1,ecfca22ddc8a102b",
        "8|2|8|58b25d3f1baec90a,58b25d3f1baec90a,58b25d3f1baec90a,58b25d3f1baec90a,65dd9c3c09ffd25e,58b25d3f1baec90a",
        "8|2|20|1f609d213ccd5eea,1f609d213ccd5eea,1f609d213ccd5eea,1f609d213ccd5eea,1e89c97a50f8113e,1f609d213ccd5eea",
        "8|3|0|e0239268cc241ef9,e0239268cc241ef9,e0239268cc241ef9,e0239268cc241ef9,e0239268cc241ef9,e0239268cc241ef9",
        "8|3|3|d94260cfbebc0174,d94260cfbebc0174,d94260cfbebc0174,d94260cfbebc0174,e7cbd501197641bc,d94260cfbebc0174",
        "8|3|8|bfdcdb53ef7faa8f,bfdcdb53ef7faa8f,bfdcdb53ef7faa8f,bfdcdb53ef7faa8f,83f35e9ff5ef075d,bfdcdb53ef7faa8f",
        "8|3|20|ea1720c51a340fef,ea1720c51a340fef,ea1720c51a340fef,ea1720c51a340fef,f95c7deb8676dcbd,ea1720c51a340fef",
        "8|4|0|033f961e1f27f077,033f961e1f27f077,033f961e1f27f077,033f961e1f27f077,033f961e1f27f077,033f961e1f27f077",
        "8|4|3|e16a2f4690aa2d7a,e16a2f4690aa2d7a,e16a2f4690aa2d7a,e16a2f4690aa2d7a,b19baee7d12b0fee,e16a2f4690aa2d7a",
        "8|4|8|4ae2fa1dd6209e03,4ae2fa1dd6209e03,604d23b2d96cb579,4ae2fa1dd6209e03,0fc901e773b8263b,4ae2fa1dd6209e03",
        "8|4|20|58c598b9e10b9be3,58c598b9e10b9be3,e35e46d966b9ac59,58c598b9e10b9be3,12dedc698d80119b,58c598b9e10b9be3",
    ]
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
