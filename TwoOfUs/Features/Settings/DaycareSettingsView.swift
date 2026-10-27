import SwiftUI
import SwiftData
import MapKit

/// Settings → Integrations → Daycare: the place itself (name, room, phone),
/// its rhythm (hours, days), where it is (map pin), and the geofence arrival
/// prompts. Everything but the location permission is shared — one parent
/// sets it up, the other's phone gets it through sync.
///
/// Laid out Apple-Settings style: a profile card up top, tinted icon squares
/// on every row, quiet captions under the toggles, and a slider for the
/// geofence radius.
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

    // The slider moves locally and commits on release — a sync save per
    // drag tick would spam CloudKit (and the geofence re-registration).
    @State private var radius: Double = 200

    @State private var camera: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var searchError: String?

    private var settings: SharedSettings? { SharedSettings.canonical(settingsList) }
    private var store: EventStore { EventStore(context: context) }
    private var babyName: String { babies.first?.name ?? "your baby" }

    private var canEditShared: Bool {
        (participants.first { $0.id == prefs.myParticipantID }?.role ?? .full) == .full
    }

    /// Whether the sliders run in geofence mode ON THIS PHONE (mirrors
    /// `HomeView.geofenceSliderMode`): fence configured and enabled, Always
    /// location granted here. Decides which of the two modes this page
    /// explains — and hides the time-based pick-up setting the fence replaces.
    private var geofenceModeActive: Bool {
        settings?.daycareGeofenceEnabled == true
            && settings?.daycareCoordinate != nil
            && geofence.hasAlwaysPermission
    }

    var body: some View {
        Form {
            if let settings, canEditShared {
                profileSection(settings)
                placeSection(settings)
                hoursSection(settings)
                daysSection(settings)
                locationSection(settings)
                remindersSection(settings)
            }
        }
        .listStyle(.insetGrouped)
        .tint(AppColor.accentCheck)
        .navigationTitle("Daycare")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .onAppear(perform: load)
        .onDisappear(perform: commitTextFields)
        .onChange(of: settings?.daycareGeofenceRadiusMeters) { _, new in
            // Keep the slider honest when the other phone moves it.
            if let new { radius = new }
        }
    }

    // MARK: Profile card

    /// The place as a contact card — icon, name, room, address, one-tap call —
    /// so the page opens on *who this is about*, not a wall of fields.
    private func profileSection(_ settings: SharedSettings) -> some View {
        Section {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AppColor.accentCheck.gradient)
                        .frame(width: 64, height: 64)
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 2) {
                    Text(settings.daycareDisplayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.center)
                    if !settings.daycareRoom.isEmpty {
                        Text("Room: \(settings.daycareRoom)")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                    }
                    if !settings.daycareAddress.isEmpty {
                        Text(settings.daycareAddress)
                            .font(.footnote)
                            .foregroundStyle(AppColor.text3)
                            .multilineTextAlignment(.center)
                    }
                }
                if let url = dialURL(settings.daycarePhone) {
                    Link(destination: url) {
                        Label("Call", systemImage: "phone.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(AppColor.accentCheck.opacity(0.14),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.accentCheck)
                    .accessibilityLabel("Call \(settings.daycareDisplayName)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: The place

    private func placeSection(_ settings: SharedSettings) -> some View {
        Section {
            LabeledContent {
                TextField("Little Owls Daycare", text: $name)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitTextFields)
            } label: {
                SettingsIconLabel(title: "Name", systemImage: "building.2.fill",
                                  tint: AppColor.accentCheck)
            }
            LabeledContent {
                TextField("Owls", text: $room)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitTextFields)
            } label: {
                SettingsIconLabel(title: "Room", systemImage: "door.left.hand.open",
                                  tint: AppColor.accentActivity)
            }
            LabeledContent {
                TextField("(555) 123-4567", text: $phone)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.phonePad)
                    .onSubmit(commitTextFields)
            } label: {
                SettingsIconLabel(title: "Phone", systemImage: "phone.fill",
                                  tint: AppColor.accentHealth)
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
            DatePicker(selection: minuteBinding(settings.daycareOpenMinute) {
                store.updateDaycare(openMinute: $0)
                geofence.refreshMonitoring()
            }, displayedComponents: .hourAndMinute) {
                SettingsIconLabel(title: "Opens", systemImage: "sunrise.fill",
                                  tint: AppColor.accentDiaper)
            }
            DatePicker(selection: minuteBinding(settings.daycareCloseMinute) {
                store.updateDaycare(closeMinute: $0)
                geofence.refreshMonitoring()
            }, displayedComponents: .hourAndMinute) {
                SettingsIconLabel(title: "Closes", systemImage: "sunset.fill",
                                  tint: AppColor.accentSleep)
            }
            // The time-based pick-up setting is the fence's fallback: with
            // the fence running on this phone, arrival is what surfaces the
            // slider, and a redundant clock row would only invite confusion.
            if !geofenceModeActive {
                DatePicker(selection: minuteBinding(settings.daycarePickupShowMinute) {
                    store.updateDaycare(pickupShowMinute: $0)
                }, displayedComponents: .hourAndMinute) {
                    SettingsIconLabel(title: "Pick-up from", systemImage: "car.fill",
                                      tint: AppColor.accentCheck)
                }
            }
        } header: {
            Text("Hours")
        } footer: {
            Text(geofenceModeActive
                 ? "Opening and closing times bound the arrival sliders: an evening visit (a parents' night) shows nothing. With no pick-up logged, the daycare day is assumed over at closing time."
                 : "Without arrival detection, the clock decides: the drop-off slider appears when the doors open, and the pick-up slider from \"Pick-up from\". With no pick-up logged, the daycare day is assumed over at closing time.")
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
                SettingsIconLabel(title: "", systemImage: "mappin.and.ellipse",
                                  tint: AppColor.accentMedication)
                    .labelStyle(.iconOnly)
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
                    SettingsIconLabel(title: "Remove Pin",
                                      systemImage: "mappin.slash.fill",
                                      tint: AppColor.urgencyRed)
                        .foregroundStyle(AppColor.urgencyRed)
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
                SettingsIconLabel(title: "Arrival Prompts",
                                  systemImage: "location.circle.fill",
                                  tint: AppColor.accentCheck,
                                  subtitle: "Ask to log the drop-off or pick-up when a phone arrives")
            }
            .disabled(settings.daycareCoordinate == nil)

            if settings.daycareGeofenceEnabled {
                VStack(spacing: 6) {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(radius)) m")
                            .foregroundStyle(AppColor.text2)
                            .monospacedDigit()
                    }
                    Slider(value: $radius, in: 100...500, step: 25) { editing in
                        if !editing {
                            store.updateDaycare(geofenceRadiusMeters: radius)
                            geofence.refreshMonitoring()
                        }
                    }
                    .accessibilityLabel("Geofence radius")
                    .accessibilityValue("\(Int(radius)) meters")
                }

                if !geofence.hasAlwaysPermission {
                    permissionRow
                }
            }
        } header: {
            Text("Arrival Detection")
        } footer: {
            Text(footerText(settings))
        }
    }

    /// The two modes, spelled out where the toggle lives: with the fence,
    /// arrival drives everything and a home day is implicit silence; without
    /// it, the times above take over.
    private func footerText(_ settings: SharedSettings) -> String {
        guard settings.daycareCoordinate != nil else {
            return "Place the pin above first. Until then, the drop-off and "
                + "pick-up sliders follow the times in Hours."
        }
        let place = settings.daycareDisplayName
        if geofenceModeActive {
            return "Arrival mode is on: the drop-off and pick-up sliders appear "
                + "only on the phone that's actually at \(place) (during its hours), "
                + "plus a lock-screen prompt — the other phone just sees that "
                + "someone's there. On a day no phone visits, nothing shows at all: "
                + "weekends and sick days stay quiet, no button needed. "
                + "Your location never leaves this phone."
        }
        return "With this on and \"Always\" location allowed, the sliders appear "
            + "only when a phone actually arrives at \(place) — and days with no "
            + "visit stay quiet. Until then, they follow the times in Hours "
            + "(time mode). Your location never leaves this phone."
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
        radius = settings.daycareGeofenceRadiusMeters
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

    private func dialURL(_ raw: String) -> URL? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }
}
