# إكمال ربط OneSignal Web Push في Speed Go

## ما أُضيف إلى هذه الحزمة
- تهيئة OneSignal Web SDK باستخدام App ID العام: `55de0609-2a3a-4eb3-92e0-7685d64fb959`.
- تسجيل مستخدم الويب تحت `external_id` المطابق لمعرّف Supabase Auth بعد تسجيل الدخول.
- زر يطلب إذن الإشعارات بعد ضغط المستخدم، وزر تسجيل الخروج يفصل هوية OneSignal.
- ملفات Service Worker الخاصة بـ OneSignal في جذر PWA.
- نُسخت التعديلات نفسها إلى نسخة الويب داخل مصدر Android.

## يلزم ضبطه في لوحة OneSignal
1. في Web Push، أضف عنوان النطاق الحقيقي الذي يستضيف PWA (HTTPS). يجب أن يطابق النطاق الذي سيُفتح منه التطبيق؛ لا يكفي `file://` أو معاينة Replit بعنوان مختلف.
2. تأكد من إعداد Web Push وتهيئة المتصفح/المتصفح المدعوم، ثم انشر ملفات PWA بما فيها `OneSignalSDKWorker.js` و`OneSignalSDKUpdaterWorker.js` في جذر النطاق.
3. افتح PWA عبر HTTPS، سجّل الدخول، ثم من الإعدادات اضغط «تفعيل إشعارات المكالمات والرحلات» واسمح بالإشعارات.
4. تحقق من ظهور الاشتراك في OneSignal، ثم أرسل إشعار اختبار.

## Android
- Android يستخدم OneSignal SDK الأصلي عبر `MainActivity.java` وواجهة `SpeedGoNative`، وليس Web Push داخل WebView.
- عند بناء APK، أضف إلى ملف `gradle.properties` المحلي: `onesignalAppId=55de0609-2a3a-4eb3-92e0-7685d64fb959` ثم نفّذ Gradle Sync/Build.
- لا تضع `ONESIGNAL_REST_API_KEY` في التطبيق أو ملفات PWA/Android. يبقى سرًا في Supabase Edge Function Secrets فقط.
- إعداد Android في OneSignal قد يتطلب إعداد Firebase/FCM credentials في لوحة OneSignal حتى تصل إشعارات Android.

## حدود الاختبار
هذه تعديلات مصدرية ولم يُجر اختبار إشعار حي من جهاز/نطاق منشور في هذه البيئة. لا تعتبر الإشعارات ناجحة حتى يظهر اشتراك الجهاز وتنجح رسالة اختبار.
