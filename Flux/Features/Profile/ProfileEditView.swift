import SwiftUI

/// Own-profile editor: avatar, banner, name, username, bio, location,
/// website, birthday (mirrors the Android ProfileEditScreen).
struct ProfileEditView: View {
    @EnvironmentObject var backend: LocalBackend
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var website = ""
    @State private var birthday: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var hasBirthday = false
    @State private var pendingAvatar: Data?
    @State private var pendingBanner: Data?
    @State private var showAvatarPicker = false
    @State private var showBannerPicker = false
    @State private var saving = false
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                bannerEditor
                form
            }
            .padding(.bottom, 40)
        }
        .background(FluxColors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fluxToast($toast)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
        .sheet(isPresented: $showAvatarPicker) {
            PhotoLibraryPicker { data in
                pendingAvatar = data
            }
        }
        .sheet(isPresented: $showBannerPicker) {
            PhotoLibraryPicker { data in
                pendingBanner = data
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FluxColors.textPrimary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Редактировать профиль")
                .font(.system(size: 17, weight: .bold))
            Spacer()
            if saving {
                ProgressView()
            } else {
                Button {
                    Haptics.light()
                    save()
                } label: {
                    Text("Сохранить")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FluxColors.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FluxColors.background)
    }

    // MARK: Banner + avatar

    private var bannerEditor: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                if let pendingBanner, let image = UIImage(data: pendingBanner) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let path = backend.myProfile.bannerPath, FluxMedia.isStorageRef(path) {
                    RemoteMediaImage(path: path) {
                        FluxBannerView(user: backend.me, bannerPath: nil, height: 180)
                    }
                } else if let path = backend.myProfile.bannerPath, let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    FluxBannerView(user: backend.me, bannerPath: nil, height: 180)
                }
                Color.black.opacity(0.25)
                VStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                    Text("Изменить баннер")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.light()
                showBannerPicker = true
            }

            Group {
                if let pendingAvatar, let image = UIImage(data: pendingAvatar) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 86, height: 86)
                        .clipShape(Circle())
                } else {
                    FluxAvatarView(user: backend.me, size: 86)
                }
            }
            .overlay(Circle().stroke(FluxColors.background, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(FluxColors.gradient)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(FluxColors.background, lineWidth: 2))
                    Image(systemName: "camera")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, 20)
            .padding(.bottom, -43)
            .onTapGesture {
                Haptics.light()
                showAvatarPicker = true
            }
        }
        .padding(.bottom, 43)
        .padding(.top, 8)
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 20) {
            sectionLabel("Основное") {
                VStack(spacing: 0) {
                    fieldTile(icon: "person.fill", color: FluxColors.blue) {
                        FluxTextField(text: $name, hint: "Ваше имя", maxLength: 64)
                    }
                    rowDivider
                    fieldTile(icon: "at", color: FluxColors.violet) {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15))
                            .foregroundStyle(FluxColors.textPrimary)
                            .onChange(of: username) { newValue in
                                let filtered = newValue.filter { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "_" }
                                username = String(filtered.prefix(32))
                            }
                    }
                    rowDivider
                    fieldTile(icon: "text.quote", color: FluxColors.cyan) {
                        TextField("Расскажите о себе...", text: $bio, axis: .vertical)
                            .lineLimit(1...4)
                            .font(.system(size: 15))
                            .foregroundStyle(FluxColors.textPrimary)
                            .onChange(of: bio) { newValue in
                                if newValue.count > 200 {
                                    bio = String(newValue.prefix(200))
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }

            sectionLabel("Дополнительное") {
                VStack(spacing: 0) {
                    fieldTile(icon: "mappin.and.ellipse", color: FluxColors.danger) {
                        FluxTextField(text: $location, hint: "Город, страна", maxLength: 64)
                    }
                    rowDivider
                    fieldTile(icon: "link", color: FluxColors.blue) {
                        FluxTextField(text: $website, hint: "https://example.com", keyboard: .default, maxLength: 128)
                            .keyboardType(.URL)
                    }
                    rowDivider
                    fieldTile(icon: "gift", color: FluxColors.warning) {
                        HStack {
                            Text(hasBirthday ? birthdayString : "")
                                .font(.system(size: 15))
                                .foregroundStyle(hasBirthday ? FluxColors.textPrimary : FluxColors.textTertiary)
                            if !hasBirthday {
                                Text("дд.мм.гггг")
                                    .font(.system(size: 15))
                                    .foregroundStyle(FluxColors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "calendar")
                                .foregroundStyle(FluxColors.warning)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(FluxMotion.decelAnimation) {
                                showBirthdayPicker.toggle()
                            }
                        }
                    }
                    if showBirthdayPicker {
                        rowDivider
                        DatePicker(
                            "Дата рождения",
                            selection: $birthday,
                            in: Calendar.current.date(byAdding: .year, value: -100, to: Date())!...Calendar.current.date(byAdding: .year, value: -5, to: Date())!,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .tint(FluxColors.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 8)
            }

            FluxButton(title: "Сохранить изменения", enabled: !saving, showsProgress: saving) {
                save()
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 8)
        .onAppear { loadExisting() }
    }

    @State private var showBirthdayPicker = false

    private var rowDivider: some View {
        Divider().overlay(FluxColors.separator).padding(.leading, 56)
    }

    private func sectionLabel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(FluxColors.textTertiary)
                .padding(.leading, 4)
            content()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(FluxColors.surface)
                        .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
                )
        }
    }

    private func fieldTile<Content: View>(icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                )
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var birthdayString: String {
        let comps = Calendar.current.dateComponents([.day, .month, .year], from: birthday)
        return String(format: "%02d.%02d.%04d", comps.day ?? 1, comps.month ?? 1, comps.year ?? 2000)
    }

    private func loadExisting() {
        guard let me = backend.me else { return }
        name = me.name
        username = me.username ?? ""
        bio = me.status
        location = backend.myProfile.location ?? ""
        website = backend.myProfile.website ?? ""
        if let raw = backend.myProfile.birthday, let comps = parseBirthday(raw),
           let date = Calendar.current.date(from: comps) {
            birthday = date
            hasBirthday = true
        }
    }

    private func save() {
        guard !saving else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            toast = Toast(text: "Имя не может быть пустым", isError: true)
            return
        }
        saving = true
        Haptics.medium()

        var avatarPath: String?
        if let pendingAvatar {
            avatarPath = FluxMediaStore.saveImage(pendingAvatar, prefix: "avatar")
        }

        Task {
            await backend.updateMe(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                status: bio,
                avatarPath: avatarPath
            )
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUsername.isEmpty, trimmedUsername != backend.me?.username {
                do {
                    try await backend.updateUsername(trimmedUsername)
                } catch {
                    toast = Toast(text: error.localizedDescription, isError: true)
                }
            }
            await backend.updateProfile(
                bannerPath: pendingBanner.flatMap { FluxMediaStore.saveImage($0, prefix: "banner") },
                location: location.isEmpty ? nil : location,
                website: website.isEmpty ? nil : website,
                birthday: hasBirthday ? birthdayString : nil
            )
            saving = false
            Haptics.success()
            dismiss()
        }
    }
}
