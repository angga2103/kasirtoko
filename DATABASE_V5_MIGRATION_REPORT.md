# Laporan Migrasi Database Schema v5 (Tahap 1 — `kasirtoko`)

**Tanggal:** 2026-11-26  
**Branch:** `feat/phase1-multi-device-foundation`  
**Versi Skema:** `4 -> 5` (`DatabaseHelper.dbVersion = 5`)  
**Scope:** Fondasi skema multi-perangkat, KDF v2, idempotensi, assignment laci kas, dan pencatatan void shift tertutup pada aplikasi POS Admin (`kasirtoko`). Tidak ada kode POS Staff atau server LAN yang diaktifkan di tahap ini.

---

## 1. Mekanisme Keselamatan, Backup & Recovery Pra-Migrasi

Implementasi ada di `lib/database/db_helper.dart`:

1. **`_onConfigure` (dijalankan sebelum migrasi dan setiap koneksi dibuka):**
   - `PRAGMA foreign_keys = ON`
   - `PRAGMA busy_timeout = 5000` (via `db.rawQuery` agar kompatibel penuh dengan Android `sqflite`)
   - `PRAGMA journal_mode = WAL` (untuk database file non-in-memory via `db.rawQuery`, dibungkus `try/catch` bila runtime virtual FS tidak mendukung WAL).
2. **`_prepareAndVerifyPreMigrationBackup`:**
   - Berjalan sebelum `openDatabase(..., version: 5)` pada `_initDB` dan `openTestDatabase(..., deleteIfExists: false)` jika file database sudah ada dan `PRAGMA user_version < 5`.
   - Mengeksekusi `PRAGMA wal_checkpoint(TRUNCATE)` agar seluruh jurnal WAL tergabung sebelum file disalin.
   - Menyalin database ke `kasirtoko_pre_v5_backup.db` (atau `<nama>_pre_v5_backup.db` saat pengujian).
   - Membuka file backup secara *read-only* (`openReadOnlyDatabase`) dan memverifikasi **`PRAGMA integrity_check == 'ok'`**; migrasi dibatalkan dengan `StateError` bila verifikasi backup gagal.
3. **Rollback Otomatis Jika Migrasi Gagal (`_restoreFromBackupFile`):**
   - Jika `_onUpgrade` melempar exception, koneksi ditutup, file `-wal`/`-shm` dibersihkan, dan file database utama dipulihkan utuh dari backup pra-v5 yang sudah terverifikasi.
4. **Kompatibilitas Data Lama (Foreign Key Non-Retroaktif):**
   - Tabel historis (`transactions`, `audit_logs`, `customer_debts`) tidak ditambahkan klausa `FOREIGN KEY` retroaktif agar baris lama dengan referensi pelanggan yang sudah dihapus atau `user_id = 0` tetap sah saat `PRAGMA foreign_keys = ON` aktif.
   - Relasi `FOREIGN KEY` ketat diterapkan pada tabel baru v5 (`cash_register_assignments`, `paired_terminals`, `terminal_sessions`, `print_jobs`, `transaction_voids`).

---

## 2. Perubahan Kolom Non-Destruktif (`if (oldVersion < 5)`)

Seluruh penambahan kolom dilakukan secara idempoten dengan `_addColumnIfMissing` serta guard pemeriksaan tabel inti (`transactions` dan `shifts`):

| Tabel | Kolom Baru v5 | Tipe & Default | Backfill Data Lama |
|---|---|---|---|
| `users` | `pin_salt` | `TEXT NOT NULL DEFAULT ''` | Dipertahankan kosong sampai akun login (migrasi transparan v1 -> v2 menghasilkan salt terpisah). |
| `users` | `hash_version` | `TEXT NOT NULL DEFAULT 'legacy_v1'` | Diisi `'v2_pbkdf2_sha256'` bila hash berawalan `$pbkdf2-sha256$`, selain itu `'legacy_v1'`. |
| `users` | `pin_lookup_hash` | `TEXT NOT NULL DEFAULT ''` | Diisi HMAC-SHA256 keyed lookup digest saat akun v2 dibuat atau dimigrasikan saat login. |
| `users` | `failed_pin_count` | `INTEGER NOT NULL DEFAULT 0` | Default `0`. |
| `users` | `pin_locked_until` | `TEXT` | `NULL`. |
| `transactions` | `terminal_id` | `TEXT NOT NULL DEFAULT 'ADMIN'` | Backfill `'ADMIN'` bila null/kosong. |
| `transactions` | `cash_register_id` | `INTEGER NOT NULL DEFAULT 1` | Backfill `1` (`REG-MAIN`) bila null/`<= 0`. |
| `transactions` | `idempotency_key` | `TEXT` | Dibiarkan `NULL` untuk transaksi historis; unik jika terisi (partial index). |
| `shifts` | `terminal_id` | `TEXT NOT NULL DEFAULT 'ADMIN'` | Backfill `'ADMIN'` bila null/kosong. |
| `shifts` | `cash_register_id` | `INTEGER NOT NULL DEFAULT 1` | Backfill `1` bila null/`<= 0`. |
| `shifts` | `drawer_mode` | `TEXT NOT NULL DEFAULT 'SHARED_DRAWER'` | Backfill `'SHARED_DRAWER'` bila null/kosong. |
| `cash_flows` | `terminal_id` | `TEXT NOT NULL DEFAULT 'ADMIN'` | Backfill dari `shifts.terminal_id` jika `shift_id` ada, fallback `'ADMIN'`. |
| `cash_flows` | `cash_register_id` | `INTEGER NOT NULL DEFAULT 1` | Backfill dari `shifts.cash_register_id` jika `shift_id` ada, fallback `1`. |
| `return_settlements` | `settlement_shift_id` | `INTEGER` | Backfill `COALESCE(settlement_shift_id, shift_id)`. |
| `return_settlements` | `settlement_cash_register_id` | `INTEGER` | Backfill dari `shifts.cash_register_id` bila `shift_id` terisi. |
| `audit_logs` | `user_role`, `module`, `object_id`, `before_value`, `after_value` | `TEXT NOT NULL DEFAULT ''` | Memastikan skema v1 parsial tetap dapat menerima log keamanan v5 tanpa kegagalan kolom hilang. |

**Sanitasi Shift Terbuka Duplikat Pra-v5 (`_normalizePreV5OpenShifts`):**
- Sebelum membuat partial unique index `idx_shifts_one_open_per_register`, migrasi memeriksa apakah terdapat >1 shift `'open'` pada `cash_register_id = 1`. Bila ada anomali pra-v5, shift terbuka yang lebih lama ditutup otomatis dengan catatan migrasi + audit log `tutup_shift`, sedangkan shift terbuka terbaru dipertahankan.

---

## 3. Tabel Baru & Indeks Schema v5

1. **`cash_registers`** — Daftar fisik/logis laci kas. Di-seed default row `id = 1`, `register_code = 'REG-MAIN'`, `name = 'Laci Kasir Utama (Admin)'`, `is_shared = 1`.
2. **`cash_register_assignments`** — Aturan penugasan deterministik (`cash_register_id`, `terminal_id`, `cashier_id`, `priority`, `is_active`, `assigned_by`, `created_at`).
3. **`paired_terminals`** — Struktur registri terminal kasir yang dipairing (`terminal_id`, `device_secret_hash`, `device_token_hash`, `assigned_register_id`, `allow_open_cash_drawer`, `is_revoked`) — disiapkan untuk Tahap 2.
4. **`terminal_sessions`** — Struktur sesi kasir pada terminal dengan `expires_at` dan `revoked_at` — disiapkan untuk Tahap 2.
5. **`print_jobs`** — Antrean cetak idempoten (`job_uuid UNIQUE`, `open_drawer_requested`, `drawer_opened`, `status`, `attempts`) — disiapkan untuk Tahap 2.
6. **`transaction_voids`** — Catatan peristiwa pembatalan/reversal transaksi yang immutable (`original_transaction_id`, `original_invoice_number`, `original_shift_id`, `original_cash_register_id`, `void_type`, `refund_method`, `refund_amount`, `credit_restored`, `voided_at`, `voided_by`, `voided_by_name`, `void_reason`, `settlement_shift_id`, `settlement_cash_register_id`, `settlement_terminal_id`, `cash_flow_id`).
7. **`store_settings`** — Seed default `'drawer_mode': 'SHARED_DRAWER'` menggunakan `ConflictAlgorithm.ignore`.

**Indeks Unik & Lookup v5 (`_ensureV5Indexes`):**
- `idx_transactions_idempotency` (`UNIQUE` partial on `transactions (idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key != ''`)
- `idx_shifts_one_open_per_register` (`UNIQUE` partial on `shifts (cash_register_id) WHERE status = 'open'`)
- `idx_shifts_one_open_per_cashier_indiv` (`UNIQUE` partial on `shifts (cashier_id) WHERE status = 'open' AND drawer_mode = 'INDIVIDUAL_DRAWER'`)
- `idx_cash_register_assignments_lookup`
- `idx_users_pin_lookup`
- `idx_transaction_voids_orig_trx`

---

## 4. Hasil Verifikasi Migrasi Database

- `test/phase1_db_v5_migration_test.dart` (**3/3 skenario lulus** pada `sqflite_common_ffi`):
  - Upgrade v4 -> v5 lengkap dengan data transaksi historis, pelanggan terhapus, retur, dan `return_settlements`: backup terverifikasi `PRAGMA integrity_check == ok`, WAL aktif, `foreign_keys = 1`, `busy_timeout >= 5000`, partial unique idempotency index tervalidasi.
  - Upgrade database pra-v5 yang memiliki >1 shift terbuka duplikat: disanitasi otomatis tanpa kegagalan pembuatan unique index.
  - Simulasi kegagalan migrasi pada database korup/asing: backup terverifikasi dan database dipulihkan kembali ke versi pra-migrasi tanpa kehilangan data.
- Regresi migrasi historis lama di `test/production_qa_scenarios_test.dart` (Scenario 21 v1 -> v5) dan `test/return_system_forensic_qa_test.dart` (Scenario 18 v3 -> v5): **lulus**.
