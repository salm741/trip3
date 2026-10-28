-- TRIP arrival verification and GPS coordinates. Apply after migrations 001-004 in staging first.
alter table public.delivery_requests
  add column if not exists pickup_lat double precision,
  add column if not exists pickup_lng double precision,
  add column if not exists dropoff_lat double precision,
  add column if not exists dropoff_lng double precision;

-- Secure server-side arrival check: current device coordinates must be within 50m of the saved store location.
create or replace function public.confirm_delivery_store_arrival(p_delivery_id uuid,p_lat double precision,p_lng double precision)
returns void language plpgsql security definer set search_path=public as $$
declare d public.delivery_requests%rowtype; dist_m double precision;
begin
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'إحداثيات GPS غير صالحة'; end if;
 select * into d from public.delivery_requests where id=p_delivery_id for update;
 if not found then raise exception 'التوصيلة غير موجودة'; end if;
 if d.driver_id is distinct from auth.uid() then raise exception 'تأكيد الوصول متاح للسائق المعيّن فقط'; end if;
 if d.status<>'accepted' then raise exception 'يجب قبول التوصيلة قبل تأكيد الوصول'; end if;
 if d.pickup_lat is null or d.pickup_lng is null then raise exception 'لم يحفظ المتجر إحداثيات GPS؛ لا يمكن إثبات الوصول ضمن 50 متراً. اطلب من المتجر تثبيت موقعه'; end if;
 dist_m := 6371000 * 2 * asin(sqrt(least(1,power(sin(radians(p_lat-d.pickup_lat)/2),2)+cos(radians(d.pickup_lat))*cos(radians(p_lat))*power(sin(radians(p_lng-d.pickup_lng)/2),2))));
 if dist_m>50 then raise exception 'أنت خارج نطاق المتجر: المسافة %.0f متر. يجب أن تكون ضمن 50 متراً',dist_m; end if;
 update public.delivery_requests set status='store_arrived',store_arrived_at=now(),updated_at=now() where id=p_delivery_id;
end; $$;
revoke all on function public.confirm_delivery_store_arrival(uuid,double precision,double precision) from public,anon;
grant execute on function public.confirm_delivery_store_arrival(uuid,double precision,double precision) to authenticated;

-- Regular trip arrival at passenger pickup is only verifiable if the passenger submitted GPS coordinates.
create or replace function public.confirm_trip_pickup_arrival(p_trip_id uuid,p_lat double precision,p_lng double precision)
returns void language plpgsql security definer set search_path=public as $$
declare t public.trips%rowtype; dist_m double precision;
begin
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'إحداثيات GPS غير صالحة'; end if;
 select * into t from public.trips where id=p_trip_id for update;
 if not found then raise exception 'الرحلة غير موجودة'; end if;
 if t.driver_id is distinct from auth.uid() then raise exception 'تأكيد الوصول متاح للسائق المعيّن فقط'; end if;
 if t.status not in ('accepted','driver_arriving') then raise exception 'حالة الرحلة لا تسمح بتأكيد الوصول'; end if;
 if t.pickup_lat is null or t.pickup_lng is null then raise exception 'لم يثبت الراكب موقع الانطلاق عبر GPS؛ لا يمكن تأكيد الوصول ضمن 50 متراً'; end if;
 dist_m := 6371000 * 2 * asin(sqrt(least(1,power(sin(radians(p_lat-t.pickup_lat)/2),2)+cos(radians(t.pickup_lat))*cos(radians(p_lat))*power(sin(radians(p_lng-t.pickup_lng)/2),2))));
 if dist_m>50 then raise exception 'أنت خارج نطاق موقع الانطلاق: المسافة %.0f متر. يجب أن تكون ضمن 50 متراً',dist_m; end if;
 update public.trips set status='driver_arriving',updated_at=now() where id=p_trip_id;
end; $$;
revoke all on function public.confirm_trip_pickup_arrival(uuid,double precision,double precision) from public,anon;
grant execute on function public.confirm_trip_pickup_arrival(uuid,double precision,double precision) to authenticated;
