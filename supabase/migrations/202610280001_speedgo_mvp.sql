-- TRIP core schema. Review and run in a development Supabase project before publishing.
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null default 'passenger' check (role in ('passenger','driver','store')),
 display_name text, full_name text, phone text, account_status text not null default 'active' check(account_status in ('active','blocked','pending')),
 approved boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.drivers (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 is_online boolean not null default false, approved boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.trips (
 id uuid primary key default gen_random_uuid(), passenger_id uuid not null references public.profiles(id),
 driver_id uuid references public.profiles(id), pickup_label text not null, dropoff_label text not null,
 status text not null default 'requested' check(status in ('requested','accepted','driver_arriving','in_progress','completed','cancelled')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.driver_wallets (
 driver_id uuid primary key references public.profiles(id) on delete cascade,
 balance_lyd numeric(12,2) not null default 0 check(balance_lyd >= 0), updated_at timestamptz not null default now()
);
create table if not exists public.wallet_codes (
 id uuid primary key default gen_random_uuid(), code_hash text not null unique,
 amount_lyd numeric(12,2) not null check(amount_lyd > 0), expires_at timestamptz not null,
 note text, created_by uuid not null references public.profiles(id), redeemed_by uuid references public.profiles(id), redeemed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.wallet_ledger (
 id uuid primary key default gen_random_uuid(), driver_id uuid not null references public.profiles(id),
 amount_lyd numeric(12,2) not null, entry_type text not null check(entry_type in ('topup','deduction','adjustment')),
 reference_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.admin_users (user_id uuid primary key references public.profiles(id) on delete cascade, created_at timestamptz not null default now());
create table if not exists public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null, notification_type text not null default 'notice', created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,role,display_name,full_name,phone,account_status,approved)
 values(new.id, case when new.raw_user_meta_data->>'role' in ('driver','store') then new.raw_user_meta_data->>'role' else 'passenger' end,
 coalesce(new.raw_user_meta_data->>'display_name',new.raw_user_meta_data->>'full_name'),new.raw_user_meta_data->>'full_name',new.phone,'active',false)
 on conflict(id) do nothing;
 if coalesce(new.raw_user_meta_data->>'role','passenger')='driver' then insert into public.drivers(user_id) values(new.id) on conflict do nothing; end if;
 return new;
end; $$;
drop trigger if exists on_auth_user_created_speedgo on auth.users;
create trigger on_auth_user_created_speedgo after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admin_users where user_id=auth.uid()); $$;

alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.trips enable row level security;
alter table public.driver_wallets enable row level security;
alter table public.wallet_codes enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.admin_users enable row level security;
alter table public.notifications enable row level security;

drop policy if exists profiles_read_self_admin on public.profiles;
create policy profiles_read_self_admin on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
drop policy if exists profiles_update_self_limited on public.profiles;
create policy profiles_update_self_limited on public.profiles for update to authenticated using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
drop policy if exists drivers_read on public.drivers;
create policy drivers_read on public.drivers for select to authenticated using(user_id=auth.uid() or public.is_admin() or approved=true);
drop policy if exists drivers_insert_self on public.drivers;
create policy drivers_insert_self on public.drivers for insert to authenticated with check(user_id=auth.uid());
drop policy if exists drivers_update_self_admin on public.drivers;
create policy drivers_update_self_admin on public.drivers for update to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
drop policy if exists trips_read_participants_admin on public.trips;
create policy trips_read_participants_admin on public.trips for select to authenticated using(passenger_id=auth.uid() or driver_id=auth.uid() or public.is_admin() or (status='requested' and driver_id is null and exists(select 1 from public.drivers d where d.user_id=auth.uid() and d.approved=true)));
drop policy if exists trips_insert_passenger on public.trips;
create policy trips_insert_passenger on public.trips for insert to authenticated with check(passenger_id=auth.uid() and driver_id is null and status='requested');
drop policy if exists wallets_read_owner_admin on public.driver_wallets;
create policy wallets_read_owner_admin on public.driver_wallets for select to authenticated using(driver_id=auth.uid() or public.is_admin());
drop policy if exists ledger_read_owner_admin on public.wallet_ledger;
create policy ledger_read_owner_admin on public.wallet_ledger for select to authenticated using(driver_id=auth.uid() or public.is_admin());
drop policy if exists admins_read_self on public.admin_users;
create policy admins_read_self on public.admin_users for select to authenticated using(user_id=auth.uid());
drop policy if exists notifications_read_self on public.notifications;
create policy notifications_read_self on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_admin());

create or replace function public.accept_trip(p_trip_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_driver public.drivers%rowtype;
begin
 select * into v_driver from public.drivers where user_id=auth.uid() for update;
 if not found or not v_driver.approved or not v_driver.is_online then raise exception 'السائق غير معتمد أو غير متصل'; end if;
 update public.trips set driver_id=auth.uid(),status='accepted',updated_at=now() where id=p_trip_id and status='requested' and driver_id is null;
 if not found then raise exception 'الرحلة لم تعد متاحة'; end if;
end; $$;

create or replace function public.update_trip_status(p_trip_id uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$
declare v public.trips%rowtype;
begin
 if p_status not in ('driver_arriving','in_progress','completed','cancelled') then raise exception 'حالة غير مسموحة'; end if;
 select * into v from public.trips where id=p_trip_id for update;
 if not found then raise exception 'الرحلة غير موجودة'; end if;
 if p_status='cancelled' then
   if auth.uid() not in (v.passenger_id,v.driver_id) and not public.is_admin() then raise exception 'غير مصرح'; end if;
   if v.status in ('completed','cancelled') then raise exception 'لا يمكن إلغاء هذه الرحلة'; end if;
 else
   if v.driver_id<>auth.uid() and not public.is_admin() then raise exception 'غير مصرح'; end if;
   if not ((v.status='accepted' and p_status='driver_arriving') or (v.status in ('accepted','driver_arriving') and p_status='in_progress') or (v.status='in_progress' and p_status='completed')) then raise exception 'تسلسل حالة الرحلة غير صحيح'; end if;
 end if;
 update public.trips set status=p_status,updated_at=now() where id=p_trip_id;
end; $$;

create or replace function public.admin_assign_trip(p_trip_id uuid,p_driver_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'يتطلب صلاحية مدير'; end if;
 if not exists(select 1 from public.drivers where user_id=p_driver_id and approved=true) then raise exception 'السائق غير معتمد'; end if;
 update public.trips set driver_id=p_driver_id,status='accepted',updated_at=now() where id=p_trip_id and status='requested' and driver_id is null;
 if not found then raise exception 'الرحلة لم تعد متاحة'; end if;
end; $$;

create or replace function public.admin_issue_wallet_code(p_amount_lyd numeric,p_expiry_hours integer,p_note text default '') returns jsonb language plpgsql security definer set search_path=public as $$
declare v_code text; v_id uuid;
begin
 if not public.is_admin() then raise exception 'يتطلب صلاحية مدير'; end if;
 if p_amount_lyd<1 or p_amount_lyd>10000 or p_expiry_hours<1 or p_expiry_hours>8760 then raise exception 'القيمة أو مدة الصلاحية غير صحيحة'; end if;
 v_code:=upper(encode(gen_random_bytes(8),'hex'));
 insert into public.wallet_codes(code_hash,amount_lyd,expires_at,note,created_by) values(encode(digest(v_code,'sha256'),'hex'),p_amount_lyd,now()+make_interval(hours=>p_expiry_hours),left(coalesce(p_note,''),200),auth.uid()) returning id into v_id;
 return jsonb_build_object('code',v_code,'amount_lyd',p_amount_lyd,'expires_at',now()+make_interval(hours=>p_expiry_hours),'id',v_id);
end; $$;

create or replace function public.redeem_wallet_code(p_code text) returns numeric language plpgsql security definer set search_path=public as $$
declare v_code public.wallet_codes%rowtype; v_role text;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
 select role into v_role from public.profiles where id=auth.uid();
 if v_role<>'driver' then raise exception 'الشحن مخصص لحساب السائق'; end if;
 select * into v_code from public.wallet_codes where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') for update;
 if not found or v_code.redeemed_at is not null or v_code.expires_at<=now() then raise exception 'الرمز غير صالح أو مستخدم أو منتهي'; end if;
 update public.wallet_codes set redeemed_by=auth.uid(),redeemed_at=now() where id=v_code.id and redeemed_at is null;
 if not found then raise exception 'تم استخدام الرمز بالفعل'; end if;
 insert into public.driver_wallets(driver_id,balance_lyd) values(auth.uid(),v_code.amount_lyd) on conflict(driver_id) do update set balance_lyd=public.driver_wallets.balance_lyd+excluded.balance_lyd,updated_at=now();
 insert into public.wallet_ledger(driver_id,amount_lyd,entry_type,reference_id) values(auth.uid(),v_code.amount_lyd,'topup',v_code.id);
 return v_code.amount_lyd;
end; $$;

revoke all on function public.accept_trip(uuid) from public;
revoke all on function public.update_trip_status(uuid,text) from public;
revoke all on function public.admin_assign_trip(uuid,uuid) from public;
revoke all on function public.admin_issue_wallet_code(numeric,integer,text) from public;
revoke all on function public.redeem_wallet_code(text) from public;
grant execute on function public.accept_trip(uuid) to authenticated;
grant execute on function public.update_trip_status(uuid,text) to authenticated;
grant execute on function public.admin_assign_trip(uuid,uuid) to authenticated;
grant execute on function public.admin_issue_wallet_code(numeric,integer,text) to authenticated;
grant execute on function public.redeem_wallet_code(text) to authenticated;
