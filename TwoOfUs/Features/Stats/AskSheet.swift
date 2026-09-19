import SwiftUI

/// "Ask about Miller": a small on-device chat over the log. Lives on Stats
/// next to the generated cards, and only when the AI toggle is on and the
/// model is available — the same gate as those cards.
struct AskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: AskSession
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(babyName: String) {
        _session = State(initialValue: AskSession(babyName: babyName))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if session.messages.isEmpty {
                                starters
                            }
                            ForEach(session.messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                            if session.isResponding {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Reading the log…")
                                        .font(.subheadline)
                                        .foregroundStyle(AppColor.text2)
                                }
                                .padding(.horizontal, 4)
                                .id("responding")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: session.messages.count) {
                        withAnimation { proxy.scrollTo(session.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: session.isResponding) {
                        if session.isResponding { withAnimation { proxy.scrollTo("responding", anchor: .bottom) } }
                    }
                }

                composer
            }
            .background(AppColor.bg)
            .navigationTitle("Ask about \(session.babyName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(AIGlow.mark) Ask anything about \(session.babyName)'s feeds, sleep, or diapers.")
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
            ForEach(session.suggestions, id: \.self) { suggestion in
                Button {
                    Task { await session.ask(suggestion) }
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCard(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
            Text("Answers are generated on your iPhone from your own logs. Not medical advice.")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
                .padding(.top, 4)
        }
    }

    private func bubble(_ message: AskSession.Message) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            if message.role == .user {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [AppColor.indigoHi, AppColor.indigoLo],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            } else {
                // Same gradient hairline as the generated Stats cards — the
                // boundary of "the model wrote this" stays consistent.
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .surfaceCard(cornerRadius: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: AIGlow.colors.map { $0.opacity(0.35) },
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    )
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Answer"): \(message.text)")
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(send)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .surfaceCard(cornerRadius: 18)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AppColor.accentSleep : AppColor.text3)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColor.bg)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isResponding
    }

    private func send() {
        guard canSend else { return }
        let question = draft
        draft = ""
        Task { await session.ask(question) }
    }
}
