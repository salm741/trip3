-- TRIP: delivery payment, recipient geofence, optional trust document and photo evidence.
-- Apply migrations 003, 004 and 005 first. Review this migration in development before production.
alter table public.delivery_requests
 add column if not exists trust_document_required boolean not null default false,
 add column if not exists trust_document_description text,
 add column if not exists trust_document_photo_path text,
 add column if not exists driver_document_description text,
 add column if not exists driver_document_photo_path text,
 add column if not exists store_document_description text,
 add column if not exists store_document_photo_path text,
 add column if not exists recipient_arrived_at timestamptz,
 add column if not exists recipient_arrival_lat double precision,
 add column if not exists recipient_arrival_lng double precision,
 add column if not exists customer_payment_confirmed boolean,
 add column if not exists customer_payment_confirmed_at timestamptz,
 add column if not exists customer_payment_confirmed_by uuid,
 add column if not exists delivery_confirmed boolean,
 add column if not exists delivery_confirmed_at timestamptz,
 add column if not exists delivery_confirmed_by uuid,
 add column if not exists driver_document_returned boolean,
 add column if not exists driver_document_returned_at timestamptz,
 add column if not exists store_document_received boolean,
 add column if not exists store_document_received_at timestamptz,
 add column if not exists settlement_confirmed boolean,
 add column if not exists settlement_confirmed_at timestamptz,
 add column if not exists settlement_confirmed_by uuid,
 add column if not exists milestone_log jsonb not null default '[]'::jsonb;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('delivery-evidence','delivery-evidence',false,8388608,array['image/jpeg','image/png','image/webp','image/heic'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp','image/heic'];
drop policy if exists delivery_evidence_participant_read on storage.objects;
create policy delivery_evidence_participant_read on storage.objects for select to authenticated using(bucket_id='delivery-evidence' and exists(select 1 from public.delivery_requests d where d.id::text=(storage.foldername(name))[1] and (d.store_id=auth.uid() or d.driver_id=auth.uid() or exists(select 1 from public.admin_users a where a.user_id=auth.uid() and a.account_status='active'))));
drop policy if exists delivery_evidence_participant_insert on storage.objects;
create policy delivery_evidence_participant_insert on storage.objects for insert to authenticated with check(bucket_id='delivery-evidence' and (storage.foldername(name))[2]=auth.uid()::text and exists(select 1 from public.delivery_requests d where d.id::text=(storage.foldername(name))[1] and (d.store_id=auth.uid() or d.driver_id=auth.uid())));

create or replace function public.set_delivery_trust_document(p_delivery_id uuid,p_description text,p_photo_path text default null)
returns void language plpgsql security definer set search_path=public as $$
declare d public.delivery_requests%rowtype;
begin
 select * into d from public.delivery_requests where id=p_delivery_id for update;
 if not found or d.store_id<>auth.uid() then raise exception 'غير مصرح: الطلب ليس تابعاً لمتجرك'; end if;
 if d.status<>'requested' then raise exception 'لا يمكن تغيير سند الأمانة بعد قبول الطلب'; end if;
 if not d.trust_document_required then raise exception 'المتجر لم يشترط سند أمانة لهذا الطلب'; end if;
 if coalesce(trim(p_description),'')='' then raise exception 'أدخل وصف سند الأمانة'; end if;
 if p_photo_path is not null and split_part(p_photo_path,'/',1)<>p_delivery_id::text then raise exception 'مسار الصورة غير صالح'; end if;
 update public.delivery_requests set trust_document_description=left(trim(p_description),500),trust_document_photo_path=coalesce(p_photo_path,trust_document_photo_path),updated_at=now() where id=p_delivery_id;
end; $$;
revoke all on function public.set_delivery_trust_document(uuid,text,text) from public,anon;
grant execute on function public.set_delivery_trust_document(uuid,text,text) to authenticated;

create or replace function public.record_delivery_milestone(p_delivery_id uuid,p_action text,p_answer boolean,p_description text default '',p_photo_path text default null,p_lat double precision default null,p_lng double precision default null)
returns void language plpgsql security definer set search_path=public as $$
declare d public.delivery_requests%rowtype; dist double precision; ev jsonb;
begin
 select * into d from public.delivery_requests where id=p_delivery_id for update;
 if not found then raise exception 'التوصيلة غير موجودة'; end if;
 if auth.uid() is null or (auth.uid()<>d.driver_id and auth.uid()<>d.store_id and not exists(select 1 from public.admin_users where user_id=auth.uid() and account_status='active')) then raise exception 'غير مصرح لك'; end if;
 if p_action not in ('recipient_arrival','payment','delivery','driver_document_return','store_document_received','settlement') then raise exception 'خطوة غير مسموحة'; end if;
 if p_photo_path is not null and (split_part(p_photo_path,'/',1)<>p_delivery_id::text or split_part(p_photo_path,'/',2)<>auth.uid()::text) then raise exception 'مسار صورة الإثبات غير صالح'; end if;
 if p_action='recipient_arrival' then
   if auth.uid()<>d.driver_id then raise exception 'تأكيد الوصول للمستلم متاح للسائق فقط'; end if;
   if d.status<>'picked_up' then raise exception 'يجب استلام البضاعة من المتجر أولاً'; end if;
   if d.dropoff_lat is null or d.dropoff_lng is null then raise exception 'يجب أن يثبت المتجر موقع المستلم أولاً'; end if;
   if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'إحداثيات GPS غير صالحة'; end if;
   dist:=6371000*2*asin(sqrt(power(sin(radians(p_lat-d.dropoff_lat)/2),2)+cos(radians(d.dropoff_lat))*cos(radians(p_lat))*power(sin(radians(p_lng-d.dropoff_lng)/2),2)));
   if dist>50 then raise exception 'أنت خارج نطاق 50 متراً من موقع المستلم (%.1f م)',dist; end if;
   if p_answer then update public.delivery_requests set recipient_arrived_at=now(),recipient_arrival_lat=p_lat,recipient_arrival_lng=p_lng,updated_at=now() where id=p_delivery_id; end if;
 elsif p_action='payment' then
   if auth.uid()<>d.driver_id then raise exception 'تأكيد الدفع متاح للسائق فقط'; end if;
   if d.status not in ('picked_up','completed','document_returned','settled') then raise exception 'الدفع يؤكد بعد استلام الطلب'; end if;
   if p_answer then update public.delivery_requests set customer_payment_confirmed=true,customer_payment_confirmed_at=now(),customer_payment_confirmed_by=auth.uid(),updated_at=now() where id=p_delivery_id;
   else update public.delivery_requests set customer_payment_confirmed=false,customer_payment_confirmed_at=now(),customer_payment_confirmed_by=auth.uid(),updated_at=now() where id=p_delivery_id; end if;
 elsif p_action='delivery' then
   if auth.uid()<>d.driver_id then raise exception 'تأكيد التسليم متاح للسائق فقط'; end if;
   if d.status not in ('picked_up','completed') then raise exception 'حالة التوصيلة لا تسمح بتأكيد التسليم'; end if;
   if p_answer and d.recipient_arrived_at is null then raise exception 'أكد الوصول ضمن 50 متراً أولاً'; end if;
   if p_answer and d.payment_mode='driver_collects' and coalesce(d.customer_payment_confirmed,false)=false then raise exception 'أكد استلام الدفع من العميل أولاً'; end if;
   if p_answer then update public.delivery_requests set delivery_confirmed=true,delivery_confirmed_at=now(),delivery_confirmed_by=auth.uid(),status='completed',completed_at=coalesce(completed_at,now()),updated_at=now() where id=p_delivery_id;
   else update public.delivery_requests set delivery_confirmed=false,delivery_confirmed_at=now(),delivery_confirmed_by=auth.uid(),updated_at=now() where id=p_delivery_id; end if;
 elsif p_action='driver_document_return' then
   if auth.uid()<>d.driver_id then raise exception 'توثيق إرجاع السند متاح للسائق فقط'; end if;
   if not d.trust_document_required then raise exception 'لا يوجد سند أمانة مطلوب'; end if;
   if not p_answer then raise exception 'لا يمكن تأكيد الإرجاع بلا؛ سجّل الحالة كمسألة معلقة لدى الإدارة'; end if;
   if coalesce(trim(p_description),'')='' or p_photo_path is null then raise exception 'أدخل وصف السند الم returned وارفق صورة إثبات'; end if;
   update public.delivery_requests set driver_document_returned=true,driver_document_returned_at=now(),driver_document_description=left(trim(p_description),1000),driver_document_photo_path=p_photo_path,updated_at=now() where id=p_delivery_id;
 elsif p_action='store_document_received' then
   if auth.uid()<>d.store_id then raise exception 'تأكيد استلام السند متاح للمتجر فقط'; end if;
   if not d.trust_document_required or not coalesce(d.driver_document_returned,false) then raise exception 'يجب أن يوثق السائق إرجاع السند أولاً'; end if;
   if not p_answer then raise exception 'لم يؤكد المتجر استلام السند؛ تبقى التسوية معلقة'; end if;
   if coalesce(trim(p_description),'')='' or p_photo_path is null then raise exception 'أدخل وصف الاستلام وارفق صورة إثبات'; end if;
   update public.delivery_requests set store_document_received=true,store_document_received_at=now(),store_document_description=left(trim(p_description),1000),store_document_photo_path=p_photo_path,updated_at=now() where id=p_delivery_id;
 elsif p_action='settlement' then
   if auth.uid()<>d.store_id then raise exception 'تأكيد التسوية متاح للمتجر فقط'; end if;
   if not coalesce(d.delivery_confirmed,false) then raise exception 'تأكيد التسليم مطلوب قبل التسوية'; end if;
   if d.payment_mode='driver_collects' and coalesce(d.customer_payment_confirmed,false) is distinct from true then raise exception 'يجب تأكيد دفع العميل أولاً'; end if;
   if d.trust_document_required and not coalesce(d.store_document_received,false) then raise exception 'استلام سند الأمانة مطلوب قبل التسوية'; end if;
   if not p_answer then raise exception 'التسوية غير مؤكدة؛ تبقى التوصيلة مفتوحة'; end if;
   update public.delivery_requests set settlement_confirmed=true,settlement_confirmed_at=now(),settlement_confirmed_by=auth.uid(),status='settled',settlement_closed_at=now(),settlement_note=left(coalesce(trim(p_description),''),1000),updated_at=now() where id=p_delivery_id;
 end if;
 ev:=jsonb_build_object('action',p_action,'answer',p_answer,'description',left(coalesce(p_description,''),1000),'photo_path',p_photo_path,'actor_id',auth.uid(),'created_at',now());
 update public.delivery_requests set milestone_log=coalesce(milestone_log,'[]'::jsonb)||jsonb_build_array(ev),updated_at=now() where id=p_delivery_id;
end; $$;
revoke all on function public.record_delivery_milestone(uuid,text,boolean,text,text,double precision,double precision) from public,anon;
grant execute on function public.record_delivery_milestone(uuid,text,boolean,text,text,double precision,double precision) to authenticated;
