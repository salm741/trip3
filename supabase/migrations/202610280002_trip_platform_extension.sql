-- TRIP platform extension (apply after 202610280001_speedgo_mvp.sql). Review against existing schema first.
create table if not exists public.account_devices (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 device_id text not null, device_label text, platform text not null default 'web' check(platform in ('web','android','ios','windows')),
 last_seen_at timestamptz not null default now(), created_at timestamptz not null default now(), unique(user_id,device_id)
);
create table if not exists public.stores (
 user_id uuid primary key references public.profiles(id) on delete cascade, store_name text not null, approved boolean not null default false,
 phone text, address text, created_at timestamptz not null default now()
);
create table if not exists public.store_products (
 id uuid primary key default gen_random_uuid(), store_id uuid not null references public.stores(user_id) on delete cascade,
 name text not null, description text, price_lyd numeric(12,2) not null check(price_lyd>=0), available boolean not null default true,
 image_path text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.delivery_orders (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.profiles(id), store_id uuid references public.stores(user_id),
 driver_id uuid references public.profiles(id), status text not null default 'requested' check(status in ('requested','accepted','picked_up','in_progress','completed','cancelled')),
 pickup_label text, dropoff_label text not null, total_lyd numeric(12,2) not null default 0 check(total_lyd>=0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.archive_hosts (
 id uuid primary key default gen_random_uuid(), device_id text not null unique, label text not null, platform text not null default 'windows',
 is_primary boolean not null default false, last_seen_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.archive_items (
 id uuid primary key default gen_random_uuid(), host_id uuid references public.archive_hosts(id) on delete set null, entity_type text not null, entity_id text not null,
 relative_path text not null, sha256 text, byte_size bigint, verified_at timestamptz, created_at timestamptz not null default now(), unique(entity_type,entity_id,relative_path)
);
create table if not exists public.audit_events (
 id bigint generated always as identity primary key, actor_id uuid references public.profiles(id) on delete set null, action text not null,
 entity_type text, entity_id text, details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

alter table public.account_devices enable row level security;
alter table public.stores enable row level security;
alter table public.store_products enable row level security;
alter table public.delivery_orders enable row level security;
alter table public.archive_hosts enable row level security;
alter table public.archive_items enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists account_devices_self_admin on public.account_devices;
create policy account_devices_self_admin on public.account_devices for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists account_devices_write_self on public.account_devices;
create policy account_devices_write_self on public.account_devices for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
drop policy if exists stores_read_public_approved on public.stores;
create policy stores_read_public_approved on public.stores for select to authenticated using(approved=true or user_id=auth.uid() or public.is_admin());
drop policy if exists stores_write_owner_admin on public.stores;
create policy stores_write_owner_admin on public.stores for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
drop policy if exists products_read_available on public.store_products;
create policy products_read_available on public.store_products for select to authenticated using(available=true or exists(select 1 from public.stores s where s.user_id=store_id and (s.user_id=auth.uid() or public.is_admin())));
drop policy if exists products_owner_admin on public.store_products;
create policy products_owner_admin on public.store_products for all to authenticated using(exists(select 1 from public.stores s where s.user_id=store_id and (s.user_id=auth.uid() or public.is_admin()))) with check(exists(select 1 from public.stores s where s.user_id=store_id and (s.user_id=auth.uid() or public.is_admin())));
drop policy if exists delivery_orders_participants_admin on public.delivery_orders;
create policy delivery_orders_participants_admin on public.delivery_orders for select to authenticated using(customer_id=auth.uid() or driver_id=auth.uid() or store_id=auth.uid() or public.is_admin());
drop policy if exists delivery_orders_customer_create on public.delivery_orders;
create policy delivery_orders_customer_create on public.delivery_orders for insert to authenticated with check(customer_id=auth.uid() and status='requested');
drop policy if exists archive_hosts_admin_only on public.archive_hosts;
create policy archive_hosts_admin_only on public.archive_hosts for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists archive_items_admin_only on public.archive_items;
create policy archive_items_admin_only on public.archive_items for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists audit_events_admin_read on public.audit_events;
create policy audit_events_admin_read on public.audit_events for select to authenticated using(public.is_admin());

-- Authenticated users may only use their own role; promotion to admin/approval must be performed by a trusted administrator.
create or replace function public.admin_set_driver_approval(p_driver_id uuid,p_approved boolean) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'يتطلب صلاحية مدير'; end if;
 update public.drivers set approved=p_approved,updated_at=now() where user_id=p_driver_id;
 if not found then raise exception 'السائق غير موجود'; end if;
 update public.profiles set approved=p_approved,account_status=case when p_approved then 'active' else 'pending' end,updated_at=now() where id=p_driver_id;
 insert into public.audit_events(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'driver_approval','driver',p_driver_id::text,jsonb_build_object('approved',p_approved));
end; $$;
revoke all on function public.admin_set_driver_approval(uuid,boolean) from public;
grant execute on function public.admin_set_driver_approval(uuid,boolean) to authenticated;

-- Prevent users from promoting themselves or approving their own accounts through profiles UPDATE.
create or replace function public.protect_profile_privileged_fields() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is not null and not public.is_admin() then
   if new.role is distinct from old.role then raise exception 'تغيير نوع الحساب يتطلب إجراء موافقة موثوق'; end if;
   if new.approved is distinct from old.approved then raise exception 'اعتماد الحساب من صلاحية الإدارة فقط'; end if;
   if new.account_status is distinct from old.account_status then raise exception 'تغيير حالة الحساب من صلاحية الإدارة فقط'; end if;
 end if;
 new.updated_at:=now();
 return new;
end; $$;
drop trigger if exists protect_profile_privileged_fields on public.profiles;
create trigger protect_profile_privileged_fields before update on public.profiles for each row execute function public.protect_profile_privileged_fields();
