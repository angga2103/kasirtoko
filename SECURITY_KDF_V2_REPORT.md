# Laporan Keamanan & Upgrade KDF v2 (`SecurityHelper` — Tahap 1)

**Tanggal:** 2026-11-26  
**Branch:** `feat/phase1-multi-device-foundation`  
**File Utama:**
- `lib/utils/security_helper.dart`
- `android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/MainActivity.kt` (`com.kasirtoko.app/security`)
- `android/app/src/main/AndroidManifest.xml` (`android:allowBackup="false"`)
- `lib/database/db_helper.dart` & `lib/providers/auth_provider.dart`
- `lib/models/user.dart`

---

## 1. Spesifikasi KDF v2 & Parameter Kriptografis

| Komponen | Spesifikasi Implementasi |
|---|---|
| **Algoritma** | RFC 8018 **PBKDF2-HMAC-SHA256** (menggunakan library teruji `pointycastle: ^4.0.0` `PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))`, serta akselerasi native Android `SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")` pada API 26+) |
| **Target Iterasi Awal** | **600.000 iterasi** (`SecurityHelper.defaultPbkdf2Iterations = 600000`), output **32 byte** (256-bit) |
| **Salt Unik & Pemisahan Salt** | Random kriptografis 16-byte (`Random.secure()`). `pin_salt` dan `password_salt` dibuat **terpisah sepenuhnya** |
| **Domain Separation** | Input ke PBKDF2 dipisahkan domainnya: `pin` (`SecurityHelper.domainPin`) vs `pw` (`SecurityHelper.domainPassword`) |
| **Pepper & Android Keystore** | 32-byte `SecureRandom` pepper dibungkus dengan key AES-256-GCM (`kasirtoko_pepper_kek_v1`) milik **AndroidKeyStore** dan disimpan terenkripsi di `SharedPreferences` privat (`kasirtoko_keystore_prefs`); dikecualikan dari cloud backup (`android:allowBackup="false"`) dan tidak pernah masuk ke SQLite, backup `.db`, atau Git |
| **Format Hash Berversi (PHC-style)** | `$pbkdf2-sha256$v=2,i=600000,l=32,d=<pin|pw>,p=1$<salt_base64url>$<derived_base64url>` |
| **Verifikasi Waktu Konstan** | `SecurityHelper.constantTimeEquals` membandingkan digest panjang tetap secara konstan |

### Catatan Parity Java <-> Dart
Untuk menjamin kesamaan byte-per-byte antara `SecretKeyFactory` Android (yang menerima `PBEKeySpec(char[])`) dan `pointycastle` Dart (yang menerima `Uint8List`), `_prepareInputAscii` menghitung `base64UrlEncode(HMAC-SHA256(pepperBytes, '$domain:$secret'))`. Hasil base64url adalah ASCII murni sehingga aman diteruskan sebagai `char[]` ke Java dan sebagai UTF-8 bytes ke Dart.

---

## 2. Lookup Index PIN, Migrasi Transparan `legacy_v1 -> v2` & Rate Limit

1. **Lookup O(1) Tanpa Mengorbankan KDF:**
   - Pada skema lama, verifikasi PIN harus mengiterasi semua kasir aktif. Jika diterapkan mentah dengan 600.000 iterasi pada 10 kasir, 1 kesalahan input PIN akan memakan 10 × 600.000 iterasi.
   - Solusi v5 menambahkan kolom `pin_lookup_hash` berisi `base64Url(HMAC-SHA256(pepperBytes, 'lookup:pin:$pin'))`. Saat login PIN, server mencari kandidat berdasarkan `pin_lookup_hash` terlebih dahulu lalu **tetap menjalankan verifikasi PBKDF2-HMAC-SHA256 penuh 600.000 iterasi**.
2. **Migrasi Transparan `legacy_v1 -> v2_pbkdf2_sha256`:**
   - Implementasi verifikator lama (`verifyLegacyV1Secret` — 1.000 putaran HMAC-SHA256) **tetap dipertahankan** (fungsi lama `hashSecret`/`verifySecret` ditandai `@Deprecated` demi kompatibilitas).
   - Pada `DatabaseHelper.authenticateWithPin` dan `authenticateWithPassword`:
     - Akun v1–v4 (`hash_version = 'legacy_v1'`) diverifikasi menggunakan `verifyCredential(...)`.
     - Jika cocok, `_migrateUserToV2IfNeeded` langsung meng-upgrade kredensial ke format PHC v2 dengan `pin_salt` baru (terpisah dari `password_salt`), mengisi `pin_lookup_hash`, menghapus PIN plaintext bila masih ada, memperbarui `hash_version`, dan mencatat event `'migrasi_kdf_akun'` di `audit_logs`.
3. **Rate Limit, Lockout & Audit Keamanan:**
   - Kegagalan autentikasi melacak counter per terminal (`_terminalRateLimits`) dan persisten di kolom `users.failed_pin_count` & `users.pin_locked_until`.
   - Lockout progresif: **5–7 kali gagal -> kunci 60 detik**, **8–9 kali -> 300 detik**, **>= 10 kali -> 900 detik**.
   - Selama akun/terminal terkunci, bahkan PIN/password yang benar akan ditolak deterministik (`AuthAttemptStatus.lockedOut`) sampai masa kunci berakhir atau dipulihkan Owner (`recoverPasswordByOwner`).
   - Setiap kegagalan dan lockout tercatat pada `audit_logs` (`login_gagal`, `pin_lockout`) **tanpa mencatat PIN/password asli** ke log.
4. **Penjagaan Duplikasi PIN:**
   - `AuthProvider.saveEmployee`, `changeOwnCredentials`, dan `recoverPasswordByOwner` memeriksa `DatabaseHelper.isPinAlreadyInUse` sehingga tidak ada dua karyawan aktif yang memiliki PIN sama.

---

## 3. Pengaturan Penyimpanan Rahasia & `.gitignore`

- `.gitignore` diperbarui untuk memblokir: `*.jks`, `*.keystore`, `*.p12`, `*.pem`, `*.key`, `*.db`, `*.db-wal`, `*.db-shm`, `.env`, `.env.*`, `backups/`, `key.properties`.
- `BackupService` dan backup pra-migrasi hanya menyalin `.db` (yang tidak pernah menyimpan Android Keystore KEK maupun pepper mentah).

---

## 4. Hasil Benchmark Performa PBKDF2-HMAC-SHA256

### Terukur di Host Windows (Dart VM JIT / `pointycastle_dart` dalam `Isolate.run`)
1. Scratch benchmark awal (`pbkdf2_bench.dart` sebelum integrasi):
   - `100.000` iterasi: `749 ms`
   - `210.000` iterasi: `1.250 ms`
   - `600.000` iterasi: `3.563 ms`
2. Pengujian otomatis resmi `test/phase1_security_kdf_test.dart` (`SecurityHelper.benchmarkPbkdf2(iterations: 600000)`):
   - Run terbaru (saat suite lengkap `flutter test --no-pub -j 1`): **`600000 iters = 4100 ms`** (run-run sebelumnya di sesi sama: `4140 ms`, `4236 ms`, `4305 ms`).

### Status Benchmark pada Perangkat Android Target
- **Belum diuji pada perangkat Android nyata/emulator** karena `adb devices` tidak mendeteksi perangkat terhubung pada lingkungan kerja saat ini.
- Secara arsitektur, perangkat Android API 26+ akan menjalankan jalur **`SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")`** (implementasi C/BoringSSL native melalui JNI) dan fallback ke `pointycastle_dart` pada API < 26 (`minSdk = 21`).
- **Tindakan lanjutan wajib sebelum rilis produksi:** ukur latensi aktual `SecurityHelper.benchmarkPbkdf2(iterations: 600000)` di perangkat Android Admin target. Karena format hash menyimpan parameter iterasi (`v=2,i=600000,...`) dan verifikator membaca parameter tersebut per hash, apabila perangkat target low-end memakan waktu terlalu lama (khususnya jika jatuh ke jalur software Dart pada API < 26), target iterasi bisa dituning aman tanpa mematahkan hash yang sudah tersimpan.

---

## 5. Hasil Uji Keamanan (`test/phase1_security_kdf_test.dart`)

Seluruh **5/5 pengujian KDF v2 lulus**:
- Paritas vektor standar PBKDF2-HMAC-SHA256 (`1` dan `2` iterasi) pada `derivePbkdf2PointyCastle`.
- Verifikasi format PHC v2 pada `600.000` iterasi, pemisahan domain (`pin` vs `pw`), pemisahan salt, serta pengaruh rotasi pepper Keystore.
- Migrasi transparan `legacy_v1 -> v2_pbkdf2_sha256` untuk login PIN dan login password dengan `pin_salt != password_salt` dan pencatatan audit `migrasi_kdf_akun`.
- Rate limit progresif, lockout pada kegagalan ke-5 (termasuk penolakan saat PIN benar dimasukkan di tengah lockout), pencatatan `login_gagal`/`pin_lockout`, serta validasi keunikan PIN dan salt terpisah di `AuthProvider`.
- Eksekusi benchmark real `600.000` iterasi.
