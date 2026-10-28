# Speed Go — Unified Latest Release

This ZIP combines the latest OneSignal Web Push rider/driver PWA and Android source with the latest combined admin/security/API release.

## Cloudflare Pages
- The primary site entry point is `index.html` at this ZIP's root.
- For a static HTML deployment with no build step, use Framework preset `None`, Build command `exit 0` (or leave blank if your setup accepts it), and Build output directory `.`.
- The admin/security/API combined release is preserved under `integration-release/`; its admin PWA is at `integration-release/admin/admin-pwa/index.html`. To serve that admin UI at a clean `/admin/` URL, copy the contents of that admin-pwa folder into an `admin/` folder at the root before deploying, or configure a separate Pages project.

## Important
- This is a merged source package, not a verified production deployment or built APK.
- Review the Supabase URL and public publishable key configuration before use; the current project key is included in both shared config files. Never put `service_role` keys or OneSignal REST API secrets in client files.
- Follow `ONESIGNAL_WEB_PUSH_SETUP_AR.md` and the included Arabic README/checklist files.
- Apply database migrations only after reviewing them against the current Supabase schema and backup.

## إضافة Capacitor
أضيف إعداد Capacitor في `package.json` و`capacitor.config.ts`، ونسخة واجهة PWA المخصصة للتضمين داخل `web/`. راجع `CAPACITOR_SETUP_AR.md` لخطوات إنشاء مشروع Android وبناء APK. الحزمة تحتوي إعداد Capacitor لكنها لا تحتوي APK جاهزاً ولا مجلد Android مولداً.
