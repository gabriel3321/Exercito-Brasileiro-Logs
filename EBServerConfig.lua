-- SERVER-ONLY. Coloque este ModuleScript em ServerScriptService.
-- Nunca coloque o segredo em ReplicatedStorage ou LocalScript.

return {
    Logging = {
        Enabled = true,
        ApiBaseUrl = "https://SEU-PROJETO.up.railway.app",
        SharedSecret = "TROQUE_POR_O_MESMO_SEGREDO_DO_RAILWAY",
        BatchSeconds = 2.5,
        MaxBatch = 10,
        MaxQueue = 120,
        HeartbeatSeconds = 20,
    },

    AntiCheat = {
        Enabled = true,
        AutoBan = true,
        SampleInterval = 0.5,
        SpawnGraceSeconds = 8,
        AdminTeleportGraceSeconds = 5,
        MaxGroundRayDistance = 70,
        SuspiciousGroundDistance = 14,
        HoverVerticalSpeed = 5.5,
        HoverSecondsBeforeScore = 2.5,
        WarnScore = 6,
        BanScore = 12,
        ConfirmedTicks = 3,
        ImpossibleMoveStudsPerSample = 95,
    },
}
