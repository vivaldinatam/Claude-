// Spesifikasi OpenAPI 3.1 untuk Agent API.
// Dipakai oleh: n8n (HTTP Request Tool), Custom GPT Actions, Dify, Flowise,
// LangChain OpenAPI toolkit, Claude tool use, Postman, dll.

const uuid = { type: "string", format: "uuid" };
const date = { type: "string", format: "date", example: "2026-10-12" };
const idParam = { name: "id", in: "path", required: true, schema: uuid };
const ok = (description: string) => ({
  "200": {
    description,
    content: { "application/json": { schema: { type: "object", properties: { data: {} } } } },
  },
  "400": { $ref: "#/components/responses/Error" },
  "401": { $ref: "#/components/responses/Error" },
  "404": { $ref: "#/components/responses/Error" },
});
const body = (schema: Record<string, unknown>) => ({
  required: true,
  content: { "application/json": { schema } },
});
const query = (name: string, description: string, schema: Record<string, unknown> = { type: "string" }) => ({
  name,
  in: "query",
  required: false,
  description,
  schema,
});

const employeeSchema = {
  type: "object",
  properties: {
    full_name: { type: "string" },
    employee_code: { type: "string", description: "NIK / kode karyawan" },
    phone: { type: "string" },
    position: { type: "string", description: "Jabatan" },
    role: { type: "string", enum: ["admin", "employee"] },
    schedule_id: { ...uuid, description: "ID jadwal kerja" },
    annual_leave_quota: { type: "integer", description: "Kuota cuti tahunan (hari)" },
    is_active: { type: "boolean" },
  },
};
const locationSchema = {
  type: "object",
  properties: {
    name: { type: "string" },
    address: { type: "string" },
    latitude: { type: "number" },
    longitude: { type: "number" },
    radius_m: { type: "integer", minimum: 10, maximum: 5000, description: "Radius absensi (meter)" },
    is_active: { type: "boolean" },
  },
};
const scheduleSchema = {
  type: "object",
  properties: {
    name: { type: "string" },
    start_time: { type: "string", example: "08:00", description: "Jam masuk HH:MM" },
    end_time: { type: "string", example: "17:00", description: "Jam pulang HH:MM" },
    late_tolerance_min: { type: "integer", description: "Toleransi terlambat (menit)" },
    work_days: {
      type: "array",
      items: { type: "integer", minimum: 1, maximum: 7 },
      description: "Hari kerja ISO: 1=Senin ... 7=Minggu",
      example: [1, 2, 3, 4, 5],
    },
    min_overtime_min: { type: "integer", description: "Minimal kelebihan jam agar dihitung lembur" },
    makeup_enabled: { type: "boolean", description: "Wajib ganti jam keterlambatan" },
  },
};

export const openApiSpec = {
  openapi: "3.1.0",
  info: {
    title: "Absensi Karyawan - Agent API",
    version: "1.0.0",
    description: "REST API absensi karyawan untuk Agent AI dengan akses admin penuh. " +
      "Semua waktu dalam ISO 8601 (UTC), tanggal YYYY-MM-DD, durasi dalam MENIT. " +
      "Status absensi: hadir, terlambat, libur_masuk. " +
      "Ganti jam: keterlambatan ditutup dengan kelebihan jam pulang (makeup_minutes); " +
      "sisanya late_debt_minutes. Kelebihan setelah ganti jam = overtime_minutes, " +
      "yang menjadi lembur resmi bila pengajuan lembur disetujui.",
  },
  servers: [{ url: "https://YOUR-PROJECT.supabase.co/functions/v1/agent-api" }],
  security: [{ ApiKey: [] }],
  components: {
    securitySchemes: {
      ApiKey: { type: "apiKey", in: "header", name: "x-api-key" },
    },
    responses: {
      Error: {
        description: "Error",
        content: {
          "application/json": {
            schema: { type: "object", properties: { error: { type: "string" } } },
          },
        },
      },
    },
  },
  paths: {
    "/summary/today": {
      get: {
        operationId: "getTodaySummary",
        summary: "Ringkasan kehadiran hari ini",
        description:
          "Status setiap karyawan aktif hari ini: hadir, terlambat, belum_absen, izin, sakit, cuti, libur, " +
          "libur_masuk, tanpa_jadwal. Cocok untuk pertanyaan 'siapa yang terlambat/belum absen hari ini?'.",
        responses: ok("Ringkasan hari ini"),
      },
    },
    "/recap": {
      get: {
        operationId: "getMonthlyRecap",
        summary: "Rekap bulanan per karyawan",
        description:
          "Hari kerja, hadir, alpa (absent_days), izin, sakit, cuti, jumlah & total menit terlambat, " +
          "menit sudah diganti, sisa ganti jam, pulang cepat, lembur, lembur disetujui, sisa cuti.",
        parameters: [
          query("month", "Bulan format YYYY-MM (default bulan ini)", { type: "string", example: "2026-10" }),
          query("employee_id", "Filter satu karyawan", uuid),
        ],
        responses: ok("Daftar rekap"),
      },
    },
    "/employees": {
      get: {
        operationId: "listEmployees",
        summary: "Daftar karyawan",
        parameters: [
          query("search", "Cari nama / kode / email"),
          query("active", "Filter aktif", { type: "boolean" }),
          query("role", "admin atau employee", { type: "string", enum: ["admin", "employee"] }),
        ],
        responses: ok("Daftar karyawan"),
      },
      post: {
        operationId: "createEmployee",
        summary: "Buat akun karyawan baru (langsung aktif)",
        requestBody: body({
          ...employeeSchema,
          required: ["email", "password", "full_name"],
          properties: {
            email: { type: "string", format: "email" },
            password: { type: "string", minLength: 6 },
            ...employeeSchema.properties,
          },
        }),
        responses: ok("Karyawan dibuat"),
      },
    },
    "/employees/{id}": {
      get: {
        operationId: "getEmployee",
        summary: "Detail karyawan beserta jadwal & lokasi absensi",
        parameters: [idParam],
        responses: ok("Detail karyawan"),
      },
      patch: {
        operationId: "updateEmployee",
        summary: "Ubah data karyawan (aktivasi, jadwal, peran, kuota cuti, dll)",
        parameters: [idParam],
        requestBody: body(employeeSchema),
        responses: ok("Karyawan diperbarui"),
      },
      delete: {
        operationId: "deleteEmployee",
        summary: "Hapus akun karyawan beserta seluruh datanya (permanen)",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/employees/{id}/locations": {
      put: {
        operationId: "setEmployeeLocations",
        summary: "Atur lokasi absensi yang diizinkan (array kosong = semua lokasi aktif)",
        parameters: [idParam],
        requestBody: body({
          type: "object",
          required: ["location_ids"],
          properties: { location_ids: { type: "array", items: uuid } },
        }),
        responses: ok("Lokasi diperbarui"),
      },
    },
    "/locations": {
      get: { operationId: "listLocations", summary: "Daftar lokasi absensi", responses: ok("Daftar lokasi") },
      post: {
        operationId: "createLocation",
        summary: "Tambah lokasi absensi (titik GPS + radius)",
        requestBody: body({ ...locationSchema, required: ["name", "latitude", "longitude"] }),
        responses: ok("Lokasi dibuat"),
      },
    },
    "/locations/{id}": {
      get: {
        operationId: "getLocation",
        summary: "Detail lokasi",
        parameters: [idParam],
        responses: ok("Lokasi"),
      },
      patch: {
        operationId: "updateLocation",
        summary: "Ubah lokasi absensi",
        parameters: [idParam],
        requestBody: body(locationSchema),
        responses: ok("Lokasi diperbarui"),
      },
      delete: {
        operationId: "deleteLocation",
        summary: "Hapus lokasi",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/schedules": {
      get: { operationId: "listSchedules", summary: "Daftar jadwal kerja", responses: ok("Daftar jadwal") },
      post: {
        operationId: "createSchedule",
        summary: "Tambah jadwal kerja",
        requestBody: body({ ...scheduleSchema, required: ["name", "start_time", "end_time"] }),
        responses: ok("Jadwal dibuat"),
      },
    },
    "/schedules/{id}": {
      get: {
        operationId: "getSchedule",
        summary: "Detail jadwal",
        parameters: [idParam],
        responses: ok("Jadwal"),
      },
      patch: {
        operationId: "updateSchedule",
        summary: "Ubah jadwal kerja",
        parameters: [idParam],
        requestBody: body(scheduleSchema),
        responses: ok("Jadwal diperbarui"),
      },
      delete: {
        operationId: "deleteSchedule",
        summary: "Hapus jadwal",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/attendances": {
      get: {
        operationId: "listAttendances",
        summary: "Data absensi (masuk/pulang, terlambat, ganti jam, lembur)",
        parameters: [
          query("employee_id", "Filter karyawan", uuid),
          query("date", "Tanggal tertentu", date),
          query("from", "Dari tanggal", date),
          query("to", "Sampai tanggal", date),
          query("status", "hadir | terlambat | libur_masuk"),
          query("late_only", "Hanya yang terlambat", { type: "boolean" }),
          query("limit", "Maks. baris (default 200, maks 1000)", { type: "integer" }),
        ],
        responses: ok("Daftar absensi"),
      },
    },
    "/attendances/{id}": {
      get: {
        operationId: "getAttendance",
        summary: "Detail absensi",
        parameters: [idParam],
        responses: ok("Absensi"),
      },
      patch: {
        operationId: "correctAttendance",
        summary: "Koreksi data absensi oleh admin (nilai disimpan apa adanya, tidak dihitung ulang)",
        parameters: [idParam],
        requestBody: body({
          type: "object",
          properties: {
            check_in_at: { type: "string", format: "date-time" },
            check_out_at: { type: "string", format: "date-time" },
            late_minutes: { type: "integer" },
            makeup_minutes: { type: "integer" },
            late_debt_minutes: { type: "integer" },
            early_leave_minutes: { type: "integer" },
            overtime_minutes: { type: "integer" },
            worked_minutes: { type: "integer" },
            status: { type: "string", enum: ["hadir", "terlambat", "libur_masuk"] },
            check_in_note: { type: "string" },
            check_out_note: { type: "string" },
          },
        }),
        responses: ok("Absensi dikoreksi"),
      },
      delete: {
        operationId: "deleteAttendance",
        summary: "Hapus data absensi",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/leave-requests": {
      get: {
        operationId: "listLeaveRequests",
        summary: "Daftar pengajuan izin / sakit / cuti",
        parameters: [
          query("status", "pending | approved | rejected", {
            type: "string",
            enum: ["pending", "approved", "rejected"],
          }),
          query("type", "izin | sakit | cuti", { type: "string", enum: ["izin", "sakit", "cuti"] }),
          query("employee_id", "Filter karyawan", uuid),
          query("from", "Pengajuan yang berakhir setelah tanggal ini", date),
          query("to", "Pengajuan yang dimulai sebelum tanggal ini", date),
        ],
        responses: ok("Daftar pengajuan"),
      },
      post: {
        operationId: "createLeaveRequest",
        summary: "Buat pengajuan izin/sakit/cuti atas nama karyawan (status pending)",
        requestBody: body({
          type: "object",
          required: ["employee_id", "type", "start_date", "end_date", "reason"],
          properties: {
            employee_id: uuid,
            type: { type: "string", enum: ["izin", "sakit", "cuti"] },
            start_date: date,
            end_date: date,
            reason: { type: "string" },
            attachment_url: { type: "string" },
          },
        }),
        responses: ok("Pengajuan dibuat"),
      },
    },
    "/leave-requests/{id}": {
      get: {
        operationId: "getLeaveRequest",
        summary: "Detail pengajuan",
        parameters: [idParam],
        responses: ok("Pengajuan"),
      },
      delete: {
        operationId: "deleteLeaveRequest",
        summary: "Hapus pengajuan",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/leave-requests/{id}/review": {
      post: {
        operationId: "reviewLeaveRequest",
        summary: "Setujui / tolak pengajuan izin, sakit, cuti (cuti dicek terhadap kuota tahunan)",
        parameters: [idParam],
        requestBody: body({
          type: "object",
          required: ["approve"],
          properties: { approve: { type: "boolean" }, note: { type: "string" } },
        }),
        responses: ok("Pengajuan diproses"),
      },
    },
    "/overtime-requests": {
      get: {
        operationId: "listOvertimeRequests",
        summary: "Daftar pengajuan lembur",
        parameters: [
          query("status", "pending | approved | rejected", {
            type: "string",
            enum: ["pending", "approved", "rejected"],
          }),
          query("employee_id", "Filter karyawan", uuid),
          query("from", "Dari tanggal", date),
          query("to", "Sampai tanggal", date),
        ],
        responses: ok("Daftar pengajuan lembur"),
      },
      post: {
        operationId: "createOvertimeRequest",
        summary: "Buat pengajuan lembur atas nama karyawan (status pending)",
        requestBody: body({
          type: "object",
          required: ["employee_id", "work_date", "requested_minutes", "reason"],
          properties: {
            employee_id: uuid,
            work_date: date,
            requested_minutes: { type: "integer", minimum: 1 },
            reason: { type: "string" },
          },
        }),
        responses: ok("Pengajuan dibuat"),
      },
    },
    "/overtime-requests/{id}": {
      get: {
        operationId: "getOvertimeRequest",
        summary: "Detail pengajuan lembur",
        parameters: [idParam],
        responses: ok("Pengajuan"),
      },
      delete: {
        operationId: "deleteOvertimeRequest",
        summary: "Hapus pengajuan lembur",
        parameters: [idParam],
        responses: ok("Terhapus"),
      },
    },
    "/overtime-requests/{id}/review": {
      post: {
        operationId: "reviewOvertimeRequest",
        summary: "Setujui / tolak lembur (menit disetujui dibatasi kelebihan jam aktual)",
        parameters: [idParam],
        requestBody: body({
          type: "object",
          required: ["approve"],
          properties: {
            approve: { type: "boolean" },
            approved_minutes: { type: "integer", description: "Default = menit yang diajukan" },
            note: { type: "string" },
          },
        }),
        responses: ok("Lembur diproses"),
      },
    },
    "/settings": {
      get: { operationId: "getSettings", summary: "Pengaturan perusahaan", responses: ok("Pengaturan") },
      patch: {
        operationId: "updateSettings",
        summary: "Ubah pengaturan (zona waktu, mode ganti jam, batas akurasi GPS)",
        requestBody: body({
          type: "object",
          properties: {
            company_name: { type: "string" },
            timezone: { type: "string", enum: ["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura"] },
            makeup_mode: { type: "string", enum: ["same_day", "monthly"] },
            max_gps_accuracy_m: { type: "integer" },
          },
        }),
        responses: ok("Pengaturan diperbarui"),
      },
    },
  },
};
