// =====================================================================
// Agent API - REST API absensi untuk Agent AI (n8n, Dify, Flowise,
// LangChain, Custom GPT Actions, Claude tool use, dll).
//
// Base URL : https://<project-ref>.supabase.co/functions/v1/agent-api
// Auth     : header  x-api-key: <AGENT_API_KEY>
//            atau    Authorization: Bearer <AGENT_API_KEY>
// Dokumen  : GET /openapi.json (tanpa auth)
//
// Akses penuh admin: memakai service_role key di sisi server, jadi
// AGENT_API_KEY wajib dirahasiakan seperti kata sandi admin.
// =====================================================================

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { openApiSpec } from "./openapi.ts";

const AGENT_API_KEY = Deno.env.get("AGENT_API_KEY") ?? "";
const db: SupabaseClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-api-key, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });

/** Bandingkan string tanpa bocor waktu (constant-time). */
function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) {
    diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  }
  return diff === 0;
}

function authorize(req: Request) {
  if (AGENT_API_KEY.length < 16) {
    throw new HttpError(500, "AGENT_API_KEY belum diset (minimal 16 karakter).");
  }
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const key = req.headers.get("x-api-key") ?? bearer;
  if (!key || !safeEqual(key, AGENT_API_KEY)) {
    throw new HttpError(401, "API key tidak valid.");
  }
}

/** Ambil hasil query Supabase atau lempar error yang rapi. */
function unwrap<T>(res: { data: T; error: { message: string; code?: string } | null }): T {
  if (res.error) {
    const notFound = res.error.code === "PGRST116";
    throw new HttpError(notFound ? 404 : 400, notFound ? "Data tidak ditemukan." : res.error.message);
  }
  return res.data;
}

/** Hanya ambil field yang diizinkan dari body. */
function pick(body: Record<string, unknown>, fields: string[]) {
  const out: Record<string, unknown> = {};
  for (const f of fields) if (f in body) out[f] = body[f];
  if (Object.keys(out).length === 0) {
    throw new HttpError(400, `Tidak ada field yang valid. Field yang diizinkan: ${fields.join(", ")}`);
  }
  return out;
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) return body;
  } catch {
    // diabaikan, ditangani di bawah
  }
  throw new HttpError(400, "Body harus berupa JSON object.");
}

function required(body: Record<string, unknown>, fields: string[]) {
  const missing = fields.filter((f) => body[f] === undefined || body[f] === null || body[f] === "");
  if (missing.length) throw new HttpError(400, `Field wajib: ${missing.join(", ")}`);
}

const EMPLOYEE_FIELDS = [
  "full_name",
  "employee_code",
  "phone",
  "position",
  "role",
  "schedule_id",
  "annual_leave_quota",
  "is_active",
];
const LOCATION_FIELDS = ["name", "address", "latitude", "longitude", "radius_m", "is_active"];
const SCHEDULE_FIELDS = [
  "name",
  "start_time",
  "end_time",
  "late_tolerance_min",
  "work_days",
  "min_overtime_min",
  "makeup_enabled",
];
const ATTENDANCE_FIX_FIELDS = [
  "check_in_at",
  "check_out_at",
  "late_minutes",
  "makeup_minutes",
  "late_debt_minutes",
  "early_leave_minutes",
  "overtime_minutes",
  "worked_minutes",
  "status",
  "check_in_note",
  "check_out_note",
];
const SETTINGS_FIELDS = ["company_name", "timezone", "makeup_mode", "max_gps_accuracy_m"];

const EMP_JOIN = "employee:profiles!%s_employee_id_fkey(full_name,employee_code)";
const withEmployee = (table: string) => `*, ${EMP_JOIN.replace("%s", table)}`;

async function companyToday(): Promise<{ date: string; isoDow: number; tz: string }> {
  const s = unwrap(await db.from("company_settings").select("timezone").eq("id", 1).single());
  const tz = (s?.timezone as string | undefined) ?? "Asia/Jakarta";
  const date = new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date());
  const dow = new Date(`${date}T00:00:00Z`).getUTCDay();
  return { date, isoDow: dow === 0 ? 7 : dow, tz };
}

/** Ringkasan kehadiran hari ini untuk semua karyawan aktif. */
async function todaySummary() {
  const { date, isoDow } = await companyToday();
  const [employees, attendances, leaves] = await Promise.all([
    db.from("profiles")
      .select("id, full_name, employee_code, schedule:work_schedules(name, start_time, end_time, work_days)")
      .eq("is_active", true).order("full_name").then(unwrap),
    db.from("attendances").select("*").eq("work_date", date).then(unwrap),
    db.from("leave_requests").select("employee_id, type")
      .eq("status", "approved").lte("start_date", date).gte("end_date", date).then(unwrap),
  ]);

  // deno-lint-ignore no-explicit-any
  const rows = (employees as any[]).map((e) => {
    // deno-lint-ignore no-explicit-any
    const att = (attendances as any[]).find((a) => a.employee_id === e.id);
    // deno-lint-ignore no-explicit-any
    const leave = (leaves as any[]).find((l) => l.employee_id === e.id);
    const workDay = e.schedule ? (e.schedule.work_days as number[]).includes(isoDow) : false;
    let status: string;
    if (att) status = att.late_minutes > 0 ? "terlambat" : att.is_work_day ? "hadir" : "libur_masuk";
    else if (leave) status = leave.type;
    else if (!e.schedule) status = "tanpa_jadwal";
    else if (!workDay) status = "libur";
    else status = "belum_absen";
    return {
      employee_id: e.id,
      full_name: e.full_name,
      employee_code: e.employee_code,
      schedule: e.schedule ? `${e.schedule.name} ${e.schedule.start_time}-${e.schedule.end_time}` : null,
      status,
      check_in_at: att?.check_in_at ?? null,
      check_out_at: att?.check_out_at ?? null,
      late_minutes: att?.late_minutes ?? 0,
      late_debt_minutes: att?.late_debt_minutes ?? 0,
      overtime_minutes: att?.overtime_minutes ?? 0,
    };
  });

  const counts: Record<string, number> = {};
  for (const r of rows) counts[r.status] = (counts[r.status] ?? 0) + 1;
  return { date, total_employees: rows.length, counts, employees: rows };
}

function monthStart(month: string | null): string {
  if (!month) return new Date().toISOString().slice(0, 7) + "-01";
  if (!/^\d{4}-\d{2}$/.test(month)) throw new HttpError(400, "Format month harus YYYY-MM.");
  return `${month}-01`;
}

async function route(req: Request, url: URL): Promise<Response> {
  const parts = url.pathname.split("/").filter(Boolean);
  // buang prefix nama fungsi: /functions/v1/agent-api/... atau /agent-api/...
  const idx = parts.indexOf("agent-api");
  const seg = idx >= 0 ? parts.slice(idx + 1) : parts;
  const [resource, id, action] = seg;
  const m = req.method;
  const q = url.searchParams;

  if (m === "GET" && (resource === undefined || resource === "health")) {
    return json({ ok: true, service: "absensi-agent-api", docs: "/openapi.json" });
  }
  if (m === "GET" && resource === "openapi.json") {
    // URL publik: PUBLIC_API_URL (opsional) atau https://<project>.supabase.co/functions/v1/agent-api
    const base = Deno.env.get("PUBLIC_API_URL") ??
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/agent-api`;
    return json({ ...openApiSpec, servers: [{ url: base }] });
  }

  authorize(req);

  switch (resource) {
    // ------------------------------------------------ ringkasan
    case "summary":
      if (m === "GET" && id === "today") return json({ data: await todaySummary() });
      break;

    // ------------------------------------------------ karyawan
    case "employees": {
      if (!id && m === "GET") {
        let query = db.from("profiles").select("*").order("full_name");
        if (q.get("active") !== null) query = query.eq("is_active", q.get("active") === "true");
        if (q.get("role")) query = query.eq("role", q.get("role")!);
        const search = q.get("search");
        if (search) {
          const s = search.replace(/[,()]/g, " ");
          query = query.or(`full_name.ilike.%${s}%,employee_code.ilike.%${s}%,email.ilike.%${s}%`);
        }
        return json({ data: unwrap(await query) });
      }
      if (!id && m === "POST") {
        const body = await readBody(req);
        required(body, ["email", "password", "full_name"]);
        const created = await db.auth.admin.createUser({
          email: String(body.email),
          password: String(body.password),
          email_confirm: true,
          user_metadata: { full_name: body.full_name },
        });
        if (created.error) throw new HttpError(400, created.error.message);
        const uid = created.data.user!.id;
        const update = { is_active: true, ...pickOptional(body, EMPLOYEE_FIELDS) };
        const profile = unwrap(await db.from("profiles").update(update).eq("id", uid).select().single());
        return json({ data: profile }, 201);
      }
      if (id && !action && m === "GET") {
        const profile = unwrap(
          await db.from("profiles").select("*, schedule:work_schedules(*)").eq("id", id).single(),
        );
        const locs = unwrap(
          await db.from("employee_locations").select("location:work_locations(*)").eq("employee_id", id),
        );
        // deno-lint-ignore no-explicit-any
        return json({ data: { ...profile, locations: (locs as any[]).map((l) => l.location) } });
      }
      if (id && !action && m === "PATCH") {
        const body = pick(await readBody(req), EMPLOYEE_FIELDS);
        return json({ data: unwrap(await db.from("profiles").update(body).eq("id", id).select().single()) });
      }
      if (id && !action && m === "DELETE") {
        const res = await db.auth.admin.deleteUser(id);
        if (res.error) throw new HttpError(400, res.error.message);
        return json({ data: { deleted: id } });
      }
      if (id && action === "locations" && m === "PUT") {
        const body = await readBody(req);
        const ids = body.location_ids;
        if (!Array.isArray(ids)) throw new HttpError(400, "location_ids harus berupa array UUID.");
        unwrap(await db.from("employee_locations").delete().eq("employee_id", id));
        if (ids.length) {
          unwrap(
            await db.from("employee_locations").insert(
              ids.map((l) => ({ employee_id: id, location_id: l })),
            ),
          );
        }
        return json({ data: { employee_id: id, location_ids: ids } });
      }
      break;
    }

    // ------------------------------------------------ lokasi & jadwal (CRUD sederhana)
    case "locations":
    case "schedules": {
      const table = resource === "locations" ? "work_locations" : "work_schedules";
      const fields = resource === "locations" ? LOCATION_FIELDS : SCHEDULE_FIELDS;
      if (!id && m === "GET") return json({ data: unwrap(await db.from(table).select("*").order("name")) });
      if (!id && m === "POST") {
        const body = pick(await readBody(req), fields);
        required(
          body,
          resource === "locations" ? ["name", "latitude", "longitude"] : ["name", "start_time", "end_time"],
        );
        return json({ data: unwrap(await db.from(table).insert(body).select().single()) }, 201);
      }
      if (id && m === "GET") {
        return json({ data: unwrap(await db.from(table).select("*").eq("id", id).single()) });
      }
      if (id && m === "PATCH") {
        const body = pick(await readBody(req), fields);
        return json({ data: unwrap(await db.from(table).update(body).eq("id", id).select().single()) });
      }
      if (id && m === "DELETE") {
        unwrap(await db.from(table).delete().eq("id", id));
        return json({ data: { deleted: id } });
      }
      break;
    }

    // ------------------------------------------------ absensi
    case "attendances": {
      if (!id && m === "GET") {
        let query = db.from("attendances").select(withEmployee("attendances"))
          .order("work_date", { ascending: false }).order("check_in_at", { ascending: false })
          .limit(Math.min(Number(q.get("limit") ?? 200), 1000));
        if (q.get("employee_id")) query = query.eq("employee_id", q.get("employee_id")!);
        if (q.get("date")) query = query.eq("work_date", q.get("date")!);
        if (q.get("from")) query = query.gte("work_date", q.get("from")!);
        if (q.get("to")) query = query.lte("work_date", q.get("to")!);
        if (q.get("status")) query = query.eq("status", q.get("status")!);
        if (q.get("late_only") === "true") query = query.gt("late_minutes", 0);
        return json({ data: unwrap(await query) });
      }
      if (id && m === "GET") {
        return json({
          data: unwrap(
            await db.from("attendances").select(withEmployee("attendances")).eq("id", id).single(),
          ),
        });
      }
      if (id && m === "PATCH") {
        const body = pick(await readBody(req), ATTENDANCE_FIX_FIELDS);
        return json({
          data: unwrap(await db.from("attendances").update(body).eq("id", id).select().single()),
        });
      }
      if (id && m === "DELETE") {
        unwrap(await db.from("attendances").delete().eq("id", id));
        return json({ data: { deleted: id } });
      }
      break;
    }

    // ------------------------------------------------ izin/sakit/cuti & lembur
    case "leave-requests":
    case "overtime-requests": {
      const isLeave = resource === "leave-requests";
      const table = isLeave ? "leave_requests" : "overtime_requests";
      if (!id && m === "GET") {
        let query = db.from(table).select(withEmployee(table))
          .order("created_at", { ascending: false })
          .limit(Math.min(Number(q.get("limit") ?? 200), 1000));
        if (q.get("status")) query = query.eq("status", q.get("status")!);
        if (q.get("employee_id")) query = query.eq("employee_id", q.get("employee_id")!);
        if (isLeave && q.get("type")) query = query.eq("type", q.get("type")!);
        if (q.get("from")) query = query.gte(isLeave ? "end_date" : "work_date", q.get("from")!);
        if (q.get("to")) query = query.lte(isLeave ? "start_date" : "work_date", q.get("to")!);
        return json({ data: unwrap(await query) });
      }
      if (!id && m === "POST") {
        // membuat pengajuan atas nama karyawan (status selalu pending)
        const body = await readBody(req);
        const fields = isLeave
          ? ["employee_id", "type", "start_date", "end_date", "reason", "attachment_url"]
          : ["employee_id", "work_date", "requested_minutes", "reason"];
        required(body, fields.filter((f) => f !== "attachment_url"));
        const row = pick(body, fields);
        return json({ data: unwrap(await db.from(table).insert(row).select().single()) }, 201);
      }
      if (id && !action && m === "GET") {
        return json({ data: unwrap(await db.from(table).select(withEmployee(table)).eq("id", id).single()) });
      }
      if (id && action === "review" && m === "POST") {
        const body = await readBody(req);
        if (typeof body.approve !== "boolean") throw new HttpError(400, "Field approve (boolean) wajib.");
        const res = isLeave
          ? await db.rpc("review_leave", { p_id: id, p_approve: body.approve, p_note: body.note ?? null })
          : await db.rpc("review_overtime", {
            p_id: id,
            p_approve: body.approve,
            p_approved_minutes: body.approved_minutes ?? null,
            p_note: body.note ?? null,
          });
        return json({ data: unwrap(res) });
      }
      if (id && !action && m === "DELETE") {
        unwrap(await db.from(table).delete().eq("id", id));
        return json({ data: { deleted: id } });
      }
      break;
    }

    // ------------------------------------------------ rekap
    case "recap":
      if (m === "GET") {
        const res = await db.rpc("monthly_recap", {
          p_month: monthStart(q.get("month")),
          p_employee_id: q.get("employee_id"),
        });
        return json({ data: unwrap(res) });
      }
      break;

    // ------------------------------------------------ pengaturan
    case "settings":
      if (m === "GET") {
        return json({ data: unwrap(await db.from("company_settings").select("*").eq("id", 1).single()) });
      }
      if (m === "PATCH") {
        const body = { ...pick(await readBody(req), SETTINGS_FIELDS), updated_at: new Date().toISOString() };
        return json({
          data: unwrap(await db.from("company_settings").update(body).eq("id", 1).select().single()),
        });
      }
      break;
  }

  throw new HttpError(404, `Endpoint ${m} /${seg.join("/")} tidak ditemukan. Lihat /openapi.json`);
}

function pickOptional(body: Record<string, unknown>, fields: string[]) {
  const out: Record<string, unknown> = {};
  for (const f of fields) if (f in body) out[f] = body[f];
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  try {
    return await route(req, new URL(req.url));
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error(e);
    return json({ error: "Terjadi kesalahan pada server." }, 500);
  }
});
