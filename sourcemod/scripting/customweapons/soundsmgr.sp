/*
 *  • Overrides the default game shot sound with a custom ones.
 *  •
 */

#if !defined COMPILING_FROM_MAIN
#error "Attemped to compile from the wrong file"
#endif

// 'm_hActiveWeapon' netprop offset.
int m_hActiveWeaponOffset;

void SoundsManagerHooks()
{
    if ((m_hActiveWeaponOffset = FindSendPropInfo("CBasePlayer", "m_hActiveWeapon")) <= 0)
    {
        SetFailState("Failed to find offset 'CBasePlayer::m_hActiveWeapon'");
    }

    // Hook shots temp entity to prevent their sound effect. (CTEFireBullets)
    AddTempEntHook("Shotgun Shot", Hook_OnShotgunShot);
    AddNormalSoundHook(Hook_NormalSound);
}

// Client side.
void SoundsMgr_OnWeaponSwitchPost(int client, int weapon)
{
    CheckPlayerWeaponSounds(client, weapon);
}

void CheckPlayerWeaponSounds(int client, int weapon)
{
    CustomWeaponData custom_weapon_data;

    if (custom_weapon_data.GetMyself(weapon) && custom_weapon_data.HasCustomShotSound())
    {
        if (g_Players[client].default_sounds_enabled)
        {
            CreateToggleDefaultSoundsTimer(client, false);

            g_Players[client].default_sounds_enabled = false;
        }
    }
    else if (!g_Players[client].default_sounds_enabled)
    {
        CreateToggleDefaultSoundsTimer(client, true);

        g_Players[client].default_sounds_enabled = true;
    }
}

void CreateToggleDefaultSoundsTimer(int client, bool value)
{
    // Truncates the old timer. (if exists)
    delete g_Players[client].toggle_sounds_timer;

    // Create a new one!
    DataPack dp;
    g_Players[client].toggle_sounds_timer = CreateDataTimer(GetEntPropFloat(client, Prop_Send, "m_flNextAttack") - GetGameTime() - 0.1, Timer_ToggleDefaultSounds, dp);
    dp.WriteCell(GetClientUserId(client));
    dp.WriteCell(value);
    dp.Reset();
}

Action Timer_ToggleDefaultSounds(Handle timer, DataPack dp)
{
    int client = GetClientOfUserId(dp.ReadCell());
    if (!client)
    {
        return Plugin_Continue;
    }

    g_Players[client].toggle_sounds_timer = null;

    g_Players[client].ToggleDefaultShotSounds(dp.ReadCell());

    return Plugin_Continue;
}

// Server side.
public Action Hook_NormalSound( int clients[MAXPLAYERS],
                                int& numClients,
                                char sample[PLATFORM_MAX_PATH],
                                int& entity,
                                int& channel,
                                float& volume,
                                int& level,
                                int& pitch,
                                int& flags,
                                char soundEntry[PLATFORM_MAX_PATH],
                                int& seed)
{
    int attacker = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

    if (!IsEntityKnife(entity)) 
    {
        return Plugin_Continue;
    }
    
    if (!IsClientConnected(attacker) || !(1 <= attacker <= MaxClients))
    {
        return Plugin_Continue;
    }

    if(!HandleCustomSound(attacker, entity))
    {
        return Plugin_Continue;
    }
    
    return Plugin_Stop;
}

Action Hook_OnShotgunShot(const char[] teName, const int[] players, int numClients, float delay)
{
    int client = TE_ReadNum("m_iPlayer") + 1;

    // Make sure 'client' is between the valid boundaries.
    if (!(1 <= client <= MaxClients))
    {
        return Plugin_Continue;
    }

    int weapon = GetEntDataEnt2(client, m_hActiveWeaponOffset);

    // Weapon is unavailable?
    if (weapon == -1)
    {
        return Plugin_Continue;
    }

    if(!HandleCustomSound(client, weapon))
    {
        return Plugin_Continue;
    }

    // Block the original sound
    return Plugin_Stop;
}

bool HandleCustomSound(int client, int weapon)
{
    // Try to retrieve and validate the weapon customization data.
    // If it failed, that means that there are no customizations applied on this weapon.
    CustomWeaponData custom_weapon_data;
    if (!custom_weapon_data.GetMyself(weapon) || !custom_weapon_data.HasCustomShotSound())
    {
        return false;
    }

    if (Call_OnSound(client, weapon, custom_weapon_data.shot_sound) >= Plugin_Handled)
    {
        g_Players[client].ToggleDefaultShotSounds(true);

        g_Players[client].default_sounds_enabled = false;

        return false;
    }

    float origin[3];
    GetClientAbsOrigin(client, origin);

    EmitShotSound(custom_weapon_data.shot_sound, client, origin, 0.2);

    return true;
}

// Wraps between game sounds and third party sounds.
void EmitShotSound(const char[] sound, int entity, float origin[3], float vol)
{
    int channel;
    int level;
    float volume;
    int pitch;

    char sample[PLATFORM_MAX_PATH];

    if (GetGameSoundParams(sound, channel, level, volume, pitch, sample, sizeof(sample), entity))
    {
        EmitSoundToAll(sample, entity, .channel = channel, .level = level, .volume = vol, .pitch = pitch);
    }
    else
    {
        strcopy(sample, sizeof(sample), sound);

        EmitAmbientSound(sample, .pos = origin, .entity = entity, .vol = vol);
    }
}