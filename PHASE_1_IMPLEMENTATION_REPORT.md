# Laporan Implementasi Tahap 1 — Fondasi Multi-Device POS Admin (`kasirtoko`)

**Tanggal:** 2026-11-26  
**Repository:** `kasirtoko` (https://github.com/angga2103/kasirtoko)  
**Branch Fitur:** `feat/phase1-multi-device-foundation`  
**Status:** Siap untuk review Tahap 1 dan pengujian di perangkat fisik Android (Tahap 2 server LAN dan pengembangan app `stafkasirtoko` belum dijalankan menunggu persetujuan tertulis berikutnya).

---

## 1. Ringkasan Pemenuhan 4 Keputusan Final Arsitektur

1. **`SecurityHelper` KDF v2 (`lib/utils/security_helper.dart`, `MainActivity.kt`):**
   - Menggunakan library teruji **`pointycastle: ^4.0.0`** (`PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))`) dan **native Android `SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")`** pada API 26+.
   - Target awal **600.000 iterasi**, salt acak 16-byte unik per kredensial (**`pin_salt` terpisah dari `password_salt`**), pemisahan domain (`pin` vs `pw`), pepper 32-byte yang dibungkus AES-256-GCM oleh **`AndroidKeyStore`** (`kasirtoko_pepper_kek_v1`) dengan `android:allowBackup="false"`, dan format hash berversi `$pbkdf2-sha256$v=2,i=600000,l=32,d=<domain>,p=1$<salt>$<hash>`.
   - Migrasi transparan `legacy_v1 -> v2_pbkdf2_sha256` saat login pertama berhasil (`authenticateWithPin` / `authenticateWithPassword`) dengan pencatatan audit `migrasi_kdf_akun`, ditambah rate limit progresif, lockout (`login_gagal`, `pin_lockout`), dan pencegahan duplikasi PIN.
   - Rincian lengkap di `SECURITY_KDF_V2_REPORT.md`.

2. **Android Foreground Service (`PosServerForegroundService.kt`, `ServerBootReceiver.kt`, `AndroidManifest.xml`, `ServerLifecycleBridge`):**
   - Menggunakan tipe **`android:foregroundServiceType="specialUse"`** dengan deklarasi eksplisit `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE` untuk layanan sinkronisasi POS lokal (bukan `dataSync`).
   - Service Tahap 1 berupa lifecycle shell (`START_STICKY`, `NetworkCallback`, `PARTIAL_WAKE_LOCK` terbatas, penanganan `onTaskRemoved`, dan `ServerBootReceiver` pasca-reboot yang patuh pembatasan Android 12–16 dengan notifikasi 1-tap untuk membuka ulang aplikasi) tanpa membuka socket server LAN sebelum Tahap 2.
   - Dokumentasi jujur: layanan latar belakang **tidak pernah dijamin hidup tanpa batas** oleh OEM/Android Doze agresif; status terinterupsi dicatat di `SharedPreferences` privat dan opsi pemeriksaan/permintaan `isIgnoringBatteryOptimizations` tersedia di `ServerLifecycleBridge`.

3. **Cash Register & Deterministic Assignments (`lib/models/cash_register.dart`, `lib/database/db_helper.dart`):**
   - Mengimplementasikan tabel `cash_registers` (seed default `id = 1`, `REG-MAIN`) dan `cash_register_assignments` dengan dukungan assignment berbasis `terminal_id`, `cashier_id`, maupun kombinasi `terminal_id + cashier_id`.
   - Resolver `resolveAuthorizedCashRegisterTxn` menerapkan preseden deterministik `(terminal_id + cashier_id) > (cashier_id) > (terminal_id) > priority DESC`, menolak konflik ambigu dengan spesifisitas dan prioritas identik pada register berbeda, serta menolak transaksi/pembukaan shift bila laci kas tidak sah atau nonaktif.
   - Mendukung penuh operasional `SHARED_DRAWER` (multi-kasir dalam 1 shift toko) dan `INDIVIDUAL_DRAWER` (multi-shift paralel terisolasi per laci kas) serta memperbaiki bug isolasi `getShiftStats`.
   - Rincian lengkap di `CASH_REGISTER_SHIFT_REPORT.md`.

4. **Void Transaksi Shift Tertutup (`TransactionVoidModel`, `transaction_voids`, `DatabaseHelper.voidTransaction`):**
   - Shift berstatus `'closed'` bersifat **immutable** (tidak pernah dimodifikasi secara retroaktif).
   - Transaksi asli mempertahankan `shift_id` dan `cash_register_id` asalnya.
   - Setiap void tercatat sebagai peristiwa baru pada tabel `transaction_voids` (menyimpan `original_transaction_id`, `voided_at`, `voided_by`, `void_reason`, `settlement_shift_id`, `settlement_cash_register_id`, `void_type`, `refund_method`, `refund_amount`, `cash_flow_id`).
   - Memisahkan `pre_payment_void` dan `post_payment_reversal`, menyalurkan refund tunai ke shift settlement aktif terbuka, serta **menahan** void/refund tunai shift tertutup jika belum ada shift aktif yang sah.

---

## 2. Daftar Lengkap File yang Dibuat / Dimodifikasi di `kasirtoko`

### File Baru
- `android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/PosServerForegroundService.kt`
- `android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/ServerBootReceiver.kt`
- `lib/models/cash_register.dart`
- `lib/models/transaction_void.dart`
- `lib/services/server_lifecycle_bridge.dart`
- `test/phase1_security_kdf_test.dart`
- `test/phase1_db_v5_migration_test.dart`
- `test/phase1_cash_register_shift_void_test.dart`
- `PHASE_1_IMPLEMENTATION_REPORT.md`
- `DATABASE_V5_MIGRATION_REPORT.md`
- `SECURITY_KDF_V2_REPORT.md`
- `CASH_REGISTER_SHIFT_REPORT.md`
- `POS_REGRESSION_TEST_REPORT.md`

### File Dimodifikasi
- `.gitignore` (menghalangi commit file keystore/secret/database lokal)
- `pubspec.yaml` & `pubspec.lock` (menambah `pointycastle: ^4.0.0`)
- `android/app/src/main/AndroidManifest.xml` (`allowBackup="false"`, izin & komponen `PosServerForegroundService` `specialUse`, `ServerBootReceiver`)
- `android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/MainActivity.kt` (channel `com.kasirtoko.app/security` & `com.kasirtoko.app/server_lifecycle`, guard API 23 untuk AndroidKeyStore KEK + `minSdk = 21`)
- `lib/utils/security_helper.dart` (PBKDF2-HMAC-SHA256 v2, pepper Keystore abstraction, verifikasi gabungan v1+v2, benchmark)
- `lib/database/db_helper.dart` (Schema v5, WAL/FK/`busy_timeout`, backup pra-migrasi terverifikasi & recovery, Auth KDF v2 + lockout, Cash Register & Assignment CRUD/resolver, refactor shift/transaksi/void/stats)
- `lib/models/user.dart`, `lib/models/shift.dart`, `lib/models/transaction.dart`, `lib/models/cash_flow.dart`, `lib/models/return_settlement.dart`, `lib/models/audit_log.dart`
- `lib/providers/auth_provider.dart`, `lib/providers/cash_flow_provider.dart`, `lib/providers/pos_provider.dart`, `lib/providers/settings_provider.dart`
- `lib/screens/home_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/cash_flow/shift_screen.dart`, `lib/screens/pos/payment_dialog.dart`, `lib/screens/reports/daily_report_screen.dart`, `lib/screens/settings/settings_screen.dart`
- `test/responsive_widget_test.dart`, `test/unit_logic_test.dart`

---

## 3. Verifikasi Keselamatan Scope Tahap 1

- **Tidak ada server HTTP/WebSocket LAN** yang dijalankan di `kasirtoko`.
- **Tidak ada modifikasi kode** maupun build app pada repository `stafkasirtoko`.
- **Tidak ada build APK release final** yang dibuat.
- **Tidak ada data lama, tabel lama, maupun fitur POS lama** yang dihapus.
- **Tidak ada keystore, password, PIN, atau secret** yang disimpan ke Git maupun backup `.db`.

---

## 4. Batasan & Riset/Verifikasi yang Masih Tertunda (Jujur Sebelum Tahap 2)

1. **Verifikasi Perangkat Nyata & Kompilasi Gradle Android:**
   - Pada sesi ini `adb devices` tidak menemukan perangkat Android atau emulator terhubung, dan pengunduhan distribusi Gradle (`gradle-9.3.1-bin.zip`) pada `:app:compileDebugKotlin` dibatalkan karena koneksi unduhan lambat sehingga kompilasi Kotlin native dan eksekusi runtime di perangkat Android fisik **belum teruji**.
   - Pengujian Android fisik perlu dijalankan terlebih dahulu untuk memverifikasi:
     a) `AndroidKeyStore` AES-GCM wrapping & `SecretKeyFactory` PBKDF2WithHmacSHA256 600.000 iterasi (latensi riil perangkat target),  
     b) Perilaku `PosServerForegroundService` (`specialUse`) dan `ServerBootReceiver` di Android 12–15 saat layar mati, Doze mode, dan perpindahan jaringan Wi-Fi/Hotspot.
2. **Langkah Berikutnya (Menunggu Persetujuan Tertulis):**
   - Validasi build debug & benchmark perangkat Android target.
   - Setelah disetujui, lanjut ke **Tahap 2**: implementasi HTTP/WebSocket server TLS + Certificate Pinning + HMAC signing + pairing QR, Print Server antrean `print_jobs`, dan pengembangan aplikasi terminal POS Staff (`stafkasirtoko`).
