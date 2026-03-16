//
//  LoginView.swift
//  closet
//
//  Created by Codex on 2026/3/11.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    @State private var mode: AuthFormMode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1, green: 0.95, blue: 0.96),
                    Color(red: 0.93, green: 0.95, blue: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Lumina Closet")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(ClosetTheme.textPrimary)
                    Text("AI 智能衣橱管理助手")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary)
                }

                VStack(spacing: 18) {
                    Picker("模式", selection: $mode) {
                        Text("登录").tag(AuthFormMode.login)
                        Text("注册").tag(AuthFormMode.register)
                    }
                    .pickerStyle(.segmented)

                    if mode == .register {
                        TextField("用户名", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("密码", text: $password)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ClosetTheme.rose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(mode == .login ? "登录" : "注册")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(ClosetTheme.accentGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || !isFormValid)

                    Button("跳过登录，先使用本地功能") {
                        appViewModel.continueAsGuest()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClosetTheme.textSecondary)

                    Text("跳过后仍可使用本地衣橱、日记、照片管理；AI、天气、账号同步等联网功能将不可用。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ClosetTheme.textSecondary.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var isFormValid: Bool {
        if mode == .register && username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            do {
                switch mode {
                case .login:
                    try await appViewModel.login(email: email, password: password)
                case .register:
                    try await appViewModel.register(username: username, email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription + "。你也可以先跳过登录进入本地模式。"
            }
        }
    }
}

private enum AuthFormMode {
    case login
    case register
}
