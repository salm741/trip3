-- TRIP store-to-driver delivery workflow. This is NOT a customer marketplace/cart.
-- Review and apply in Supabase SQL Editor before using the delivery UI.
create table if not exists public.delivery_requests (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.store_profiles(user_id) on delete restrict,
 driver_id uuid references public.driver_profiles(user_id) on delete set null,
 pickup_address text not null check(length(trim(pickup_address)) between 3 and 300),
 dropoff_address text not null check(length(trim(dropoff_address)) between 3 and 300),
 order_value_lyd numeric(12,2) not null default 0 check(order_value_lyd>=0),
 delivery_fee_lyd numeric(12,2) not null default 0 check(delivery_fee_lyd>=0),
 payment_mode text not null check(payment_mode in ('store_prepaid','driver_collects')),
 status text not null default 'requested' check(status in ('requested','accepted','picked_up','completed','cancelled')),
 finance_note text,
 collected_value_lyd numeric(12,2) not null default 0 check(collected_value_lyd>=0),
 store_settlement_note text,
 completed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(length(coalesce(finance_note,''))<=1000), check(length(coalesce(store_settlement_note,''))<=1000)
);
create index if not exists delivery_requests_store_created_idx on public.delivery_requests(store_id,created_at desc);
create index if not exists delivery_requests_driver_status_idx on public.delivery_requests(driver_id,status,created_at desc);
alter table public.delivery_requests enable row level security;
drop policy if exists delivery_requests_participants_read on public.delivery_requests;
create policy delivery_requests_participants_read on public.delivery_requests for select to authenticated using(store_id=auth.uid() or driver_id=auth.uid() or (status='requested' and exists(select 1 from public.driver_profiles d where d.user_id=auth.uid() and d.approval_status='approved' and d.is_online=true)) or exists(select 1 from public.admin_users a where a.user_id=auth.uid() and a.account_status='active'));
drop policy if exists delivery_requests_store_create on public.delivery_requests;
create policy delivery_requests_store_create on public.delivery_requests for insert to authenticated with check(store_id=auth.uid() and driver_id is null and status='requested' and exists(select 1 from public.store_profiles s where s.user_id=auth.uid() and s.approval_status='approved'));
-- No direct updates: assignment and completion are guarded by SECURITY DEFINER RPCs.
drop policy if exists delivery_requests_store_update on public.delivery_requests;
drop policy if exists delivery_requests_driver_update on public.delivery_requests;
create or replace function public.accept_delivery_request(p_delivery_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from public.driver_profiles where user_id=auth.uid() and approval_status='approved' and is_online=true) then raise exception 'يجب اعتماد السائق وتفعيل حالة الاتصال'; end if;
 update public.delivery_requests set driver_id=auth.uid(),status='accepted',updated_at=now() where id=p_delivery_id and status='requested' and driver_id is null;
 if not found then raise exception 'التوصيلة لم تعد متاحة'; end if;
end; $$;
revoke all on function public.accept_delivery_request(uuid) from public,anon;
grant execute on function public.accept_delivery_request(uuid) to authenticated;
create or replace function public.update_delivery_request(p_delivery_id uuid,p_status text,p_finance_note text default '') returns void language plpgsql security definer set search_path=public as $$
declare d public.delivery_requests%rowtype;
begin
 if p_status not in ('picked_up','completed','cancelled') then raise exception 'حالة التوصيل غير مسموحة'; end if;
 select * into d from public.delivery_requests where id=p_delivery_id for update;
 if not found then raise exception 'التوصيلة غير موجودة'; end if;
 if d.driver_id<>auth.uid() and not exists(select 1 from public.admin_users where user_id=auth.uid() and account_status='active') then raise exception 'غير مصرح لك بتعديل هذه التوصيلة'; end if;
 if p_status='picked_up' and d.status<>'accepted' then raise exception 'يجب قبول التوصيلة أولاً'; end if;
 if p_status='completed' and d.status<>'picked_up' then raise exception 'يجب تأكيد استلام الطلب أولاً'; end if;
 if p_status='cancelled' and d.status not in ('requested','accepted') then raise exception 'لا يمكن إلغاء التوصيلة في هذه المرحلة'; end if;
 update public.delivery_requests set status=p_status,finance_note=case when coalesce(trim(p_finance_note),'')='' then finance_note else left(trim(p_finance_note),1000) end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where id=p_delivery_id;
end; $$;
revoke all on function public.update_delivery_request(uuid,text,text) from public,anon;
grant execute on function public.update_delivery_request(uuid,text,text) to authenticated;
