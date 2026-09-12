-- ============================================================
--  Masitz-commands | client/main.lua
--
--  Bevidst minimal: /pov, /povdone og /check er registreret SERVER-SIDE
--  (server/pov.lua, server/check.lua), så der er intet client->server
--  event for dem at omgå eller forfalske. Denne fil håndterer
--  udelukkende én ren informationsvisning som ikke kræver noget svar
--  tilbage til serveren - lib.alertDialog kan ikke kaldes server-side.
--
--  Almindelige ox_lib-notifikationer (lib.notify) sendes direkte fra
--  serveren via det allerede eksisterende 'ox_lib:notify'-event
--  (samme mønster som resten af serveren, fx mm-adminpakke), og kræver
--  derfor ingen kode her.
-- ============================================================

RegisterNetEvent('Masitz-commands:client:povAlert', function(data)
    lib.alertDialog({
        header = data.header,
        content = data.content,
        centered = true,
        cancel = false,
    })
end)
