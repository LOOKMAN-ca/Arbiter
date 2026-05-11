import SwiftUI
import WebKit

// MARK: — In-app login sheet (Xcode-style)

struct WebAuthSheet: View {
    let title: String
    let loginURL: URL
    @Binding var apiKey: String
    @Environment(\.dismiss) var dismiss

    @State private var pasteBuffer = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            WebView(url: loginURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            keyBar
        }
        .background(Color.arbiterBg)
        .frame(minWidth: 780, minHeight: 580)
    }

    private var header: some View {
        HStack {
            Text(title.uppercased())
                .font(ArbiterFont.mono(12).bold())
                .foregroundColor(.arbiterCyan)
            Spacer()
            Button("✕") { dismiss() }.buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.55))
        .overlay(
            Rectangle().fill(Color.arbiterBorder).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var keyBar: some View {
        VStack(spacing: 8) {
            Text("After signing in, navigate to your API keys page, copy a key, and paste it below.")
                .font(ArbiterFont.mono(9))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                SecureField("Paste API key here…", text: $pasteBuffer)
                    .textFieldStyle(.roundedBorder)
                    .font(ArbiterFont.mono(11))

                Button("SAVE KEY") {
                    apiKey = pasteBuffer
                    dismiss()
                }
                .font(ArbiterFont.mono(10).bold())
                .foregroundColor(.arbiterCyan)
                .disabled(pasteBuffer.isEmpty)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.arbiterCyan.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.arbiterCyan.opacity(pasteBuffer.isEmpty ? 0.15 : 0.5), lineWidth: 0.5)
                )
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.45))
        .overlay(
            Rectangle().fill(Color.arbiterBorder).frame(height: 0.5),
            alignment: .top
        )
    }
}

// MARK: — WKWebView wrapper

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
