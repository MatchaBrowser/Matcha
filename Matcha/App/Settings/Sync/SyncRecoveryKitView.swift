import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Recovery kit of the sync account (`SYNC.md` § 3.3): the server's address, the email and the recovery key, the only
/// way back into the account without the master password. Saved as a PDF or printed before continuing.
struct SyncRecoveryKitView: View {
    let kit: SyncRecoveryKit
    /// Called once the kit is saved or printed.
    let done: () -> Void

    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save Your Recovery Kit", systemImage: "key.fill")
                .font(.title2.weight(.semibold))
            Text("""
            If you forget your master password, this kit is the only way to get your synced data back. Matcha can't \
            recover it for you. Keep it somewhere safe, away from this Mac.
            """, comment: "Recovery kit sheet: explanation")
                .fixedSize(horizontal: false, vertical: true)
            SyncRecoveryKitPage(kit: kit)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            HStack {
                Button("Save as PDF…") { savePDF() }
                Button("Print…") { printKit() }
                Spacer()
                Button("Continue") { done() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isSaved)
                    .accessibilityIdentifier("recoveryKitContinueButton")
            }
            if !isSaved {
                Text("Save or print the kit to continue.", comment: "Recovery kit sheet: why Continue is disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = String(localized: "Matcha Recovery Kit.pdf", comment: "File name of the saved recovery kit")
        guard panel.runModal() == .OK, let url = panel.url, let data = pdf() else {
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            isSaved = true
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func printKit() {
        let view = NSHostingView(rootView: SyncRecoveryKitPage(kit: kit).frame(width: 480).environment(\.colorScheme, .light))
        view.frame = NSRect(x: 0, y: 0, width: 480, height: view.fittingSize.height)
        let operation = NSPrintOperation(view: view)
        operation.printInfo.horizontalPagination = .fit
        operation.printInfo.verticalPagination = .automatic
        if operation.run() {
            isSaved = true
        }
    }

    /// One A4 page with the kit, in light mode.
    @MainActor
    private func pdf() -> Data? {
        let renderer = ImageRenderer(content: SyncRecoveryKitPage(kit: kit).frame(width: 480).environment(\.colorScheme, .light))
        let data = NSMutableData()
        renderer.render { size, render in
            var box = CGRect(x: 0, y: 0, width: 595, height: 842)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
                return
            }
            context.beginPDFPage(nil)
            context.translateBy(x: (box.width - size.width) / 2, y: box.height - size.height - 60)
            render(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }
}

/// The kit itself: what is shown, saved and printed.
struct SyncRecoveryKitPage: View {
    let kit: SyncRecoveryKit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Matcha Recovery Kit", comment: "Title of the recovery kit page")
                .font(.headline)
            row(Text("Server", comment: "Recovery kit: server address"), kit.server.normalized)
            row(Text("Email", comment: "Recovery kit: account identifier"), kit.email)
            row(Text("Recovery key", comment: "Recovery kit: the key"), kit.recoveryKey)
                .font(.system(.body, design: .monospaced))
            Text("Created on \(Date.now.formatted(date: .long, time: .omitted))", comment: "Recovery kit: creation date")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .textSelection(.enabled)
        }
    }
}
