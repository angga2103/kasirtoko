# KasirToko Android - Aplikasi Kasir Offline Lengkap & Modern

**KasirToko** adalah aplikasi Point of Sale (POS) Android yang dirancang khusus dengan arsitektur **Full Offline-First**, kaya fitur, namun tetap intuitif dan mudah dipahami oleh pengguna awam maupun kasir pemula.

Aplikasi ini tidak memerlukan koneksi internet untuk beroperasi sehari-hari, bebas biaya langganan bulanan server, memiliki respon transaksi super cepat tanpa lag, serta dilengkapi sistem pencadangan database aman ke Google Drive dan WhatsApp.

---

## Fitur Utama

### 1. Point of Sale (Kasir & Transaksi)
*   **Scan Barcode Cepat:** Dukungan pemindaian melalui kamera HP/tablet maupun barcode scanner eksternal USB/Bluetooth.
*   **Multi Satuan Produk:** Mendukung penjualan bertingkat (misal: 1 Dus = 12 Pack = 120 Pcs) dengan konversi harga dan pemotongan stok otomatis.
*   **Harga Bertingkat (Grosir):** Harga otomatis berubah lebih murah jika pembeli membeli dalam jumlah kuantitas tertentu (misal: Beli $\ge$ 10 pcs dapat harga grosir).
*   **Produk Fisik vs Jasa:** Mendukung produk fisik (memotong stok inventori) dan produk jasa (seperti servis, ongkos kirim, jasa potong) tanpa stok.
*   **Tahan Pesanan (Hold / Pending Order):** Simpan keranjang belanja sementara jika pembeli lupa dompet atau menambah barang, lalu lanjutkan antrean berikutnya.
*   **Pecahan Cepat Uang (Quick Cash):** Tombol otomatis uang pas, pecahan Rp 10.000, 20.000, 50.000, 100.000, 200.000 untuk hitung kembalian instan.
*   **Support Printer Termal & Laci Kasir (Cash Drawer):** Format cetak struk ESC/POS untuk ukuran kertas 58mm dan 80mm serta pemicu sinyal RJ11 untuk membuka laci kasir otomatis.
*   **Struk Digital via WhatsApp:** Kirim struk belanja langsung ke WhatsApp pelanggan dalam bentuk teks rapi atau gambar.

### 2. QR Code Transaksi di Footer Struk
*   Setiap struk belanja otomatis mencetak **QR Code Unik** di bagian footer (`TRX|<No.Nota>|<Total>`).
*   Kasir cukup mengarahkan scanner ke QR Code tersebut untuk membuka detail riwayat transaksi atau memproses retur dalam 1 detik.

### 3. Logika Retur Produk Rapi (Sebagian atau Semua)
*   **Retur Parsial / Semua:** Pilih barang mana saja dan jumlah kuantitas yang ingin dikembalikan.
*   **Pemisahan Kondisi Barang:**
    *   *Kondisi Baik:* Stok barang otomatis dikembalikan ke rak aktif penjualan.
    *   *Kondisi Rusak / Cacat / Basi:* Barang dialihkan ke gudang retur afkir untuk klaim ke supplier.
*   **Pilihan Pengembalian Dana (Refund):** Tunai (otomatis memotong uang kas di laci), Potong Piutang/Kasbon, atau Tukar Barang.

### 4. Manajemen Shift & Arus Kas (Cash Flow)
*   **Buka Shift:** Catat modal kembalian awal di laci kasir.
*   **Pemasukan & Pengeluaran Operasional:** Catat pengeluaran kecil dari laci (beli plastik, galon, bayar iuran, modal tambahan).
*   **Tutup Shift (Blind Cash Count):** Kasir menghitung uang fisik tanpa melihat angka sistem terlebih dahulu, sehingga selisih kas (lebih/kurang/cocok) terdeteksi akurat.
*   **Laporan Shift WhatsApp:** 1-Klik kirim ringkasan penutupan shift ke WhatsApp Owner.

### 5. Buku Kasbon & Notifikasi Jatuh Tempo
*   Pencatatan kasbon belanja pelanggan lengkap dengan tanggal jatuh tempo.
*   Penanda status warna: **Aman**, **H-3 Mendekati Tempo**, dan **Lewat Jatuh Tempo (Overdue)**.
*   **1-Klik Kirim Tagihan WhatsApp:** Teks tagihan sopan dan profesional langsung terisi otomatis ke WhatsApp pelanggan.
*   **Cetak Surat Invoice Penagihan Resmi:** Cetak surat tagihan berformat PDF resmi ukuran A4.

### 6. Generator Barcode & QR Code (Cetak Label Stiker Thermal)
*   Buat barcode 1D (Code128 / EAN-13) maupun QR Code 2D untuk barang curah, makanan kemasan sendiri, atau produk jasa.
*   Kustomisasi label: Nama toko, nama produk, harga jual, dan barcode.
*   Cetak massal langsung ke printer thermal stiker (ukuran 40x30 mm, 50x30 mm, roll 58 mm).

### 7. Gudang: Stok Opname & Surat Jalan
*   **Stok Opname:** Bandingkan stok fisik dengan stok sistem, catat alasan selisih (rusak/hilang/salah hitung), dan sesuaikan stok dengan 1 klik.
*   **Pengingat Kadaluarsa (Expired Date):** Pemantauan batch produk dengan indikator: *Aman*, *Peringatan (H-30)*, *Kritis (H-7)*, dan *Kadaluarsa*.
*   **Surat Jalan (Delivery Order) & Surat Ambil Barang:** Formulir pembuatan dan cetak dokumen resmi A4 dengan data penerima, supir, no. polisi kendaraan, dan tanda tangan serah terima.

### 8. Absensi Selfie Liveness Detection Offline (Anti-AI & Anti-Pemalsuan)
*   **100% Offline Google ML Kit Face Mesh:** Memastikan objek di depan kamera adalah manusia hidup (mendeteksi senyuman, kedipan mata, atau rotasi kepala).
*   **Tantangan Acak Dinamis:** Menghasilkan kode angka acak 3 digit (Token) pada setiap sesi absensi untuk mencegah penggunaan foto lama dari galeri atau rekayasa AI / deepfake.
*   **Watermark Permanen Menyatu ke Pixel Foto:**
    *   Waktu & Tanggal Akurat (WIB).
    *   Nama Karyawan & Tipe Absen (Masuk / Pulang).
    *   Status Kehadiran (*Tepat Waktu* atau *Terlambat XX Menit*).
    *   **Kode Hash Verifikasi Unik:** Contoh: `#AUTH-8F2D-742`.
*   **1-Klik Kirim Bukti ke WhatsApp Owner.**
*   **Laporan Mingguan Kedisiplinan:** Rekap persentase kehadiran, jumlah keterlambatan, dan galeri foto verifikasi.

### 9. Keamanan & Log Audit Karyawan
*   **Hak Akses Multi-Level:** Owner, Supervisor/Manager, Kasir, dan Petugas Gudang (login cepat berbasis PIN).
*   **Log Audit Keamanan:** Mencatat seluruh tindakan sensitif karyawan (*void transaksi, ubah harga, buka laci manual, proses retur, ubah stok*).

### 10. Impor/Ekspor Excel & Pencadangan Data
*   Impor master produk massal dari file Excel (`.xlsx`).
*   Ekspor katalog produk dan laporan penjualan ke Excel.
*   Cadangkan (backup) seluruh database SQLite ke file lokal, Google Drive, atau bagikan langsung ke WhatsApp.

---

## Akun Demo & PIN Bawaan

| Level Akun | Nama | PIN Masuk | Hak Akses |
| :--- | :--- | :--- | :--- |
| **Owner** | Pemilik Toko | `123456` | Seluruh menu, laporan keuangan, log audit, backup database |
| **Supervisor** | Supervisor Toko | `3333` | Kasir, retur, stok, laporan, diskon & promo |
| **Kasir** | Kasir 1 | `1111` | Kasir (POS), buka/tutup shift, kas masuk/keluar, retur |
| **Gudang** | Petugas Gudang | `2222` | Stok opname, surat jalan, cetak barcode, cek kadaluarsa |

---

## Otomatisasi Build APK (GitHub Actions CI/CD)

Proyek ini telah dikonfigurasi dengan alur kerja GitHub Actions pada [`.github/workflows/build.yml`](.github/workflows/build.yml).

Setiap kali kode di-push ke branch `main`, GitHub Actions akan:
1. Menyiapkan environment Ubuntu & Java 17 Temurin.
2. Mengunduh Flutter SDK dan mengompilasi dependency.
3. Melakukan build release APK Android (`flutter build apk --release --no-tree-shake-icons`).
4. Mengunggah file `.apk` siap pakai ke tab **Artifacts** di repositori GitHub Anda.

---

## Menjalankan Proyek Secara Lokal

Pastikan Anda telah menginstal [Flutter SDK](https://flutter.dev) (minimal versi 3.24 / 3.47).

```bash
# 1. Clone repositori
git clone https://github.com/angga2103/kasirtoko.git
cd kasirtoko

# 2. Ambil seluruh dependencies
flutter pub get

# 3. Jalankan unit test
flutter test

# 4. Jalankan aplikasi di HP/Emulator Android
flutter run
```
