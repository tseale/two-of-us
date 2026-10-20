import SwiftUI
import SwiftData
import MapKit

/// Settings → Integrations → Daycare: the place itself (name, room, phone),
/// its rhythm (hours, days), where it is (map pin), and the geofence arrival
/// prompts. Everything but the location permission is shared — one parent
/// sets it up, the other's phone gets it through sync.
struct DaycareSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [SharedSettings]
    @Query private var participants: [Participant]
    @Query private var babies: [Baby]
    @State private var prefs = LocalPrefs.shared
    @State private var geofence = DaycareGeofenceManager.shared

    // Text fields edit locally and commit on submit / page exit — committing
    // every keystroke would push a sync save per letter.
    @State private var name = ""
    @State private var room = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var loaded = false

    @State private var camera: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var searchError: String?

    private var settings: SharedSettings? { SharedSettings.canonical(settingsList) }
    private var store: EventStore { EventStore(context: context) }
    private var babyName: String { babies.first?.name ?? "your baby" }

    private var canEditShared: Bool {
        (participants.first { $0.id == prefs.myParticipantID }?.role ?? .full) == .full
    }

    private let radiusOptions: [Double] = [100, 200, 500]

    var body: some View {
        Form {
            if let settings, canEditShared {
                placeSection(settings)
                hoursSection(settings)
                daysSection(settings)
                locationSection(settings)
                remindersSection(settings)
            }
        }
        .navigationTitle("Daycare")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .onAppear(perform: load)
        .onDisappear(perform: commitTextFields)
    }

    // MARK: The place

    private func placeSection(_ settings: SharedSettings) -> some View {
        Section {
            LabeledContent("Name") {
                TextField("Little Owls Daycare", text: $name)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitTextFields)
            }
            LabeledContent("Room") {
                TextField("Owls", text: $room)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitTextFields)
            }
            LabeledContent("Phone") {
                TextField("(555) 123-4567", text: $phone)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.phonePad)
                    .onSubmit(commitTextFields)
            }
            if let url = dialURL(settings.daycarePhone) {
                Link(destination: url) {
                    SettingsIconLabel(title: "Call \(settings.daycareDisplayName)",
                                      systemImage: "phone.fill",
                                      tint: AppColor.accentCheck)
                }
            }
        } header: {
            Text("The Place")
        } footer: {
            Text("The name shows up wherever the app says \"Daycare\" today. Room should match the classroom name Brightwheel uses.")
        }
    }

    // MARK: Hours & days

    private func hoursSection(_ settings: SharedSettings) -> some View {
        Section {
            DatePicker("Opens",
                       selection: minuteBinding(settings.daycareOpenMinute) {
                           store.updateDaycare(openMinute: $0)
                           geofence.refreshMonitoring()
                       },
                       displayedComponents: .hourAndMinute)
            DatePicker("Closes",
                       selection: minuteBinding(settings.daycareCloseMinute) {
                           store.updateDaycare(closeMinute: $0)
                           geofence.refreshMonitoring()
                       },
                       displayedComponents: .hourAndMinute)
        } header: {
            Text("Hours")
        } footer: {
            Text("The drop-off button appears when the doors open; with no pick-up logged, the daycare day is assumed over at closing time.")
        }
    }

    private func daysSection(_ settings: SharedSettings) -> some View {
        Section {
            HStack(spacing: 8) {
                // Calendar weekday numbers, laid out in the local week order.
                let calendar = Calendar.current
                let symbols = calendar.veryShortWeekdaySymbols   // Sun-first
                let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
                ForEach(order, id: \.self) { index in
                    let weekday = index + 1
                    let on = settings.daycareDays.contains(weekday)
                    Button {
                        var days = settings.daycareDays
                        if on { days.remove(weekday) } else { days.insert(weekday) }
                        store.updateDaycare(days: days)
                        Haptics.tap()
                    } label: {
                        Text(symbols[index])
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(on ? Color.white : AppColor.text2)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? AppColor.accentCheck : AppColor.card2,
                                        in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.weekdaySymbols[index])
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Days")
        } footer: {
            Text("Drop-off and pick-up buttons (and arrival prompts) only show on these days.")
        }
    }

    // MARK: Location

    @ViewBuilder
    private func locationSection(_ settings: SharedSettings) -> some View {
        Section {
            HStack {
                TextField("Address", text: $address)
                    .textInputAutocapitalization(.words)
                    .onSubmit { search(settings) }
                if isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Find") { search(settings) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.accentCheck)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            map(settings)
                .frame(height: 220)
                .listRowInsets(EdgeInsets())

            Button {
                Task { await useCurrentLocation(settings) }
            } label: {
                SettingsIconLabel(title: "Use Current Location",
                                  systemImage: "location.fill",
                                  tint: AppColor.accentCheck)
            }
            if settings.daycareCoordinate != nil {
                Button(role: .destructive) {
                    store.updateDaycare(location: .some(nil))
                    geofence.refreshMonitoring()
                } label: {
                    Text("Remove Pin")
                }
            }
        } header: {
            Text("Location")
        } footer: {
            if let searchError {
                Text(searchError).foregroundStyle(AppColor.urgencyRed)
            } else {
                Text("Search the address or tap the map to place the pin — it anchors the arrival prompts below.")
            }
        }
    }

    private func map(_ settings: SharedSettings) -> some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let c = settings.daycareCoordinate {
                    let coordinate = CLLocationCoordinate2D(latitude: c.latitude,
                                                            longitude: c.longitude)
                    Annotation(settings.daycareDisplayName, coordinate: coordinate) {
                        Image(systemName: "building.2.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(AppColor.accentCheck, in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                    }
                    MapCircle(center: coordinate, radius: settings.daycareGeofenceRadiusMeters)
                        .foregroundStyle(AppColor.accentCheck.opacity(0.12))
                        .stroke(AppColor.accentCheck.opacity(0.45), lineWidth: 1.5)
                }
            }
            .onTapGesture { position in
                if let coordinate = proxy.convert(position, from: .local) {
                    setPin(coordinate, recenter: false)
                }
            }
        }
    }

    // MARK: Arrival prompts

    private func remindersSection(_ settings: SharedSettings) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.daycareGeofenceEnabled },
                set: { on in
                    store.updateDaycare(geofenceEnabled: on)
                    if on { geofence.requestPermission() }
                    geofence.refreshMonitoring()
                }
            )) {
                SettingsIconLabel(title: "Arrival Prompts", systemImage: "location.circle.fill",
                                  tint: AppColor.accentCheck)
            }
            .disabled(settings.daycareCoordinate == nil)

            if settings.daycareGeofenceEnabled {
                Picker("Radius", selection: Binding(
                    get: { nearestRadius(settings.daycareGeofenceRadiusMeters) },
                    set: {
                        store.updateDaycare(geofenceRadiusMeters: $0)
                        geofence.refreshMonitoring()
                    }
                )) {
                    ForEach(radiusOptions, id: \.self) { r in
                        Text("\(Int(r)) m").tag(r)
                    }
                }
                .pickerStyle(.segmented)

                if !geofence.hasAlwaysPermission {
                    permissionRow
                }
            }
        } header: {
            Text("Arrival Prompts")
        } footer: {
            Text(settings.daycareCoordinate == nil
                 ? "Place the pin above first."
                 : "Arriving at \(settings.daycareDisplayName) in the morning asks to log the drop-off; arriving while \(babyName) is there asks about the pick-up. Needs \"Always\" location access so the prompt can fire with the app closed — your location never leaves this phone.")
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch geofence.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            Button {
                geofence.requestPermission()
            } label: {
                SettingsIconLabel(title: "Allow \"Always\" Location",
                                  systemImage: "exclamationmark.triangle.fill",
                                  tint: AppColor.urgencyAmber)
            }
        default:
            // Denied/restricted: the system prompt won't show again — only
            // the Settings app can flip it now.
            Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                SettingsIconLabel(title: "Allow Location in Settings",
                                  systemImage: "exclamationmark.triangle.fill",
                                  tint: AppColor.urgencyAmber)
            }
        }
    }

    // MARK: Plumbing

    private func load() {
        guard !loaded, let settings else { return }
        loaded = true
        name = settings.daycareName
        room = settings.daycareRoom
        phone = settings.daycarePhone
        address = settings.daycareAddress
        if let c = settings.daycareCoordinate {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                latitudinalMeters: 1200, longitudinalMeters: 1200))
        }
    }

    private func commitTextFields() {
        guard loaded, let settings else { return }
        // Only write what changed — an untouched visit mustn't mint a sync save.
        store.updateDaycare(
            name: name != settings.daycareName ? name : nil,
            room: room != settings.daycareRoom ? room : nil,
            phone: phone != settings.daycarePhone ? phone : nil,
            address: address != settings.daycareAddress ? address : nil
        )
    }

    private func setPin(_ coordinate: CLLocationCoordinate2D, recenter: Bool) {
        store.updateDaycare(location: (coordinate.latitude, coordinate.longitude))
        geofence.refreshMonitoring()
        Haptics.tap()
        if recenter {
            withAnimation {
                camera = .region(MKCoordinateRegion(center: coordinate,
                                                    latitudinalMeters: 1200,
                                                    longitudinalMeters: 1200))
            }
        }
    }

    private func search(_ settings: SharedSettings) {
        let query = address.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isSearching else { return }
        isSearching = true
        searchError = nil
        Task {
            defer { isSearching = false }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .address
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                searchError = "Couldn't find that address — try adding the city, or tap the map instead."
                return
            }
            setPin(item.placemark.coordinate, recenter: true)
            commitTextFields()
        }
    }

    private func useCurrentLocation(_ settings: SharedSettings) async {
        if geofence.authorizationStatus == .notDetermined {
            geofence.requestPermission()
            return
        }
        guard let coordinate = await geofence.currentLocation() else {
            searchError = "Couldn't get a location fix — check location access in Settings."
            return
        }
        setPin(coordinate, recenter: true)
    }

    /// Minutes-from-midnight ↔ the DatePicker's Date, pinned to today so DST
    /// can't shift the stored wall-clock minute.
    private func minuteBinding(_ minute: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
        )
    }

    private func nearestRadius(_ value: Double) -> Double {
        radiusOptions.min { abs($0 - value) < abs($1 - value) } ?? 200
    }

    private func dialURL(_ raw: String) -> URL? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }
}
