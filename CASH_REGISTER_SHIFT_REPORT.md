# Laporan Laci Kas, Assignment, Mode Shift & Void Shift Tertutup (Tahap 1 — `kasirtoko`)

**Tanggal:** 2026-11-26  
**Branch:** `feat/phase1-multi-device-foundation`  
**Cakupan:** Pemisahan identitas `cashier_id`, `terminal_id`, `shift_id`, dan `cash_register_id`, implementasi `cash_register_assignments`, dukungan `SHARED_DRAWER` & `INDIVIDUAL_DRAWER`, idempotensi transaksi, perbaikan `getShiftStats`, serta void/reversal shift tertutup tanpa modifikasi retroaktif.

---

## 1. Pemisahan Entitas & Mode Operasional Laci Kas

Keputusan desain resmi memisahkan seluruh entitas pada model dan tabel v5:
- **Models baru/diperbarui:**
  - `lib/models/cash_register.dart`: `DrawerMode` (`SHARED_DRAWER` / `INDIVIDUAL_DRAWER`), `CashRegisterModel`, dan `CashRegisterAssignmentModel` (dengan `specificityRank`).
  - `lib/models/shift.dart`: menambah `terminalId`, `cashRegisterId`, `drawerMode`.
  - `lib/models/transaction.dart`: menambah `terminalId`, `cashRegisterId`, `idempotencyKey`.
  - `lib/models/cash_flow.dart`: menambah `terminalId`, `cashRegisterId`.
  - `lib/models/transaction_void.dart`: `VoidTypes` (`pre_payment_void` vs `post_payment_reversal`) dan `TransactionVoidModel`.
  - `lib/models/return_settlement.dart`: menambah `settlementShiftId`, `settlementCashRegisterId`.
  - `lib/models/user.dart`: menambah permission granular `AppPermissions.openCashDrawer`.

### Perbandingan Perilaku Mode Operasional
1. **`SHARED_DRAWER` (Default komparatif v1–v4):**
   - Beberapa kasir dan terminal (`ADMIN`, `STAFF-01`, dst.) dapat bertransaksi dalam satu shift toko aktif pada laci utama (`REG-MAIN`, `id = 1`).
   - Constraint indeks `idx_shifts_one_open_per_register` + pengecekan di `DatabaseHelper.openShift` memastikan hanya ada 1 shift terbuka per `cash_register_id`.
   - Setiap baris `transactions` menyimpan `cashier_id`, `cashier_name`, `terminal_id`, `shift_id`, dan `cash_register_id` masing-masing tanpa tertimpa.
   - Penutupan shift mengunci snapshot kas tanpa menghilangkan atau mengubah atribut kasir pada transaksi historis.
2. **`INDIVIDUAL_DRAWER`:**
   - Kasir wajib memiliki penugasan sah (`cash_register_assignments`) ke laci kas miliknya.
   - Beberapa shift berbeda dapat terbuka secara paralel selama `cash_register_id` berbeda (`idx_shifts_one_open_per_register`) dan tidak ada dua shift terbuka untuk kasir yang sama (`idx_shifts_one_open_per_cashier_indiv`).
   - Pada `insertTransaction`, transaksi pada shift `INDIVIDUAL_DRAWER` menolak kasir berbeda yang mencoba memakai shift milik kasir lain maupun laci kas yang tidak ditugaskan.
   - `closeShift(shiftId, ...)` hanya menutup `WHERE id = ? AND status = 'open'` sehingga tidak memengaruhi shift paralel kasir lain.
   - Switching `INDIVIDUAL_DRAWER -> SHARED_DRAWER` melalui `setDrawerMode` dicegah apabila masih terdapat >1 shift individu terbuka atau shift terbuka di luar `REG-MAIN`.

---

## 2. Resolusi Deterministik `cash_register_assignments`

Implementasi di `DatabaseHelper.resolveAuthorizedCashRegisterTxn` (`lib/database/db_helper.dart`):

1. **Hierarki Spesifisitas (`specificityRank`):**
   - Rank `3`: Kombinasi tepat **`terminal_id` + `cashier_id`**
   - Rank `2`: **`cashier_id`** saja (`terminal_id IS NULL`)
   - Rank `1`: **`terminal_id`** saja (`cashier_id IS NULL`)
2. **Resolusi Konflik:**
   - Kandidat aktif disaring lalu diurutkan berdasarkan `(specificityRank DESC, priority DESC, id ASC)`.
   - Hanya aturan pada `specificityRank` tertinggi yang dipertimbangkan; nilai `priority` memutus konflik di level spesifisitas yang sama.
   - Bila masih ada >1 `cash_register_id` berbeda dengan `specificityRank` dan `priority` identik di puncak peringkat, resolver menolak dengan `StateError` alih-alih menebak secara acak.
   - Bila `requestedRegisterId` tidak cocok dengan register hasil resolusi atau laci kas berstatus `is_active = 0`, transaksi dan pembukaan shift ditolak deterministik.
   - Pada mode `INDIVIDUAL_DRAWER`, terminal/kasir tanpa rule assignment yang cocok juga ditolak (`StateError`).

---

## 3. Idempotensi Transaksi & Isolasi `getShiftStats`

- **Idempotensi Checkout (`insertTransaction`):**
  - Bila `trx.idempotencyKey` diisi (e.g. dari retry akibat putus jaringan atau double-tap), `insertTransaction` memeriksa `transactions WHERE idempotency_key = ?` di dalam transaksi DB atomik dan mengembalikan `id` transaksi eksisting tanpa memotong stok, memotong saldo kredit, membuat piutang, atau menambah total shift untuk kedua kalinya.
  - Diperkuat pada level SQLite dengan partial unique index `idx_transactions_idempotency`.
- **Perbaikan Bug Statistik Lintas Shift (`getShiftStats`):**
  - Sebelumnya `getShiftStats` memakai fallback `OR (shift_id IS NULL AND date >= ? AND date <= ?)` untuk semua shift. Pada mode multi-shift paralel, hal itu berisiko membuat shift individu menyerap transaksi yatim (`shift_id IS NULL`).
  - Kini fallback orphan hanya diizinkan pada shift `SHARED_DRAWER` di `REG-MAIN` (`id = 1`) dengan filter ketat `(terminal_id = 'ADMIN' AND cash_register_id = 1)`. Untuk shift `INDIVIDUAL_DRAWER` atau register sekunder, `getShiftStats` hanya menghitung `status != 'voided' AND shift_id = ?`.

---

## 4. Void Transaksi Shift Tertutup (`voidTransaction` & `transaction_voids`)

Implementasi di `DatabaseHelper.voidTransaction` (`lib/database/db_helper.dart`):

1. **Shift Tertutup Bersifat Immutable:**
   - Jika `origShift.status == 'closed'` (atau void dilakukan lewat shift settlement berbeda), baris `shifts` milik shift asal **tidak pernah diubah** (`total_sales_*`, `expectedCash`, `actual_cash`, `difference` tetap utuh).
   - `transactions.shift_id` dan `transactions.cash_register_id` tetap menunjuk ke shift & register asal.
2. **Pencatatan Peristiwa Baru (`transaction_voids`):**
   - Setiap pembatalan menyimpan baris peristiwa baru dengan kolom wajib: `original_transaction_id`, `original_invoice_number`, `original_shift_id`, `original_cash_register_id`, `void_type`, `refund_method`, `refund_amount`, `credit_restored`, `voided_at`, `voided_by`, `voided_by_name`, `void_reason`, `settlement_shift_id`, `settlement_cash_register_id`, `settlement_terminal_id`, dan `cash_flow_id`.
3. **Pemisahan `pre_payment_void` vs `post_payment_reversal`:**
   - `VoidTypes.prePaymentVoid`: Pembatalan sebelum pembayaran selesai (`refund_method = 'none'`, `refund_amount = 0.0`), melepas stok tanpa arus kas refund laci.
   - `VoidTypes.postPaymentReversal`: Reversal/refund setelah pembayaran selesai.
4. **Aturan Ketat Refund Tunai Shift Tertutup:**
   - Untuk `post_payment_reversal` dengan `payment_method == 'tunai'` pada nota dari shift tertutup: sistem **mewajibkan** adanya shift aktif berstatus `'open'` sebagai shift settlement dan mengecek kecukupan kas laci (`_ensureSufficientShiftCash`).
   - Jika tidak ada shift aktif yang sah (atau shift settlement sudah ditutup), `voidTransaction` melempar `StateError` dan **menahan** void/refund secara atomik tanpa mengubah status nota maupun stok.
   - Jika shift settlement aktif tersedia, refund tunai dicatat sebagai `cash_flows` keluar (`source_type = 'void_reversal'`) dan menambah `total_return_cash` pada **shift settlement aktif** tersebut (menurunkan `expectedCash` shift aktif, bukan shift lama yang sudah ditutup).
   - Untuk kompatibilitas penuh saat void dilakukan pada shift yang **sama-sama masih terbuka**, perilaku penyesuaian live shift berjalan tetap dipertahankan sambil tetap mencatat baris peristiwa di `transaction_voids`.

---

## 5. UI & Provider Terkait (`kasirtoko`)

- `CashFlowProvider` & `ShiftScreen`: mendukung `openShifts` paralel, menampilkan `Laci Kas #...`, `Terminal`, dan `Mode` pada shift aktif.
- `SettingsProvider` & `SettingsScreen`: menyediakan pemilih mode operasional laci kas (`SHARED_DRAWER` / `INDIVIDUAL_DRAWER`) serta dialog pengelolaan `cash_registers` & `cash_register_assignments`.
- `PosProvider` & `PaymentDialog`: menjaga kelengkapan `creditUsed`, `terminalId`, `cashRegisterId`, dan `idempotencyKey` pada `TransactionModel` hasil checkout.
- `DailyReportScreen`: meneruskan `voidedBy`, `voidedByName`, dan `reason` ke `voidTransaction` serta menampilkan pesan error bila refund tunai shift tertutup tertahan karena belum ada shift aktif.

---

## 6. Hasil Verifikasi Suite Uji Shift & Assignment

`test/phase1_cash_register_shift_void_test.dart` (**3/3 skenario lulus** pada run terbaru):
- `SHARED_DRAWER`: multi-kasir & multi-terminal dalam 1 shift toko, pemblokiran shift kedua di register sama, retensi identitas transaksi setelah `closeShift`, serta uji idempotensi `idempotency_key` tanpa pengurangan stok ganda.
- `INDIVIDUAL_DRAWER` & `cash_register_assignments`: prioritas `terminal+cashier > cashier > terminal`, pemutusan konflik prioritas + penolakan konflik ambigu dengan spesifisitas & prioritas identik, penolakan register tidak sah & kasir tanpa assignment, 2 shift paralel terbuka, penutupan satu shift tidak memengaruhi shift lain, serta isolasi penuh `getShiftStats` dari transaksi `shift_id IS NULL`.
- Void shift tertutup: penahanan refund tunai saat tidak ada shift aktif terbuka, pemisahan `pre_payment_void` vs `post_payment_reversal`, keutuhan 100% snapshot shift tertutup, pencatatan settlement kas pada shift terbuka baru, dan verifikasi lengkap tabel `transaction_voids`.
