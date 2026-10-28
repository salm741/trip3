# إعداد Capacitor لتطبيق Speed Go

أُضيف إعداد Capacitor إلى هذه الحزمة، مع وضع نسخة واجهة PWA داخل `web/` لتكون مصدر التطبيق الذي يُضمَّن داخل Android.

## ماذا تتضمن الحزمة؟
- `package.json` مع حزم Capacitor Core وCLI وAndroid.
- `capacitor.config.ts` باسم التطبيق `Speed Go` ومعرّف Android `ly.speedgo.app`.
- مجلد `web/` وفيه ملفات واجهة PWA الأساسية وملفات `shared/`.
- ملفات PWA والإدارة وSupabase الموجودة في بقية الحزمة.

## إنشاء مشروع Android وبناء APK
يتطلب هذا الجزء جهاز كمبيوتر مع Node.js وAndroid Studio وAndroid SDK. هذه الحزمة لا تتضمن مجلد Android أصلياً جاهزاً ولا ملف APK مبنياً، لأن ملفات Android يجب توليدها ومزامنتها في بيئة البناء.

1. فك ضغط الملف.
2. افتح Terminal أو موجه الأوامر داخل مجلد الحزمة الرئيسي.
3. نفّذ:
   ```bash
   npm install
   npx cap add android
   npx cap sync android
   npx cap open android
   ```
4. في Android Studio انتظر اكتمال Gradle Sync.
5. من قائمة Build اختر Build APK(s). سيظهر مسار APK داخل سجل البناء أو نافذة الإشعار.

بعد تعديل ملفات واجهة التطبيق، انسخ التعديلات إلى `web/` ثم نفّذ `npx cap sync android` مجدداً.

## تنبيهات مهمة
- لا تضع مفاتيح Supabase السرية أو `service_role` داخل التطبيق. استخدم رابط المشروع ومفتاح `anon/publishable` فقط في الواجهة، وطبّق RLS وسياسات آمنة.
- يجب ضبط قيم Supabase وOneSignal الحقيقية قبل اختبار الخدمات. لا تتضمن الحزمة مفاتيح سرية جاهزة.
- إعداد Capacitor لا يحوّل مكالمات WebRTC أو إشعارات الويب تلقائياً إلى تكاملات Android أصلية كاملة؛ قد تحتاج المكالمات والإشعارات في الخلفية إلى إضافات Android وإعدادات وأذونات واختبار على جهاز فعلي.
- تطبيق الويب المنشور على Cloudflare Pages يظل منفصلاً عن بناء APK. لا ترفع مجلد `android/` إلى Pages على أنه موقع الويب.
