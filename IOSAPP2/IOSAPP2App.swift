import SwiftUI
import PhotosUI

// MARK: - MODEL & STORE

/// A single scavenger-hunt target
struct HuntItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var hint: String
    var found: Bool
    var photoData: Data?

    init(id: UUID = UUID(), title: String, hint: String, found: Bool = false, photoData: Data? = nil) {
        self.id = id
        self.title = title
        self.hint = hint
        self.found = found
        self.photoData = photoData
    }
}

/// App-wide store (shared using EnvironmentObject)
final class HuntStore: ObservableObject {
    @Published var items: [HuntItem] = [
        .init(title: "City Bookstore",   hint: "Find the aisle with local authors."),
        .init(title: "Main Street Café", hint: "Smells like fresh croissants at 8am."),
        .init(title: "Riverside Park",   hint: "Near the big fountain."),
        .init(title: "Museum Lobby",     hint: "Stand by the dinosaur."),
        .init(title: "Cinema Lobby",     hint: "Poster wall of classic films."),
        .init(title: "City Hall",        hint: "Look for the statue out front."),
        .init(title: "Ice Cream Shop",   hint: "Blue bench by the door."),
        .init(title: "Tech Hub",         hint: "Cowork space on 2nd floor."),
        .init(title: "Art Gallery",      hint: "Red abstract piece in entry."),
        .init(title: "Train Station",    hint: "Platform 2 timetable.")
    ]

    var foundCount: Int { items.filter(\.found).count }
    var allFound: Bool { foundCount == items.count }
    var hasDiscount: Bool { foundCount >= 7 }

    func markFound(_ item: HuntItem, photoData: Data?) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].found = true
        items[idx].photoData = photoData
    }

    func resetAll() {
        for i in items.indices {
            items[i].found = false
            items[i].photoData = nil
        }
    }
}

// MARK: - MAIN APP

@main
struct iOSApp2App: App {
    @StateObject private var store = HuntStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}

// MARK: - MAIN VIEW

struct ContentView: View {
    @EnvironmentObject private var store: HuntStore
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                RewardBanner()

                List {
                    ForEach(store.items) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 12) {
                                StatusDot(found: item.found)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text(item.hint).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.found { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: HuntItem.self) { item in
                    ItemDetailView(item: item)
                }

                Text("Found \(store.foundCount) of \(store.items.count)")
                    .font(.footnote)
                    .padding(.bottom, 6)
            }
            .navigationTitle("City Scavenger Hunt")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }.disabled(store.foundCount == 0)
                }
            }
            .alert("Reset progress?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { store.resetAll() }
            } message: { Text("This will clear all photos and marks.") }
        }
    }
}

// MARK: - SUBVIEWS

struct StatusDot: View {
    let found: Bool
    var body: some View {
        Circle().fill(found ? .green : .gray.opacity(0.3))
            .frame(width: 12, height: 12)
    }
}

struct RewardBanner: View {
    @EnvironmentObject private var store: HuntStore
    var body: some View {
        VStack(spacing: 6) {
            if store.allFound {
                Label("🎉 All 10 found! You’re entered into the $5,000 draw.", systemImage: "trophy.fill")
            } else if store.hasDiscount {
                Label("🏷️ 20% discount unlocked! (7+ items found)", systemImage: "tag.fill")
            } else {
                Label("Find 7 for 20% off — find all 10 for the $5,000 draw!", systemImage: "map.fill")
            }
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - DETAIL VIEW WITH CARD FLIP + PHOTO PICKER

struct ItemDetailView: View {
    @EnvironmentObject private var store: HuntStore
    let item: HuntItem

    @State private var flipped = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pickedImageData: Data?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CardFront(title: item.title, hint: item.hint, found: currentItem.found)
                    .opacity(flipped ? 0 : 1)
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                CardBack(imageData: currentItem.photoData)
                    .opacity(flipped ? 1 : 0)
                    .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(height: 260)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring()) { flipped.toggle() } }

            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .automatic) {
                Label(currentItem.found ? "Update Photo" : "Pick/Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .onChange(of: selectedPhoto) { _, newValue in Task { await loadPickedPhoto(newValue) } }

            Button {
                store.markFound(currentItem, photoData: pickedImageData ?? currentItem.photoData)
            } label: {
                Label(currentItem.found ? "Marked as Found" : "Mark as Found", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(currentItem.found == false && pickedImageData == nil)
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pickedImageData = currentItem.photoData }
    }

    private var currentItem: HuntItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            pickedImageData = data
        }
    }
}

private struct CardFront: View {
    let title: String
    let hint: String
    let found: Bool
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.title2).bold()
                Spacer()
                Image(systemName: found ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(found ? .green : .gray.opacity(0.5))
            }
            Text(hint)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            Spacer()
            Text("Tap card to flip")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }
}

private struct CardBack: View {
    let imageData: Data?
    var body: some View {
        ZStack {
            if let data = imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 36))
                    Text("No photo yet").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .shadow(radius: 4)
    }
}
