/* Call feature status: safe scaffold only. Native call UI, signaling, TURN credentials and server authorization are not configured by this file. */
(() => {
  window.sgCalls = {
    async registerAndroidDevice(){
      if (!window.Capacitor?.isNativePlatform?.()) return false;
      throw new Error('مكوّن المكالمات الأصلي لم يُدمج أو يُختبر بعد.');
    },
    async startCall(){ throw new Error('المكالمات غير مفعّلة بعد: يلزم signaling آمن وخادم TURN ومكوّن Android أصلي.'); }
  };
})();
