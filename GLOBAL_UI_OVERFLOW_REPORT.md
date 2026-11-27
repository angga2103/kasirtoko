# Global UI Overflow Audit & Responsive Layout Report — KasirToko Admin (v2.3.1+6)

## 1. Ringkasan Eksekutif

Audit tata letak responsif global telah diselesaikan untuk **KasirToko Admin** (`v2.3.1+6`) sebagai bagian dari perbaikan menyeluruh sistem POS Multi-Device (`kasirtoko` & `stafkasirtoko`). Seluruh indikasi `RenderFlex overflow`, `DropdownButtonFormField` tanpa `isExpanded: true`, baris tombol/label kaku, dialog `AlertDialog` tanpa pembatas lebar, kartu tinggi tetap pada `GridView`, serta inset keyboard dan skala font sistem Android (`1.0x`, `1.2x`, `1.5x`) telah diperbaiki tanpa menyembunyikan overflow (`ClipRect`) maupun menghilangkan fitur.

## 2. Perbaikan Kasus Terlapor Utama

| Lokasi Terlapor | Akar Masalah | Perbaikan Terverifikasi |
|---|---|---|
| `Server POS LAN & Terminal Staff` (`lib/screens/settings/multi_device_server_screen.dart`) — kartu **Terminal Terdaftar** dropdown **Laci Kasir** & **Printer Default** (`RIGHT OVERFLOWED BY 39 / 159 PIXELS`) | Dua `DropdownButtonFormField<int?>` ditempatkan berdampingan dalam `Row` kaku dan item `DropdownMenuItem` tidak memiliki batas baris/elipsis serta `isExpanded: true`. Selain itu baris card memakai `Container` opak yang memicu assertion `ListTile background color`. | Mengganti `Row` kaku dengan `AppBreakpoints.buildResponsivePair(minPairWidth: 420, spacing: 8, ...)`, menambahkan `isExpanded: true` + `maxLines: 1, overflow: TextOverflow.ellipsis`, memperbaiki dialog `Pairing Terminal Baru`, baris Port HTTPS (`LayoutBuilder`), checksum TLS, dan membungkus kartu dengan `Material`. |
| `SettingsScreen` (`lib/screens/settings/settings_screen.dart`) — dialog **Kelola Laci Kas & Penugasan** | Baris `Prioritas Angka` + tombol `Simpan Assignment` dalam `Row` mengalami overflow pada layar `320x640` skala `1.5x`. | Menggunakan `AppBreakpoints.scrollableDialogContent(...)` (`SizedBox` lebar terbatas untuk menghindari error intrinsik `AlertDialog`) dan `AppBreakpoints.buildResponsivePair(...)`. |
| `PrinterManagementScreen` (`lib/screens/settings/printer_management_screen.dart`) | Badge `PRINTER UTAMA` di sebelah nama printer dan `FloatingActionButton.extended` terdorong ke luar batas kiri pada `320x640` skala `1.5x`. | Mengganti header kartu ke `Wrap` serta beralih ke `FloatingActionButton` ringkas saat lebar layar `< 260 * textScale`. |

## 3. Utilitas Tata Letak Bersama (`lib/utils/app_theme.dart` -> `AppBreakpoints`)

- `textScaleFactor(BuildContext context, {double max = 1.8})`
- `scaledExtent(BuildContext context, {required double fixedHeight, required double textHeight, double maxScale = 1.8})`
- `buildResponsivePair(...)` (otomatis menumpuk `Column` saat `constraints.maxWidth < minPairWidth * textScaleFactor`)
- `boundedDialogWidth(BuildContext context, {double maxWidth = 460})`
- `scrollableDialogContent(BuildContext context, {required Widget child, double maxWidth = 460})`
- `spaceBetweenRow(Widget left, Widget right, {double gap = 8})`

## 4. Daftar File Sumber yang Diperbarui (`kasirtoko`)

- **Tema & Komponen Umum:** `lib/utils/app_theme.dart`, `lib/widgets/image_picker_cropper.dart`
- **Auth & POS Utama:** `lib/screens/login_screen.dart`, `lib/screens/home_screen.dart`, `lib/screens/pos/pos_screen.dart`, `lib/screens/pos/payment_dialog.dart`, `lib/screens/pos/receipt_dialog.dart`, `lib/screens/pos/held_orders_dialog.dart`
- **Server Multi-Device, Pengaturan & Printer:** `lib/screens/settings/multi_device_server_screen.dart`, `lib/screens/settings/settings_screen.dart`, `lib/screens/settings/printer_management_screen.dart`, `lib/screens/settings/receipt_settings_screen.dart`
- **Operasional, Laporan, Stok, Pelanggan & Karyawan:** `lib/screens/cash_flow/shift_screen.dart`, `lib/screens/cash_flow/cash_flow_screen.dart`, `lib/screens/reports/daily_report_screen.dart`, `lib/screens/returns/return_screen.dart`, `lib/screens/products/product_form_screen.dart`, `lib/screens/products/barcode_generator_screen.dart`, `lib/screens/promo/promo_screen.dart`, `lib/screens/purchases/purchase_list_screen.dart`, `lib/screens/service/service_detail_screen.dart`, `lib/screens/service/service_form_screen.dart`, `lib/screens/warehouse/warehouse_docs_screen.dart`, `lib/screens/customers/customer_list_screen.dart`, `lib/screens/debts/debt_list_screen.dart`, `lib/screens/employees/employee_management_screen.dart`, `lib/screens/attendance/attendance_history_screen.dart`, `lib/screens/attendance/attendance_camera_screen.dart`
- **Suite Otomasi & Dokumentasi:** `test/global_responsive_overflow_test.dart`, `pubspec.yaml` (`2.3.1+6`), `docs/screenshots/overflow_audit/*.png`

## 5. Matriks & Hasil Verifikasi Otomatis

Uji responsif baru di `test/global_responsive_overflow_test.dart` menguji **8 ukuran layar** (`320x640`, `360x640`, `360x800`, `390x844`, `412x915`, `480x960`, `800x1280`, `1280x800`), **3 skala font** (`1.0x`, `1.2x`, `1.5x`), **inset keyboard aktif (`bottom: 260`)**, string panjang, serta interaksi nyata pemilihan dropdown **Laci Kasir** dan **Printer Default** dan pembukaan dialog (`Pairing Terminal Baru`, `Kelola Laci & Assignment`, `Tambah Printer`, `Pilih Bulan`).

- **`flutter analyze --no-pub --no-fatal-infos` (`v2.3.1+6`):** **0 error, 0 warning** (`102` info bawaan lint terdahulu).
- **`flutter test --no-pub -j 1` (`v2.3.1+6`):** **70 passed, 0 failed** (mencakup seluruh `global_responsive_overflow_test.dart`, pengujian Phase 1 DB/KDF/shift, Phase 2 LAN/WSS E2E & kapasitas, QA retur forensik, responsif widget, unit & widget tests).
- **Verifikasi Screenshot Visual (`docs/screenshots/overflow_audit/`):**
  - `admin_multi_device_320x640.png`
  - `admin_multi_device_360x640_fs15.png`
  - `admin_multi_device_terminal_card_360x640_fs15.png`
  - `admin_multi_device_800x1280.png`
  - `admin_home_320x640_fs15.png`
  - `admin_shift_320x640_fs15.png`

## 6. Release Split APK Tersertifikasi (`v2.3.1+6`)

Dibangun ulang dengan keystore rilis permanen (`kasirtoko-admin-release.jks`) dan diverifikasi menggunakan `apksigner verify --print-certs`:

- Sertifikat Penanda Tangan: `CN=KasirToko Admin Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
- Fingerprint Sertifikat (SHA-256): `a946a3d88a0dfbaee56cdd13d860fff765aeee540a6bf2a83d340df051934241`
- `KasirToko-Admin-v2.3.1-arm64-v8a-release.apk`: `60.053.648 bytes` (SHA-256: `7c78644091b64e128e6e422e3d55c206eb41e72438b6abeedbec4eb6c4d21f30`)
- `KasirToko-Admin-v2.3.1-armeabi-v7a-release.apk`: `58.753.448 bytes` (SHA-256: `9cd93a61683ee27806de957a8ebc88ea6ed2fdee23b3d7e642997787c4325afd`)

## 7. Catatan Pengujian Perangkat Fisik

Pada workstation pengujian ini (`adb devices`), tidak terdapat perangkat Android fisik yang terhubung melalui USB/ADB. Oleh karena itu, verifikasi penuh dilakukan melalui widget/integration matrix otomatis Flutter + inspeksi visual render PNG Roboto (`320x640` hingga `1280x800`, skala font `1.0x`–`1.5x`). Instalasi dan uji sentuh manual pada perangkat Android fisik dilakukan menggunakan paket APK rilis bertanda tangan di atas.
