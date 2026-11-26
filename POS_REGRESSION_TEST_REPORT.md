# Laporan Pengujian Regresi POS & Suite Tahap 1 (`kasirtoko`)

**Tanggal:** 2026-11-26  
**Branch:** `feat/phase1-multi-device-foundation`  
**Perintah Verifikasi Final (setelah edit kode terakhir):**
- Static analysis: `dart analyze --no-fatal-warnings`
- Full automated test suite: `flutter test --no-pub -j 1`

---

## 1. Hasil Analisis Statis (`dart analyze`)

- **Exit Code:** `0`
- **Errors:** `0`
- **Warnings:** `0`
- **Info lints:** `97` isu `info` pra-eksisting di layar-layar UI lama (identik dengan jumlah `97 issues found` saat baseline sebelum Tahap 1 dimulai; tidak ada warning atau lint baru dari perubahan Tahap 1).

---

## 2. Ringkasan Eksekusi Automated Tests (`flutter test --no-pub -j 1`)

**Total Hasil:** **63 / 63 test PASS (`02:05 +63: All tests passed!`)**, 0 failed, 0 skipped.

| File Pengujian | Jenis | Jumlah Test | Status | Cakupan Utama |
|---|---|---|---|---|
| `test/phase1_cash_register_shift_void_test.dart` | Tahap 1 (Baru) | 3 | PASS | `SHARED_DRAWER` multi-kasir, `INDIVIDUAL_DRAWER` paralel, precedence & konflik `cash_register_assignments`, penolakan laci tidak sah, idempotensi, void shift tertutup & `transaction_voids` |
| `test/phase1_db_v5_migration_test.dart` | Tahap 1 (Baru) | 3 | PASS | Upgrade non-destruktif v4 -> v5 + backup terverifikasi `integrity_check`, WAL/FK/`busy_timeout`, partial unique indexes, normalisasi duplikat open shift lama, rollback saat migrasi gagal |
| `test/phase1_security_kdf_test.dart` | Tahap 1 (Baru) | 5 | PASS | Paritas RFC PBKDF2-HMAC-SHA256 PointyCastle, format PHC v2 600.000 iterasi + Keystore pepper + pemisahan domain/salt, migrasi transparan `legacy_v1 -> v2`, rate limit/lockout + audit log, benchmark 600k host (`4.100 ms`) |
| `test/production_qa_scenarios_test.dart` | Regresi Eksisting | 19 | PASS | Auth, PosProvider qty/stock guard, QuickCash, Kasbon, cicilan piutang, pembelian kas laci, utang supplier, shift wajib, retur & void parsial, cash flow, opname, absensi, audit log, analitik bisnis, logo ESC/POS & PDF barcode, migrasi v1 -> v5 |
| `test/responsive_widget_test.dart` | Regresi UI Eksisting | 7 | PASS | Render responsif `PosScreen`, `PaymentDialog`, `WarehouseDocFormScreen`, `BarcodeGeneratorScreen`, `PurchaseListScreen`, `StockOpname`, `AuditLog`, `DailyReport`, `CashFlow` pada ukuran layar HP & tablet |
| `test/return_forensic_repro_test.dart` | Regresi Retur | 1 | PASS | Regression guard tukar barang & pencegahan tukar kosong |
| `test/return_system_forensic_qa_test.dart` | Regresi Forensik Retur | 13 | PASS | Full/partial retur, bucket damaged/quarantine/sellable, tukar barang same/cross-SKU, saldo kredit pelanggan, kasbon over-return, idempotensi retur, void retur, migrasi v3 -> v5, widget `ReturnScreen` & `PaymentDialog` |
| `test/unit_logic_test.dart` | Regresi Unit Logic | 9 | PASS | Kompatibilitas verifikasi legacy v1 `SecurityHelper`, `BarcodeScanGuard`, harga bertingkat/promo/held orders, `ProductModel` equality, `UserModel` 7 role & 16 permissions (diperbarui dari 15 ke 16 untuk mencakup `open_cash_drawer`), ESC/POS & ESC/P bytes |
| `test/widget_test.dart` | Regresi Utility | 3 | PASS | `CurrencyHelper`, `ImageWatermarkService`, `DateHelper` |

---

## 3. Catatan Keterbukaan Kondisi Uji

1. **Lingkungan Eksekusi:** Seluruh 63 test dieksekusi di **host Windows menggunakan Dart VM + `sqflite_common_ffi`**, bukan di atas perangkat fisik Android / emulator (karena `adb devices` tidak menemukan perangkat terhubung saat sesi berjalan).
2. **Fixture KDF pada Suite Regresi Eksisting:**
   - Pada test `openTestDatabase()`, bila pemanggil tidak mengatur iterasi uji secara eksplisit via `SecurityHelper.configureForTesting(iterations: ...)`, test harness memakai `SecurityHelper.testFixturePbkdf2Iterations` (`50.000` iterasi) agar test regresi lama (seperti `Scenario 1` yang menjalankan 25 derivasi dalam satu test dengan batas timeout bawaan 30 detik di Dart JIT) tidak timeout di host CPU.
   - **Aplikasi produksi (`_initDB`) selalu menggunakan `SecurityHelper.defaultPbkdf2Iterations` (`600.000`) tanpa exception**, dan `test/phase1_security_kdf_test.dart` secara eksplisit menguji & men-benchmark `600.000` iterasi.
3. **Pengujian UI Regresi `unit_logic_test.dart`:** Satu assertion jumlah kunci permission di `unit_logic_test.dart` diperbarui dari `15` menjadi `16` mengikuti penambahan resmi `AppPermissions.openCashDrawer` sesuai persyaratan izin buka laci kasir.
4. **Celah Pengujian Hardware Nyata (Belum Dijalankan):**
   - Belum ada verifikasi pada perangkat fisik Android (Android Keystore hardware-backed AES-GCM wrapping, native `SecretKeyFactory` PBKDF2WithHmacSHA256 pada API 26+, Android Foreground Service `specialUse` saat layar mati / Doze / reboot `BOOT_COMPLETED` / pergantian Wi-Fi <-> Hotspot, serta cetak Bluetooth/USB/laci kasir RJ11 nyata).
