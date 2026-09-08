/* ══════════════════════════════════════════════════════════
   api.js — single point of contact with the Lua client.

   Every NUI callback the Lua side registers is fire-and-forget: it
   always calls cb('ok') immediately, and the actual result (if any)
   arrives later as a separate postMessage event (syncData,
   leaderboardData, profileImage, ...). Api.call therefore only needs
   to guard against the fetch() itself failing (e.g. NUI not ready
   yet) — real gameplay errors are surfaced via ox_lib notifications
   from the server, and any failure here is a genuine "something is
   wrong with the UI" case that has to be visible in the UI itself
   per the "central error handling" requirement.
   ══════════════════════════════════════════════════════════ */

var Api = (function() {
    var RESOURCE_NAME = (function() {
        var fn = window.GetParentResourceName;
        return (typeof fn === 'function') ? fn() : 'mm-christmas';
    })();

    function call(endpoint, data) {
        return fetch('https://' + RESOURCE_NAME + '/' + endpoint, {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify(data || {}),
        }).catch(function() {
            Toast.show('Noget gik galt. Prøv igen.', 'error');
            return null;
        });
    }

    return { call: call, RESOURCE_NAME: RESOURCE_NAME };
})();
