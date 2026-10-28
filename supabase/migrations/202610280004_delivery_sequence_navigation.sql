-- TRIP store dispatch sequence, recipient details, navigation and accountability milestones.
-- Apply after 202610280003_store_delivery_settlement.sql; test in development first.
alter table public.delivery_requests
  add column if not exists batch_id uuid,
  add column if not exists stop_sequence integer not null default 1 check(stop_sequence between 1 and 30),
  add column if not exists batch_count integer not null default 1 check(batch_count between 1 and 30),
  add column if not exists item_description text,
  add column if not exists item_quantity integer not null default 1 check(item_quantity between 1 and 10000),
  add column if not exists recipient_phone text,
  add column if not exists delivery_fee_prepaid boolean not null default false,
  add column if not exists store_arrived_at timestamptz,
  add column if not exists goods_document_confirmed_at timestamptz,
  add column if not exists document_returned_at timestamptz,
  add column if not exists settlement_closed_at timestamptz,
  add column if not exists settlement_note text;

alter table public.delivery_requests drop constraint if exists delivery_requests_status_check;
alter table public.delivery_requests add constraint delivery_requests_status_check
 check(status in ('requested','accepted','store_arrived','picked_up','completed','document_returned','settled','cancelled'));
create index if not exists delivery_requests_batch_sequence_idx on public.delivery_requests(batch_id,stop_sequence);
create index if not exists delivery_requests_store_sequence_idx on public.delivery_requests(store_id,created_at desc,stop_sequence);

create or replace function public.update_delivery_request(p_delivery_id uuid,p_status text,p_finance_note text default '')
returns void language plpgsql security definer set search_path=public as $$
declare d public.delivery_requests%rowtype;
begin
 if p_status not in ('store_arrived','picked_up','completed','document_returned','settled','cancelled') then raise exception 'حالة التوصيل غير مسموحة'; end if;
 select * into d from public.delivery_requests where id=p_delivery_id for update;
 if not found then raise exception 'التوصيلة غير موجودة'; end if;
 if d.driver_id<>auth.uid() and d.store_id<>auth.uid() and not exists(select 1 from public.admin_users where user_id=auth.uid() and account_status='active') then raise exception 'غير مصرح لك بتعديل هذه التوصيلة'; end if;
 if p_status='store_arrived' and (d.driver_id<>auth.uid() or d.status<>'accepted') then raise exception 'يجب أن يكون السائق قد قبل التوصيلة قبل تأكيد الوصول'; end if;
 if p_status='picked_up' and (d.driver_id<>auth.uid() or d.status<>'store_arrived') then raise exception 'أكد الوصول إلى المتجر أولاً'; end if;
 if p_status='completed' and (d.driver_id<>auth.uid() or d.status<>'picked_up') then raise exception 'يجب تأكيد استلام البضاعة أولاً'; end if;
 if p_status='document_returned' and (d.store_id<>auth.uid() or d.status<>'completed') then raise exception 'يؤكد المتجر استلام المستند بعد اكتمال التوصيل'; end if;
 if p_status='settled' and (d.store_id<>auth.uid() or d.status not in ('completed','document_returned')) then raise exception 'لا يمكن إقفال التسوية قبل اكتمال التوصيلة'; end if;
 if p_status='cancelled' and (d.store_id<>auth.uid() and d.driver_id<>auth.uid()) then raise exception 'غير مصرح بالإلغاء'; end if;
 if p_status='cancelled' and d.status not in ('requested','accepted') then raise exception 'لا يمكن إلغاء التوصيلة في هذه المرحلة'; end if;
 update public.delivery_requests set
   status=p_status,
   store_arrived_at=case when p_status='store_arrived' then now() else store_arrived_at end,
   goods_document_confirmed_at=case when p_status='picked_up' then now() else goods_document_confirmed_at end,
   completed_at=case when p_status='completed' then now() else completed_at end,
   document_returned_at=case when p_status='document_returned' then now() else document_returned_at end,
   settlement_closed_at=case when p_status='settled' then now() else settlement_closed_at end,
   settlement_note=case when coalesce(trim(p_finance_note),'')<>'' then left(trim(p_finance_note),1000) else settlement_note end,
   finance_note=case when coalesce(trim(p_finance_note),'')<>'' then left(trim(p_finance_note),1000) else finance_note end,
   updated_at=now()
 where id=p_delivery_id;
end; $$;
revoke all on function public.update_delivery_request(uuid,text,text) from public,anon;
grant execute on function public.update_delivery_request(uuid,text,text) to authenticated;
