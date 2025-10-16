import SwiftUI
import PhotosUI
import CoreLocation

// =====================================================
// MARK: - MODEL
// =====================================================

struct HuntItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var hint: String

    var found: Bool
    var photoData: Data?
    var foundAt: Date?
    var address: String?

    init(id: UUID = UUID(),
         title: String,
         hint: String,
         found: Bool = false,
         photoData: Data? = nil,
         foundAt: Date? = nil,
         address: String? = nil) {
        self.id = id
        self.title = title
        self.hint = hint
        self.found = found
        self.photoData = photoData
        self.foundAt = foundAt
        self.address = address
    }
}

// =====================================================
// MARK: - DATA STORE (with simple JSON persistence)
// =====================================================

@MainActor
final class HuntStore: ObservableObject {
    @Published var items: [HuntItem] = [] {
        didSet { save() }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("hunt.json")
    }()

    init() {
        if !load() {
            // Seed default items if no saved data
            items = [
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
            save()
        }
    }

    var foundCount: Int { items.filter(\.found).count }
    var allFound: Bool { foundCount == items.count }
    var hasDiscount: Bool { foundCount >= 7 }

    func markFound(_ item: HuntItem, photoData: Data?, address: String?) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].found = true
        items[i].foundAt = Date()
        items[i].photoData = photoData
        items[i].address = address
    }

    func removePhoto(_ item: HuntItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].photoData = nil
        // keep found status; if you want to unmark, set found=false and clear foundAt/address
    }

    func resetAll() {
        for i in items.indices {
            items[i].found = false
            items[i].photoData = nil
            items[i].foundAt = nil
            items[i].address = nil
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save error:", error.localizedDescription)
        }
    }

    @discardableResult
    private func load() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([HuntItem].self, from: data)
            return true
        } catch {
            print("Load error:", error.localizedDescription)
            return false
        }
    }
}

// =====================================================
// MARK: - LOCATION SERVICE
// =====================================================

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var lastLocation: CLLocation?
    @Published var lastAddress: String?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestAuthIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func captureAddress() {
        requestAuthIfNeeded()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async { self.lastLocation = loc }

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self else { return }
            let p = placemarks?.first
            let line1 = [p?.subThoroughfare, p?.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let line2 = [p?.locality, p?.administrativeArea].compactMap { $0 }.joined(separator: ", ")
            let line3 = p?.postalCode ?? ""
            let addr = [line1, line2, line3].filter { !$0.isEmpty }.joined(separator: " • ")
            DispatchQueue.main.async { self.lastAddress = addr.isEmpty ? nil : addr }
        }
    }
}

// =====================================================
// MARK: - APP
// =====================================================

@main
struct IOSApp2App: App {
    @StateObject private var store = HuntStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
        }
    }
}

// =====================================================
// MARK: - MAIN LIST VIEW
// =====================================================

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
                                    Text(item.hint)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.found {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                }
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
            } message: {
                Text("This will clear all photos, timestamps, and addresses.")
            }
        }
    }
}

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

// =====================================================
// MARK: - DETAIL VIEW
// =====================================================

struct ItemDetailView: View {
    @EnvironmentObject private var store: HuntStore
    @EnvironmentObject private var location: LocationService

    let item: HuntItem

    @State private var flipped = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pickedImageData: Data?

    private var currentItem: HuntItem {
        store.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    CardFront(title: currentItem.title,
                              hint: currentItem.hint,
                              found: currentItem.found)
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
                    Label(currentItem.photoData == nil ? "Pick/Take Photo" : "Change Photo",
                          systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedPhoto) { _, newValue in
                    // Trigger location capture and load photo
                    location.captureAddress()
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            pickedImageData = data
                        }
                    }
                }

                HStack {
                    Button {
                        store.markFound(currentItem,
                                        photoData: pickedImageData ?? currentItem.photoData,
                                        address: location.lastAddress)
                    } label: {
                        Label(currentItem.found ? "Marked as Found" : "Mark as Found",
                              systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled((currentItem.found == false) && (pickedImageData == nil))
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        store.removePhoto(currentItem)
                        pickedImageData = nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(currentItem.photoData == nil)
                    .buttonStyle(.bordered)
                }

                if let ts = currentItem.foundAt {
                    Text("Found: \(ts.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let addr = currentItem.address, !addr.isEmpty {
                    Text("Address: \(addr)")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pickedImageData = currentItem.photoData
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
