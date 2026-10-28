# Speed Go — بدائل Firebase (حزمة انتقال أولية)

## ما الذي تغيّر؟
- Supabase يبقى قاعدة البيانات وتسجيل الدخول والتخزين والتحديث الفوري ووظائف الخلفية.
- أزلنا إضافة Firebase Gradle ومكتبة Firebase Messaging وخدمة استقبال FCM من مصدر Android.
- أضفنا OneSignal SDK لتسجيل مستخدم Supabase بهوية `external_id` وإرسال إشعارات عبر OneSignal.
- وظيفة `call-control` أصبحت تستخدم OneSignal REST API بدلاً من إرسال FCM مباشرة.
- لم نغيّر اللون البرتقالي أو الوضعين الليلي والنهاري أو بنية واجهة PWA.

## إعداد مطلوب مرة واحدة
1. أنشئ حساب OneSignal المجاني وأنشئ تطبيقًا لمنصة Android. الخطة المجانية حاليًا محدودة إلى 1000 مستخدم نشط شهريًا لإشعارات الهاتف؛ راجع السعر الحالي قبل النشر.
2. ضع OneSignal App ID مكان `REPLACE_WITH_ONESIGNAL_APP_ID` في `Speed_Go_Android_Source/app/src/main/java/com/speedgo/app/MainActivity.java`.
3. في Supabase Edge Function Secrets أضف `ONESIGNAL_APP_ID` و`ONESIGNAL_REST_API_KEY`. لا تضع REST API Key في PWA أو APK.
4. أعد نشر وظيفة `call-control` بعد إضافة الأسرار.
5. ابنِ APK من مجلد `Speed_Go_Android_Source` بعد مزامنة Gradle.
6. سجّل الدخول على هاتفين، وجرّب إشعارًا عاديًا أولًا ثم مكالمة اختبار.

## تنبيه مهم بخصوص Firebase
هذه الحزمة تزيل التكامل المباشر مع Firebase من كود Speed Go، لكنها **لا تضمن إلغاء Firebase/FCM بالكامل من البنية**: إعداد إشعارات Android في OneSignal قد يتطلب بيانات اعتماد FCM في لوحة OneSignal. إذا كان الهدف منع أي اعتماد على خدمات Google نهائيًا، فهناك مسار UnifiedPush/ntfy، لكنه يتطلب إعدادًا إضافيًا واختبارات توافق Android، وقد يستهلك بطارية أكثر.

## حدود الاختبار
- هذه حزمة مصدر معدّلة، وليست APK مبنيًا.
- لم نتمكن من اختبار الإشعارات الفعلية دون OneSignal App ID وREST API Key وجهاز Android مسجّل.
- إشعار المكالمة عبر OneSignal قد يظهر كإشعار عادي؛ فتح شاشة المكالمة تلقائيًا على شاشة القفل ليس مضمونًا في هذه النسخة، ويحتاج تكامل Android خاصًا واختبارًا على الجهاز. لا تعتمد عليها لمكالمات إنتاجية قبل التحقق.
- جداول `call_device_tokens` القديمة في Supabase لم تُحذف حتى لا نفقد بيانات سابقة؛ لن تحتاجها وظيفة الإرسال الجديدة.


**تحديث OneSignal Web Push:** راجع `ONESIGNAL_WEB_PUSH_SETUP_AR.md` في جذر الحزمة لإعداد نطاق HTTPS واختبار الإشعارات.
