/* Intentionally does not create a public STUN/TURN configuration. Production calling needs authenticated short-lived TURN credentials. */
window.sgWebRTC = Object.freeze({configured:false, reason:'يلزم إعداد signaling وخادم TURN خاص وبيانات اعتماد مؤقتة قبل تشغيل المكالمات.'});
