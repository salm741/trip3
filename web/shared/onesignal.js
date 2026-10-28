/* Web Push initialization; works only on HTTPS and a configured OneSignal site/origin. */
(() => {
  const appId = window.SG_CONFIG?.oneSignalAppId;
  window.sgOneSignalReady = new Promise((resolve) => {
    let finished=false; const done=v=>{if(!finished){finished=true;resolve(v)}};
    if(!appId){done(null);return;}
    window.OneSignalDeferred = window.OneSignalDeferred || [];
    window.OneSignalDeferred.push(async function(OneSignal){
      try { await OneSignal.init({appId,allowLocalhostAsSecureOrigin:true,serviceWorkerPath:'./OneSignalSDKWorker.js',serviceWorkerUpdaterPath:'./OneSignalSDKUpdaterWorker.js'}); done(OneSignal); }
      catch(e){ console.warn('OneSignal init:',e); done(null); }
    });
    setTimeout(()=>done(null),8000);
  });
})();
