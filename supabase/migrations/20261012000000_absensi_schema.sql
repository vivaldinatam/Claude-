-- =====================================================================
-- Absensi Karyawan - skema database Supabase
-- Jalankan di Supabase Dashboard > SQL Editor (sekali saja).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. Tabel master
-- ---------------------------------------------------------------------

-- Pengaturan perusahaan (hanya satu baris, id = 1)
create table if not exists public.company_settings (
  id                  int primary key default 1 check (id = 1),
  company_name        text not null default 'Perusahaan Saya',
  timezone            text not null default 'Asia/Jakarta',
  -- 'same_day' : keterlambatan hanya bisa diganti di hari yang sama
  -- 'monthly'  : sisa keterlambatan bisa diganti dengan kelebihan jam
  --              (yang tidak diajukan sebagai lembur) di bulan yang sama
  makeup_mode         text not null default 'same_day'
                        check (makeup_mode in ('same_day', 'monthly')),
  max_gps_accuracy_m  int  not null default 100 check (max_gps_accuracy_m > 0),
  updated_at          timestamptz not null default now()
);
insert into public.company_settings (id) values (1) on conflict do nothing;

-- Lokasi tempat absensi (geofence)
create table if not exists public.work_locations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  address     text,
  latitude    double precision not null check (latitude between -90 and 90),
  longitude   double precision not null check (longitude between -180 and 180),
  radius_m    int not null default 100 check (radius_m between 10 and 5000),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Jadwal / jam kerja
create table if not exists public.work_schedules (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  start_time          time not null,
  end_time            time not null,
  -- toleransi: datang <= toleransi tidak dihitung terlambat
  late_tolerance_min  int  not null default 0 check (late_tolerance_min >= 0),
  -- hari kerja ISO: 1 = Senin ... 7 = Minggu
  work_days           int[] not null default '{1,2,3,4,5}',
  -- kelebihan jam minimal agar dihitung lembur
  min_overtime_min    int  not null default 30 check (min_overtime_min >= 0),
  -- aktifkan ganti jam keterlambatan
  makeup_enabled      boolean not null default true,
  created_at          timestamptz not null default now()
);

-- Profil karyawan (1:1 dengan auth.users)
create table if not exists public.profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  full_name            text not null default '',
  email                text,
  employee_code        text unique,
  phone                text,
  position             text,
  role                 text not null default 'employee' check (role in ('admin', 'employee')),
  schedule_id          uuid references public.work_schedules (id) on delete set null,
  annual_leave_quota   int not null default 12 check (annual_leave_quota >= 0),
  is_active            boolean not null default false,
  created_at           timestamptz not null default now()
);

-- Penugasan lokasi absensi per karyawan.
-- Jika karyawan tidak punya penugasan, semua lokasi aktif berlaku.
create table if not exists public.employee_locations (
  employee_id  uuid not null references public.profiles (id) on delete cascade,
  location_id  uuid not null references public.work_locations (id) on delete cascade,
  primary key (employee_id, location_id)
);

-- ---------------------------------------------------------------------
-- 2. Tabel transaksi
-- ---------------------------------------------------------------------

create table if not exists public.attendances (
  id                      uuid primary key default gen_random_uuid(),
  employee_id             uuid not null references public.profiles (id) on delete cascade,
  work_date               date not null,
  schedule_id             uuid references public.work_schedules (id) on delete set null,
  is_work_day             boolean not null default true,
  scheduled_start         timestamptz,
  scheduled_end           timestamptz,

  check_in_at             timestamptz not null,
  check_in_lat            double precision not null,
  check_in_lng            double precision not null,
  check_in_accuracy_m     double precision,
  check_in_distance_m     double precision,
  check_in_location_id    uuid references public.work_locations (id) on delete set null,
  check_in_note           text,

  check_out_at            timestamptz,
  check_out_lat           double precision,
  check_out_lng           double precision,
  check_out_accuracy_m    double precision,
  check_out_distance_m    double precision,
  check_out_location_id   uuid references public.work_locations (id) on delete set null,
  check_out_note          text,

  -- hasil perhitungan (menit)
  late_minutes            int not null default 0,  -- total terlambat
  makeup_minutes          int not null default 0,  -- terlambat yang sudah diganti
  late_debt_minutes       int not null default 0,  -- sisa terlambat belum diganti
  early_leave_minutes     int not null default 0,  -- pulang sebelum jadwal
  overtime_minutes        int not null default 0,  -- kelebihan jam setelah ganti jam
  worked_minutes          int not null default 0,

  status                  text not null default 'hadir'
                            check (status in ('hadir', 'terlambat', 'libur_masuk')),
  created_at              timestamptz not null default now(),
  unique (employee_id, work_date)
);
create index if not exists attendances_emp_date_idx on public.attendances (employee_id, work_date);

-- Pengajuan izin / sakit / cuti
create table if not exists public.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references public.profiles (id) on delete cascade,
  type          text not null check (type in ('izin', 'sakit', 'cuti')),
  start_date    date not null,
  end_date      date not null,
  reason        text not null,
  attachment_url text,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by   uuid references public.profiles (id),
  reviewed_at   timestamptz,
  review_note   text,
  created_at    timestamptz not null default now(),
  check (end_date >= start_date)
);
create index if not exists leave_requests_emp_idx on public.leave_requests (employee_id, start_date);

-- Pengajuan lembur
create table if not exists public.overtime_requests (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references public.profiles (id) on delete cascade,
  work_date          date not null,
  requested_minutes  int not null check (requested_minutes > 0),
  approved_minutes   int,
  reason             text not null,
  status             text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by        uuid references public.profiles (id),
  reviewed_at        timestamptz,
  review_note        text,
  created_at         timestamptz not null default now(),
  unique (employee_id, work_date)
);

-- ---------------------------------------------------------------------
-- 3. Fungsi bantu
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Pemanggil memakai service_role key (dipakai oleh Agent API / Edge Function)
create or replace function public.is_service_role()
returns boolean
language sql stable set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role';
$$;

-- Jarak dua koordinat dalam meter (rumus Haversine)
create or replace function public.distance_m(lat1 float8, lng1 float8, lat2 float8, lng2 float8)
returns float8
language sql immutable set search_path = ''
as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- Jumlah hari kerja (sesuai jadwal) dalam rentang tanggal
create or replace function public.count_work_days(p_work_days int[], p_start date, p_end date)
returns int
language sql immutable set search_path = ''
as $$
  select count(*)::int
  from generate_series(p_start, p_end, interval '1 day') d
  where extract(isodow from d)::int = any (coalesce(p_work_days, '{1,2,3,4,5}'));
$$;

-- Profil otomatis saat user mendaftar. User pertama menjadi admin aktif.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_first boolean;
begin
  select not exists (select 1 from public.profiles) into v_first;
  insert into public.profiles (id, full_name, email, role, is_active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    new.email,
    case when v_first then 'admin' else 'employee' end,
    v_first
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Lokasi terdekat yang boleh dipakai karyawan
create or replace function public._nearest_location(p_employee uuid, p_lat float8, p_lng float8)
returns table (location_id uuid, location_name text, radius_m int, distance float8)
language sql stable security definer set search_path = public
as $$
  select l.id, l.name, l.radius_m, public.distance_m(p_lat, p_lng, l.latitude, l.longitude)
  from public.work_locations l
  where l.is_active
    and (
      not exists (select 1 from public.employee_locations e where e.employee_id = p_employee)
      or exists (select 1 from public.employee_locations e
                 where e.employee_id = p_employee and e.location_id = l.id)
    )
  order by 4
  limit 1;
$$;

-- Validasi GPS: akurasi, lokasi palsu, dan radius. Mengembalikan lokasi yang cocok.
create or replace function public._validate_position(
  p_employee uuid, p_lat float8, p_lng float8, p_accuracy float8, p_is_mocked boolean
)
returns table (location_id uuid, distance float8)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_max_acc int;
  v_loc record;
begin
  if coalesce(p_is_mocked, false) then
    raise exception 'Lokasi palsu (mock location) terdeteksi. Matikan aplikasi fake GPS.';
  end if;

  select max_gps_accuracy_m into v_max_acc from public.company_settings where id = 1;
  if p_accuracy is not null and p_accuracy > v_max_acc then
    raise exception 'Akurasi GPS terlalu rendah (% m). Maksimal % m, coba di area terbuka.',
      round(p_accuracy::numeric), v_max_acc;
  end if;

  select * into v_loc from public._nearest_location(p_employee, p_lat, p_lng);
  if v_loc.location_id is null then
    raise exception 'Belum ada lokasi absensi yang aktif. Hubungi admin.';
  end if;
  if v_loc.distance > v_loc.radius_m then
    raise exception 'Anda di luar area absensi. Jarak ke % adalah % m (maksimal % m).',
      v_loc.location_name, round(v_loc.distance::numeric), v_loc.radius_m;
  end if;

  location_id := v_loc.location_id;
  distance := v_loc.distance;
  return next;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. RPC Absen Masuk
-- ---------------------------------------------------------------------
create or replace function public.check_in(
  p_lat float8, p_lng float8, p_accuracy float8 default null,
  p_is_mocked boolean default false, p_note text default null
)
returns public.attendances
language plpgsql security definer set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_profile   public.profiles;
  v_sched     public.work_schedules;
  v_tz        text;
  v_local     timestamp;
  v_date      date;
  v_is_work   boolean;
  v_start     timestamptz;
  v_end       timestamptz;
  v_late      int := 0;
  v_pos       record;
  v_row       public.attendances;
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu.'; end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found or not v_profile.is_active then
    raise exception 'Akun Anda belum diaktifkan oleh admin.';
  end if;
  select * into v_sched from public.work_schedules where id = v_profile.schedule_id;
  if not found then
    raise exception 'Jadwal kerja Anda belum diatur. Hubungi admin.';
  end if;

  select timezone into v_tz from public.company_settings where id = 1;
  v_local := now() at time zone v_tz;
  v_date := v_local::date;
  -- shift malam (melewati tengah malam): absen setelah 00:00 sebelum jam pulang
  -- dihitung sebagai shift hari sebelumnya
  if v_sched.end_time <= v_sched.start_time and v_local::time < v_sched.end_time then
    v_date := v_date - 1;
  end if;

  if exists (select 1 from public.attendances where employee_id = v_uid and work_date = v_date) then
    raise exception 'Anda sudah absen masuk untuk tanggal %.', to_char(v_date, 'DD-MM-YYYY');
  end if;

  if exists (select 1 from public.leave_requests
             where employee_id = v_uid and status = 'approved'
               and v_date between start_date and end_date) then
    raise exception 'Anda tercatat izin/sakit/cuti pada tanggal ini.';
  end if;

  select * into v_pos from public._validate_position(v_uid, p_lat, p_lng, p_accuracy, p_is_mocked);

  v_is_work := extract(isodow from v_date)::int = any (v_sched.work_days);
  if v_is_work then
    v_start := (v_date + v_sched.start_time) at time zone v_tz;
    v_end := (v_date + v_sched.end_time) at time zone v_tz;
    if v_sched.end_time <= v_sched.start_time then
      v_end := v_end + interval '1 day';
    end if;
    v_late := greatest(0, floor(extract(epoch from (now() - v_start)) / 60))::int;
    if v_late <= v_sched.late_tolerance_min then
      v_late := 0;
    end if;
  end if;

  insert into public.attendances (
    employee_id, work_date, schedule_id, is_work_day, scheduled_start, scheduled_end,
    check_in_at, check_in_lat, check_in_lng, check_in_accuracy_m,
    check_in_distance_m, check_in_location_id, check_in_note,
    late_minutes, late_debt_minutes, status
  ) values (
    v_uid, v_date, v_sched.id, v_is_work, v_start, v_end,
    now(), p_lat, p_lng, p_accuracy,
    v_pos.distance, v_pos.location_id, p_note,
    v_late, v_late,
    case when not v_is_work then 'libur_masuk' when v_late > 0 then 'terlambat' else 'hadir' end
  ) returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. RPC Absen Pulang (termasuk perhitungan ganti jam & lembur)
-- ---------------------------------------------------------------------
create or replace function public.check_out(
  p_lat float8, p_lng float8, p_accuracy float8 default null,
  p_is_mocked boolean default false, p_note text default null
)
returns public.attendances
language plpgsql security definer set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_att       public.attendances;
  v_sched     public.work_schedules;
  v_pos       record;
  v_now       timestamptz := now();
  v_extra     int := 0;
  v_early     int := 0;
  v_makeup    int := 0;
  v_overtime  int := 0;
  v_worked    int;
begin
  if v_uid is null then raise exception 'Silakan login terlebih dahulu.'; end if;

  select * into v_att from public.attendances
  where employee_id = v_uid and check_out_at is null
    and check_in_at > v_now - interval '24 hours'
  order by check_in_at desc
  limit 1
  for update;
  if not found then
    raise exception 'Tidak ada absen masuk yang aktif. Silakan absen masuk terlebih dahulu.';
  end if;

  select * into v_pos from public._validate_position(v_uid, p_lat, p_lng, p_accuracy, p_is_mocked);
  select * into v_sched from public.work_schedules where id = v_att.schedule_id;

  v_worked := greatest(0, floor(extract(epoch from (v_now - v_att.check_in_at)) / 60))::int;

  if v_att.is_work_day and v_att.scheduled_end is not null then
    v_extra := greatest(0, floor(extract(epoch from (v_now - v_att.scheduled_end)) / 60))::int;
    v_early := greatest(0, ceil(extract(epoch from (v_att.scheduled_end - v_now)) / 60))::int;
    if coalesce(v_sched.makeup_enabled, true) then
      -- ganti jam: kelebihan jam pulang dipakai dulu untuk menutup keterlambatan
      v_makeup := least(v_att.late_minutes, v_extra);
    end if;
    v_overtime := v_extra - v_makeup;
  else
    -- masuk di hari libur: seluruh jam kerja dihitung lembur
    v_overtime := v_worked;
  end if;

  update public.attendances set
    check_out_at = v_now,
    check_out_lat = p_lat,
    check_out_lng = p_lng,
    check_out_accuracy_m = p_accuracy,
    check_out_distance_m = v_pos.distance,
    check_out_location_id = v_pos.location_id,
    check_out_note = p_note,
    makeup_minutes = v_makeup,
    late_debt_minutes = late_minutes - v_makeup,
    early_leave_minutes = v_early,
    overtime_minutes = v_overtime,
    worked_minutes = v_worked
  where id = v_att.id
  returning * into v_att;

  return v_att;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. RPC persetujuan (admin)
-- ---------------------------------------------------------------------
create or replace function public.review_leave(p_id uuid, p_approve boolean, p_note text default null)
returns public.leave_requests
language plpgsql security definer set search_path = public
as $$
declare
  v_req     public.leave_requests;
  v_prof    public.profiles;
  v_days    int;
  v_used    int;
  v_wd      int[];
begin
  if not (public.is_admin() or public.is_service_role()) then
    raise exception 'Hanya admin yang dapat menyetujui.';
  end if;

  select * into v_req from public.leave_requests where id = p_id for update;
  if not found then raise exception 'Pengajuan tidak ditemukan.'; end if;
  if v_req.status <> 'pending' then raise exception 'Pengajuan sudah diproses.'; end if;

  if p_approve and v_req.type = 'cuti' then
    select * into v_prof from public.profiles where id = v_req.employee_id;
    select work_days into v_wd from public.work_schedules where id = v_prof.schedule_id;
    v_days := public.count_work_days(v_wd, v_req.start_date, v_req.end_date);
    select coalesce(sum(public.count_work_days(v_wd, start_date, end_date)), 0) into v_used
    from public.leave_requests
    where employee_id = v_req.employee_id and type = 'cuti' and status = 'approved'
      and extract(year from start_date) = extract(year from v_req.start_date);
    if v_used + v_days > v_prof.annual_leave_quota then
      raise exception 'Kuota cuti tidak cukup. Terpakai % dari % hari, pengajuan % hari.',
        v_used, v_prof.annual_leave_quota, v_days;
    end if;
  end if;

  update public.leave_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note
  where id = p_id
  returning * into v_req;
  return v_req;
end;
$$;

create or replace function public.review_overtime(
  p_id uuid, p_approve boolean, p_approved_minutes int default null, p_note text default null
)
returns public.overtime_requests
language plpgsql security definer set search_path = public
as $$
declare
  v_req     public.overtime_requests;
  v_actual  int;
  v_min     int;
  v_minutes int;
begin
  if not (public.is_admin() or public.is_service_role()) then
    raise exception 'Hanya admin yang dapat menyetujui.';
  end if;

  select * into v_req from public.overtime_requests where id = p_id for update;
  if not found then raise exception 'Pengajuan tidak ditemukan.'; end if;
  if v_req.status <> 'pending' then raise exception 'Pengajuan sudah diproses.'; end if;

  if p_approve then
    select a.overtime_minutes, s.min_overtime_min into v_actual, v_min
    from public.attendances a
    left join public.work_schedules s on s.id = a.schedule_id
    where a.employee_id = v_req.employee_id and a.work_date = v_req.work_date
      and a.check_out_at is not null;
    if v_actual is null then
      raise exception 'Belum ada data absen pulang pada tanggal lembur tersebut.';
    end if;
    if v_actual <= 0 then
      raise exception 'Tidak ada kelebihan jam pada tanggal tersebut.';
    end if;
    if v_actual < coalesce(v_min, 0) then
      raise exception 'Kelebihan jam (% menit) di bawah minimal lembur (% menit).', v_actual, v_min;
    end if;
    -- lembur disetujui tidak boleh melebihi kelebihan jam aktual
    v_minutes := least(coalesce(p_approved_minutes, v_req.requested_minutes), v_actual);
  end if;

  update public.overtime_requests set
    status = case when p_approve then 'approved' else 'rejected' end,
    approved_minutes = v_minutes,
    reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note
  where id = p_id
  returning * into v_req;
  return v_req;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Rekap bulanan
--    Karyawan hanya bisa melihat rekap miliknya; admin bisa semua.
-- ---------------------------------------------------------------------
create or replace function public.monthly_recap(p_month date, p_employee_id uuid default null)
returns table (
  employee_id            uuid,
  full_name              text,
  employee_code          text,
  work_days              int,
  present_days           int,
  late_count             int,
  late_minutes           int,
  makeup_minutes         int,
  late_debt_minutes      int,
  early_leave_minutes    int,
  overtime_minutes       int,
  overtime_approved_minutes int,
  izin_days              int,
  sakit_days             int,
  cuti_days              int,
  absent_days            int,
  leave_quota            int,
  leave_used_year        int,
  leave_remaining        int
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_start  date := date_trunc('month', p_month)::date;
  v_end    date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_today  date;
  v_mode   text;
begin
  select (now() at time zone timezone)::date, makeup_mode into v_today, v_mode
  from public.company_settings where id = 1;

  -- karyawan biasa hanya boleh melihat rekap miliknya sendiri
  if not (public.is_admin() or public.is_service_role()) then
    if auth.uid() is null then
      raise exception 'Silakan login terlebih dahulu.';
    end if;
    p_employee_id := auth.uid();
  end if;

  return query
  with emp as (
    select p.id, p.full_name, p.employee_code, p.annual_leave_quota, p.created_at,
           coalesce(s.work_days, '{1,2,3,4,5}') as wd
    from public.profiles p
    left join public.work_schedules s on s.id = p.schedule_id
    where (p_employee_id is null or p.id = p_employee_id)
      and p.is_active
  ),
  days as (
    select e.id as emp_id, d::date as day
    from emp e
    cross join generate_series(greatest(v_start, (e.created_at at time zone 'UTC')::date), v_end, interval '1 day') d
    where extract(isodow from d)::int = any (e.wd)
  ),
  att as (
    select a.employee_id,
      count(*) filter (where a.is_work_day)::int as present,
      count(*) filter (where a.late_minutes > 0)::int as late_cnt,
      coalesce(sum(a.late_minutes), 0)::int as late_min,
      coalesce(sum(a.makeup_minutes), 0)::int as makeup_min,
      coalesce(sum(a.late_debt_minutes), 0)::int as debt_min,
      coalesce(sum(a.early_leave_minutes), 0)::int as early_min,
      coalesce(sum(a.overtime_minutes), 0)::int as ot_min
    from public.attendances a
    where a.work_date between v_start and v_end
    group by a.employee_id
  ),
  ot as (
    select o.employee_id, coalesce(sum(o.approved_minutes), 0)::int as ot_appr
    from public.overtime_requests o
    where o.status = 'approved' and o.work_date between v_start and v_end
    group by o.employee_id
  ),
  lv as (
    select d.emp_id,
      count(*) filter (where l.type = 'izin')::int as izin,
      count(*) filter (where l.type = 'sakit')::int as sakit,
      count(*) filter (where l.type = 'cuti')::int as cuti
    from days d
    join public.leave_requests l
      on l.employee_id = d.emp_id and l.status = 'approved'
     and d.day between l.start_date and l.end_date
    group by d.emp_id
  ),
  absent as (
    select d.emp_id, count(*)::int as cnt
    from days d
    where d.day < v_today
      and not exists (select 1 from public.attendances a
                      where a.employee_id = d.emp_id and a.work_date = d.day)
      and not exists (select 1 from public.leave_requests l
                      where l.employee_id = d.emp_id and l.status = 'approved'
                        and d.day between l.start_date and l.end_date)
    group by d.emp_id
  ),
  wdays as (
    select d.emp_id, count(*)::int as cnt from days d group by d.emp_id
  ),
  cuti_year as (
    select e.id as emp_id,
      coalesce(sum(public.count_work_days(e.wd, l.start_date, l.end_date)), 0)::int as used
    from emp e
    join public.leave_requests l
      on l.employee_id = e.id and l.type = 'cuti' and l.status = 'approved'
     and extract(year from l.start_date) = extract(year from v_start)
    group by e.id
  )
  select
    e.id, e.full_name, e.employee_code,
    coalesce(w.cnt, 0),
    coalesce(a.present, 0),
    coalesce(a.late_cnt, 0),
    coalesce(a.late_min, 0),
    -- mode bulanan: kelebihan jam yang tidak diajukan lembur ikut menutup sisa terlambat
    coalesce(a.makeup_min, 0) + case when v_mode = 'monthly'
      then least(coalesce(a.debt_min, 0), greatest(0, coalesce(a.ot_min, 0) - coalesce(o.ot_appr, 0)))
      else 0 end,
    coalesce(a.debt_min, 0) - case when v_mode = 'monthly'
      then least(coalesce(a.debt_min, 0), greatest(0, coalesce(a.ot_min, 0) - coalesce(o.ot_appr, 0)))
      else 0 end,
    coalesce(a.early_min, 0),
    coalesce(a.ot_min, 0),
    coalesce(o.ot_appr, 0),
    coalesce(l.izin, 0),
    coalesce(l.sakit, 0),
    coalesce(l.cuti, 0),
    coalesce(ab.cnt, 0),
    e.annual_leave_quota,
    coalesce(cy.used, 0),
    e.annual_leave_quota - coalesce(cy.used, 0)
  from emp e
  left join att a on a.employee_id = e.id
  left join ot o on o.employee_id = e.id
  left join lv l on l.emp_id = e.id
  left join absent ab on ab.emp_id = e.id
  left join wdays w on w.emp_id = e.id
  left join cuti_year cy on cy.emp_id = e.id
  order by e.full_name;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Row Level Security
-- ---------------------------------------------------------------------
alter table public.company_settings   enable row level security;
alter table public.work_locations     enable row level security;
alter table public.work_schedules     enable row level security;
alter table public.profiles           enable row level security;
alter table public.employee_locations enable row level security;
alter table public.attendances        enable row level security;
alter table public.leave_requests     enable row level security;
alter table public.overtime_requests  enable row level security;

-- Master data: semua user login boleh baca, hanya admin boleh ubah
drop policy if exists settings_read on public.company_settings;
create policy settings_read on public.company_settings for select to authenticated using (true);
drop policy if exists settings_admin on public.company_settings;
create policy settings_admin on public.company_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists locations_read on public.work_locations;
create policy locations_read on public.work_locations for select to authenticated using (true);
drop policy if exists locations_admin on public.work_locations;
create policy locations_admin on public.work_locations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists schedules_read on public.work_schedules;
create policy schedules_read on public.work_schedules for select to authenticated using (true);
drop policy if exists schedules_admin on public.work_schedules;
create policy schedules_admin on public.work_schedules for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Profil: lihat milik sendiri, admin kelola semua
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists profiles_admin on public.profiles;
create policy profiles_admin on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists emp_loc_read on public.employee_locations;
create policy emp_loc_read on public.employee_locations for select to authenticated
  using (employee_id = auth.uid() or public.is_admin());
drop policy if exists emp_loc_admin on public.employee_locations;
create policy emp_loc_admin on public.employee_locations for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Absensi: hanya lewat RPC check_in/check_out; admin boleh koreksi
drop policy if exists att_read on public.attendances;
create policy att_read on public.attendances for select to authenticated
  using (employee_id = auth.uid() or public.is_admin());
drop policy if exists att_admin on public.attendances;
create policy att_admin on public.attendances for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists att_admin_delete on public.attendances;
create policy att_admin_delete on public.attendances for delete to authenticated
  using (public.is_admin());

-- Pengajuan: karyawan buat & batalkan milik sendiri (status pending);
-- persetujuan lewat RPC review_leave / review_overtime
drop policy if exists leave_read on public.leave_requests;
create policy leave_read on public.leave_requests for select to authenticated
  using (employee_id = auth.uid() or public.is_admin());
drop policy if exists leave_insert on public.leave_requests;
create policy leave_insert on public.leave_requests for insert to authenticated
  with check (employee_id = auth.uid() and status = 'pending' and reviewed_by is null);
drop policy if exists leave_delete on public.leave_requests;
create policy leave_delete on public.leave_requests for delete to authenticated
  using (employee_id = auth.uid() and status = 'pending');

drop policy if exists ot_read on public.overtime_requests;
create policy ot_read on public.overtime_requests for select to authenticated
  using (employee_id = auth.uid() or public.is_admin());
drop policy if exists ot_insert on public.overtime_requests;
create policy ot_insert on public.overtime_requests for insert to authenticated
  with check (employee_id = auth.uid() and status = 'pending'
              and reviewed_by is null and approved_minutes is null);
drop policy if exists ot_delete on public.overtime_requests;
create policy ot_delete on public.overtime_requests for delete to authenticated
  using (employee_id = auth.uid() and status = 'pending');

-- Hak eksekusi RPC: tidak ada fungsi yang bisa dipanggil tanpa login (anon)
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_service_role() from public, anon;
revoke execute on function public._nearest_location(uuid, float8, float8) from public, anon, authenticated;
revoke execute on function public._validate_position(uuid, float8, float8, float8, boolean) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.check_in(float8, float8, float8, boolean, text) from public, anon;
revoke execute on function public.check_out(float8, float8, float8, boolean, text) from public, anon;
revoke execute on function public.review_leave(uuid, boolean, text) from public, anon;
revoke execute on function public.review_overtime(uuid, boolean, int, text) from public, anon;
revoke execute on function public.monthly_recap(date, uuid) from public, anon;

grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.is_service_role() to authenticated, service_role;
grant execute on function public.check_in(float8, float8, float8, boolean, text) to authenticated;
grant execute on function public.check_out(float8, float8, float8, boolean, text) to authenticated;
grant execute on function public.review_leave(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.review_overtime(uuid, boolean, int, text) to authenticated, service_role;
grant execute on function public.monthly_recap(date, uuid) to authenticated, service_role;
