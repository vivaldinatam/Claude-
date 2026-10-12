# Agent API: REST API Absensi untuk Agent AI

REST API dengan **akses penuh admin** agar Agent AI bisa membaca dan mengelola data absensi:
rekap, kehadiran hari ini, karyawan, lokasi, jadwal, persetujuan izin/sakit/cuti/lembur, dan pengaturan.

- **Base URL**: `https://<PROJECT-REF>.supabase.co/functions/v1/agent-api`
- **Autentikasi**: header `x-api-key: <AGENT_API_KEY>` (atau `Authorization: Bearer <AGENT_API_KEY>`)
- **Dokumentasi mesin (OpenAPI 3.1)**: `GET <BASE_URL>/openapi.json` (tanpa auth), salinannya ada di [`openapi.json`](openapi.json)
- **Format respons**: sukses `{"data": ...}`, gagal `{"error": "pesan"}`
- Durasi dalam **menit**, tanggal `YYYY-MM-DD`, waktu ISO 8601 (UTC)

> **Penting:** `AGENT_API_KEY` setara dengan kata sandi admin. Simpan sebagai credential/secret, jangan di prompt atau kode publik.

---

## Langkah 1: Deploy API (sekali saja)

Prasyarat: skema database sudah dijalankan (lihat README, Langkah 1).

1. Install Supabase CLI: https://supabase.com/docs/guides/cli
2. Login dan hubungkan project:
   ```bash
   supabase login
   supabase link --project-ref <PROJECT-REF>
   ```
3. Buat API key acak lalu simpan sebagai secret:
   ```bash
   openssl rand -hex 32          # salin hasilnya, ini AGENT_API_KEY Anda
   supabase secrets set AGENT_API_KEY=<hasil-di-atas>
   ```
4. Deploy fungsi:
   ```bash
   supabase functions deploy agent-api --no-verify-jwt
   ```
5. Uji:
   ```bash
   curl https://<PROJECT-REF>.supabase.co/functions/v1/agent-api/health
   curl -H "x-api-key: <AGENT_API_KEY>" \
        https://<PROJECT-REF>.supabase.co/functions/v1/agent-api/summary/today
   ```

**Tanpa CLI:** buka Supabase Dashboard > **Edge Functions** > **Deploy a new function** > **Via Editor**, beri nama `agent-api`, lalu tempel isi `supabase/functions/agent-api/index.ts`. Buat file kedua `openapi.ts` dan tempel isinya. Matikan **Verify JWT**. Lalu isi `AGENT_API_KEY` di **Edge Functions > Secrets**.

---

## Langkah 2: Hubungkan ke Agent AI

### A. n8n (AI Agent + HTTP Request Tool)

1. **Buat credential** (sekali):
   - *Credentials > New > Header Auth*
   - Name: `x-api-key`, Value: `<AGENT_API_KEY>`
2. Di workflow, tambahkan node **AI Agent** (dengan Chat Model pilihan Anda).
3. Pada konektor **Tool** di AI Agent, tambahkan **HTTP Request Tool** untuk setiap kemampuan. Contoh tool yang disarankan:

| Nama tool | Method | URL | Deskripsi tool (untuk agent) |
|---|---|---|---|
| `kehadiran_hari_ini` | GET | `{BASE}/summary/today` | Status kehadiran semua karyawan hari ini (hadir, terlambat, belum absen, izin, sakit, cuti) |
| `rekap_bulanan` | GET | `{BASE}/recap` + query `month` (YYYY-MM), `employee_id` opsional | Rekap bulanan: terlambat, ganti jam, sisa ganti jam, lembur, izin, sakit, cuti, alpa |
| `cari_karyawan` | GET | `{BASE}/employees` + query `search` | Cari karyawan berdasarkan nama/kode/email untuk mendapatkan `id` |
| `data_absensi` | GET | `{BASE}/attendances` + query `employee_id`, `from`, `to`, `late_only` | Detail absensi per hari |
| `pengajuan_pending` | GET | `{BASE}/leave-requests?status=pending` | Daftar izin/sakit/cuti yang menunggu persetujuan |
| `proses_pengajuan` | POST | `{BASE}/leave-requests/{id}/review`, body `{"approve": true, "note": "..."}` | Setujui/tolak izin, sakit, cuti |
| `lembur_pending` | GET | `{BASE}/overtime-requests?status=pending` | Daftar lembur yang menunggu persetujuan |
| `proses_lembur` | POST | `{BASE}/overtime-requests/{id}/review`, body `{"approve": true, "approved_minutes": 60}` | Setujui/tolak lembur |

   Pengaturan di setiap HTTP Request Tool:
   - **Authentication**: *Generic Credential Type > Header Auth*, pilih credential dari langkah 1.
   - Untuk parameter yang diisi agent (mis. `month`, `search`, `id`), gunakan **"Let the model define this parameter"** (`$fromAI(...)`).
   - Tulis **Description** yang jelas, karena agent memilih tool berdasarkan deskripsi.
4. Contoh **System Message** untuk AI Agent:
   ```
   Kamu adalah asisten HR untuk absensi karyawan. Gunakan tools yang tersedia untuk menjawab.
   - Untuk pertanyaan tentang seseorang, cari dulu id-nya dengan cari_karyawan.
   - Durasi dari API dalam menit; tampilkan sebagai jam & menit.
   - Sebelum menyetujui/menolak pengajuan, tampilkan ringkasannya dan minta konfirmasi pengguna.
   ```

### B. Platform yang mendukung OpenAPI (paling mudah)

Cukup masukkan URL `https://<PROJECT-REF>.supabase.co/functions/v1/agent-api/openapi.json` dan API key:

| Platform | Cara |
|---|---|
| **ChatGPT Custom GPT** | *Configure > Actions > Import from URL*. Authentication: *API Key*, *Custom header* `x-api-key` |
| **Dify** | *Tools > Custom > Create Custom Tool*, impor dari URL, auth header `x-api-key` |
| **Flowise / Langflow** | Node *OpenAPI Toolkit* / *OpenAPI Chain*, isi URL spec + header |
| **LangChain (Python)** | `OpenAPIToolkit` / `RequestsToolkit` dengan header `x-api-key` |
| **Postman** | *Import > Link*, tempel URL `openapi.json` |

### C. Claude / OpenAI tool calling (kode sendiri)

Setiap `operationId` di `openapi.json` (mis. `getTodaySummary`, `getMonthlyRecap`, `reviewLeaveRequest`) bisa langsung dijadikan definisi tool. Eksekusi tool cukup berupa HTTP request ke endpoint terkait dengan header `x-api-key`.

---

## Daftar endpoint

| Method | Path | Fungsi |
|---|---|---|
| GET | `/health` | Cek status (tanpa auth) |
| GET | `/openapi.json` | Spesifikasi OpenAPI (tanpa auth) |
| GET | `/summary/today` | Ringkasan kehadiran hari ini |
| GET | `/recap?month=YYYY-MM&employee_id=` | Rekap bulanan |
| GET | `/employees?search=&active=&role=` | Daftar karyawan |
| POST | `/employees` | Buat akun karyawan (`email`, `password`, `full_name`, ...) |
| GET / PATCH / DELETE | `/employees/{id}` | Detail / ubah / hapus karyawan |
| PUT | `/employees/{id}/locations` | Atur lokasi absensi karyawan (`location_ids`) |
| GET / POST | `/locations` | Daftar / tambah lokasi |
| GET / PATCH / DELETE | `/locations/{id}` | Detail / ubah / hapus lokasi |
| GET / POST | `/schedules` | Daftar / tambah jadwal |
| GET / PATCH / DELETE | `/schedules/{id}` | Detail / ubah / hapus jadwal |
| GET | `/attendances?employee_id=&date=&from=&to=&status=&late_only=` | Data absensi |
| GET / PATCH / DELETE | `/attendances/{id}` | Detail / koreksi / hapus absensi |
| GET / POST | `/leave-requests` | Daftar / buat pengajuan izin/sakit/cuti |
| GET / DELETE | `/leave-requests/{id}` | Detail / hapus |
| POST | `/leave-requests/{id}/review` | Setujui/tolak (`approve`, `note`) |
| GET / POST | `/overtime-requests` | Daftar / buat pengajuan lembur |
| GET / DELETE | `/overtime-requests/{id}` | Detail / hapus |
| POST | `/overtime-requests/{id}/review` | Setujui/tolak (`approve`, `approved_minutes`, `note`) |
| GET / PATCH | `/settings` | Pengaturan perusahaan |

## Contoh request

```bash
BASE=https://<PROJECT-REF>.supabase.co/functions/v1/agent-api
KEY=<AGENT_API_KEY>

# Siapa yang terlambat / belum absen hari ini?
curl -H "x-api-key: $KEY" $BASE/summary/today

# Rekap Oktober 2026 semua karyawan
curl -H "x-api-key: $KEY" "$BASE/recap?month=2026-10"

# Absensi terlambat seorang karyawan dalam rentang tanggal
curl -H "x-api-key: $KEY" "$BASE/attendances?employee_id=<ID>&from=2026-10-01&to=2026-10-31&late_only=true"

# Setujui cuti
curl -X POST -H "x-api-key: $KEY" -H "Content-Type: application/json" \
     -d '{"approve": true, "note": "Disetujui via asisten AI"}' \
     $BASE/leave-requests/<ID>/review

# Tambah lokasi absensi
curl -X POST -H "x-api-key: $KEY" -H "Content-Type: application/json" \
     -d '{"name":"Gudang","latitude":-6.2,"longitude":106.8,"radius_m":150}' \
     $BASE/locations
```

## Contoh respons `/summary/today`

```json
{
  "data": {
    "date": "2026-10-12",
    "total_employees": 3,
    "counts": { "hadir": 1, "terlambat": 1, "belum_absen": 1 },
    "employees": [
      {
        "employee_id": "…",
        "full_name": "Budi",
        "status": "terlambat",
        "check_in_at": "2026-10-12T01:25:00+00:00",
        "check_out_at": null,
        "late_minutes": 25,
        "late_debt_minutes": 25,
        "overtime_minutes": 0
      }
    ]
  }
}
```

## Catatan keamanan

- API memakai `service_role` di server dan **melewati RLS**. Hanya bagikan `AGENT_API_KEY` ke sistem yang dipercaya.
- Ganti key kapan saja: `supabase secrets set AGENT_API_KEY=<baru>` (langsung berlaku).
- Disarankan agent meminta konfirmasi manusia sebelum aksi tulis (approve, hapus, ubah data).
- `PATCH /attendances/{id}` menyimpan nilai apa adanya (tidak dihitung ulang). Gunakan untuk koreksi manual.
