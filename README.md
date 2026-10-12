# Absensi Karyawan

Aplikasi absensi karyawan berbasis GPS untuk **Android, iOS, dan Web** (Flutter), dengan backend **Supabase**, ditambah **REST API untuk Agent AI**.

## Fitur

| Modul | Fitur |
|---|---|
| Absensi GPS | Absen masuk/pulang dengan validasi radius lokasi (geofence), deteksi lokasi palsu (fake GPS), batas akurasi GPS, peta posisi |
| Lokasi absensi | Admin menentukan titik GPS lewat peta atau lokasi saat ini, mengatur radius, dan menugaskan lokasi per karyawan |
| Jam kerja | Jadwal/shift (termasuk shift malam), hari kerja, toleransi terlambat, minimal lembur |
| Keterlambatan | Dihitung otomatis dalam menit |
| Ganti jam | Keterlambatan ditutup dengan kelebihan jam pulang. Mode **harian** atau **akumulasi bulanan** |
| Izin, sakit, cuti | Pengajuan dan persetujuan admin; cuti dicek terhadap kuota tahunan |
| Lembur | Pengajuan berdasarkan kelebihan jam aktual dan persetujuan admin |
| Rekap | Rekap bulanan: hadir, alpa, izin, sakit, cuti, terlambat, ganti jam, sisa ganti jam, lembur, sisa cuti |
| Agent API | REST API + OpenAPI untuk n8n, Dify, Flowise, Custom GPT, LangChain, dll. ([docs/AGENT_API.md](docs/AGENT_API.md)) |

## Aturan perhitungan

1. **Terlambat**: dihitung jika jam masuk melewati `jam masuk + toleransi`. Jika lewat toleransi, keterlambatan dihitung **penuh sejak jam masuk**.
   - Contoh: jadwal 08:00, toleransi 10 menit. Masuk 08:08 berarti tidak terlambat. Masuk 08:25 berarti terlambat 25 menit.
2. **Ganti jam** (jika aktif di jadwal): kelebihan jam setelah jam pulang dipakai **lebih dulu** untuk menutup keterlambatan.
   - Contoh: terlambat 30 menit, pulang 17:45 (jadwal 17:00). Hasilnya: diganti 30 menit, sisa 0, kelebihan 15 menit.
   - Contoh: terlambat 60 menit, pulang 17:20. Hasilnya: diganti 20 menit, **sisa ganti jam 40 menit**.
3. **Lembur** = kelebihan jam **setelah** dipotong ganti jam. Lembur hanya diakui jika ≥ minimal lembur dan pengajuannya disetujui admin.
4. **Masuk di hari libur**: seluruh jam kerja dihitung sebagai kelebihan jam (calon lembur).
5. **Mode ganti jam bulanan** (Pengaturan): sisa keterlambatan boleh ditutup dengan kelebihan jam di hari lain pada bulan yang sama, selama kelebihan jam itu tidak diajukan sebagai lembur.
6. **Alpa** = hari kerja yang sudah lewat tanpa absensi dan tanpa izin/sakit/cuti yang disetujui.

Semua perhitungan dilakukan di **database** (fungsi `check_in`, `check_out`, `monthly_recap`), sehingga tidak bisa dimanipulasi dari aplikasi.

## Struktur proyek

```
lib/
  core/        logika murni: perhitungan absensi, rumus jarak GPS, format
  models/      model data
  services/    akses Supabase (api.dart) & GPS (location_service.dart)
  screens/     auth, karyawan (beranda, riwayat, pengajuan, rekap), admin
  widgets/     komponen bersama & peta
supabase/
  migrations/  skema database, RLS, fungsi perhitungan
  functions/agent-api/  REST API untuk Agent AI
docs/
  AGENT_API.md   panduan API untuk Agent AI / n8n
  openapi.json   spesifikasi OpenAPI
test/          unit test perhitungan
```

---

## Langkah setup

### Langkah 1: Buat project Supabase

1. Buka https://supabase.com, lalu buat project baru (region **Singapore** paling dekat untuk Indonesia).
2. Buka **SQL Editor**, klik **New query**.
3. Salin seluruh isi `supabase/migrations/20261012000000_absensi_schema.sql`, tempel, lalu klik **Run**.
4. Buka **Authentication > Sign In / Providers > Email**:
   - Untuk uji coba, matikan **Confirm email** agar karyawan bisa langsung login setelah daftar.
5. Buka **Project Settings > API Keys** dan catat:
   - **Project URL** (mis. `https://abcd.supabase.co`)
   - **Publishable key** (atau *anon key*), dipakai aplikasi.

### Langkah 2: Jalankan aplikasi

Prasyarat: [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.35 atau lebih baru.

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://abcd.supabase.co \
  --dart-define=SUPABASE_KEY=publishable-key-anda
```

### Langkah 3: Akun admin pertama

1. Buka aplikasi, pilih **Daftar**, lalu buat akun.
2. **Akun pertama otomatis menjadi Admin** dan langsung aktif.
3. Akun berikutnya berstatus **Karyawan** dan **menunggu aktivasi** admin.

### Langkah 4: Konfigurasi oleh admin (urut)

1. **Admin > Pengaturan**: nama perusahaan, zona waktu (WIB/WITA/WIT), mode ganti jam, batas akurasi GPS.
2. **Admin > Lokasi Absensi > +**: ketuk peta atau tekan *Gunakan lokasi saya saat ini*, lalu atur radius (mis. 100 m).
3. **Admin > Jadwal Kerja > +**: jam masuk/pulang, hari kerja, toleransi, minimal lembur, ganti jam.
4. **Admin > Karyawan**: pilih karyawan, aktifkan, pilih jadwal, (opsional) pilih lokasi yang diizinkan, lalu isi kuota cuti.
   - Admin juga perlu diberi jadwal jika ingin ikut absen.

### Langkah 5: Penggunaan karyawan

1. **Beranda**: cek status lokasi (hijau = di dalam area), lalu tekan **Absen Masuk** / **Absen Pulang**.
2. **Pengajuan > Ajukan**: izin, sakit, cuti, atau lembur.
3. **Rekap**: lihat ringkasan bulanan, termasuk sisa ganti jam dan sisa cuti.

---

## Versi Web (front end di browser)

Aplikasi yang sama bisa dibuka lewat browser.

### Langkah 1: Build

```bash
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL=https://abcd.supabase.co \
  --dart-define=SUPABASE_KEY=publishable-key-anda
```

Hasil build ada di folder `build/web/`. Opsi `--no-web-resources-cdn` membuat semua file mesin render ikut tersimpan di hosting Anda (tidak bergantung CDN Google).

### Langkah 2: Hosting (pilih salah satu)

- **Hostinger / cPanel**: upload **isi** folder `build/web/` ke `public_html` (atau subfolder). Jika di subfolder, build dengan `--base-href /nama-subfolder/`.
- **Netlify / Vercel / Cloudflare Pages**: drag & drop folder `build/web/`.
- **Firebase Hosting**: `firebase init hosting` (public dir: `build/web`), lalu `firebase deploy`.

### Catatan web

- GPS di browser **wajib HTTPS** (kecuali `localhost`). Semua hosting di atas sudah menyediakan HTTPS.
- Browser akan meminta izin lokasi. Pengguna harus memilih **Izinkan**.
- Deteksi fake GPS hanya tersedia di Android. Di web, akurasi GPS laptop/PC biasanya rendah. Naikkan *batas akurasi GPS* bila admin/karyawan absen dari laptop.
- Uji lokal: `flutter run -d chrome --dart-define=...`.

---

## Build Android / iOS

```bash
# APK untuk dibagikan langsung
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...

# App Bundle untuk Google Play
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...

# iOS (butuh macOS + Xcode)
flutter build ipa --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
```

Izin lokasi sudah dikonfigurasi di `AndroidManifest.xml` dan `Info.plist`.

---

## Agent API (untuk Agent AI)

Lihat panduan lengkap: **[docs/AGENT_API.md](docs/AGENT_API.md)**.

Ringkasnya:

```bash
supabase functions deploy agent-api --no-verify-jwt
supabase secrets set AGENT_API_KEY=$(openssl rand -hex 32)
```

---

## Pengujian

```bash
flutter analyze
flutter test        # unit test perhitungan terlambat, ganti jam, lembur, jarak GPS
```

## Keamanan

- Semua tabel memakai **Row Level Security**. Karyawan hanya bisa melihat datanya sendiri.
- Absensi hanya bisa dibuat lewat fungsi `check_in`/`check_out`, yang memvalidasi radius, akurasi, dan fake GPS di server.
- Persetujuan hanya bisa dilakukan admin (atau Agent API).
- **Jangan** memasukkan `service_role` key ke aplikasi. Key itu hanya dipakai di Edge Function.
