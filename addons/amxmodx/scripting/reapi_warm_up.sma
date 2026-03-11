#include <amxmisc>
#include <fakemeta>
#include <fun>
#include <reapi>

#define PLUGIN "[ReAPI] Warm UP"
#define VERSION "1.0-10.03.2026"
#define AUTHOR "Emma Jule, WAW555, CODEX"
#define URL "None"
#define DESCRIPTIONPLUGIN "Plugin for Warm Up"

new const WARMUP_CONFIG_FILE[] = "configs/plugins/warm_up.ini"; // Путь к файлу конфигурации относительно папки amxmodx

#define IsPlayer(%1)    (1 <= %1 && %1 <= g_iMaxPlayers)	//	Проверяем, что это игрок,  а не какой либо объект.
#define ClearArr(%1)    arrayset(_:%1, _:0.0, sizeof(%1))	//	Очищаем массив
#define MAX_ARTIST_NAME_LEN 50
#define MAX_TRACK_NAME_LEN 50
#define MAX_TRACK_TITLE_LEN (MAX_ARTIST_NAME_LEN + MAX_TRACK_NAME_LEN + 3)

#define TE_BEAMCYLINDER 21
#define TASK_HIGHLIGHT_LEADER 31415

enum _:ePlayerData
{
	PLAYER_ID,
	DAMAGE,
	KILLS,
	AWARD
};

enum (+=1)
{
	NULL = -1,
	VARIABLES,
	PLUGINS,
	WEAPS,
	MUSIC_FILES,
};

enum _:WARM_STRUCT
{
	GUNS[128],
	DESCRIPTION[64],
	Float:HEALTH,
	Float:PROTECTION_TIME,
	Float:RESPAWN_TIME,
	TIME,
	KEVLAR,
	FALL_DAMAGE,
	MUSIC[MAX_RESOURCE_PATH_LENGTH],
	TRACK[64],
};

enum _:CVARS
{
	RESTART,
	AUTO_AMMO,
	PAUSE_STATS,
};

new const g_eCvarsToDisable[][][] =
{
	{ "mp_maxmoney", "0" },
	{ "mp_freezetime", "0" },
	{ "mp_item_staytime", "0.0" },
	{ "mp_round_infinite", "1" },
	{ "mp_refill_bpammo_weapons", "3" },
	{ "mp_infinite_ammo", "2" },
	{ "mp_hostage_hurtable", "0" },
	{ "mp_give_player_c4", "0" },
	{ "mp_weapons_allow_map_placed", "0" },
	{ "mp_scoreboard_showmoney", "-1" },
	{ "mp_scoreboard_showhealth", "-1" },
	
	// Backwards
	{ "mp_free_armor", "0" },
	{ "mp_forcerespawn", "0" },
	{ "mp_respawn_immunitytime", "0.0" },
	{ "mp_infinite_grenades", "0" },
	{ "mp_t_give_player_knife", "0" },
	{ "mp_ct_give_player_knife", "0" },
	{ "mp_t_default_weapons_primary", "" },
	{ "mp_ct_default_weapons_primary", "" },
	{ "mp_t_default_weapons_secondary", "" },
	{ "mp_ct_default_weapons_secondary", "" },
	{ "mp_t_default_grenades", "" },
	{ "mp_ct_default_grenades", "" },
	{ "mp_falldamage", "0" },
};

new Array:g_aWarm, Array:g_aPlugins, Array:g_aMusicFilesOnDisk;
new Trie:g_tMusicTitle, Trie:g_tMusicDuration, Trie:g_tKnownMusicFiles;
new HookChain:g_hCheckMapConditions, HookChain:g_hDropPlayerItem, HookChain:g_hOnSpawnEquip, HookChain:g_hKilled;

new g_pDefaultCvars[sizeof(g_eCvarsToDisable)][64], g_pCvar[CVARS];
new g_szWarmUpDescription[64], g_szWarmUpTrack[MAX_TRACK_TITLE_LEN + 1], g_szMapWarmUpMusic[MAX_RESOURCE_PATH_LENGTH], g_szWarmUpMusicDir[MAX_RESOURCE_PATH_LENGTH] = "ms/Warm_Up", g_szWarmUpTimeMode[16] = "AUTO", Float:g_flMaxHealth, g_iCountDown, g_iWarmUpTrackTime, g_iSection;
new g_szWarmUpWeaponSprites[32][24], g_iWarmUpWeaponSpritesCount;
new g_szWarmUpConfigPath[PLATFORM_MAX_PATH];

/* top 5*/
new g_arrData[MAX_PLAYERS + 1][ePlayerData];
new g_iPlayerDmg[MAX_PLAYERS + 1];
new g_iPlayerKills[MAX_PLAYERS + 1];
new g_iPlayerAward[MAX_PLAYERS + 1];
new g_iMaxPlayers;
new g_iCounter = 0;	//	Счетчик для тайминга отображения победителей
new g_iOriginal_sv_maxspeed = 320;	//	Скорость по умолчанию
new cvar_name_sv_maxspeed;
new g_iPlayerTop = 0;
new g_iTopPlayersCount = 0;
new g_iRingSprite;
new bool:g_bFirstKillHappened;
new g_iWarmupLeader;
new g_iHighlightedLeader;
new bool:g_bHighlightRingEnabled = true;
new bool:g_bHighlightModelEnabled = true;
new Float:g_flHighlightInterval = 5.0;
new Float:g_flHighlightRadius = 85.0;
new Float:g_flHighlightHeight = 0.0;
new g_iHighlightColor[3] = {255, 0, 0};
new g_iHighlightModelColor[3] = {255, 0, 0};
new g_iWarmupResultsFadeAlpha = 180;
new g_iMsgScreenFade;
new g_iMsgStatusIcon;
new bool:g_bWarmupRestartPending;
new bool:g_bWarmupCompleted;
new bool:g_bWarmupWeaponSpriteEnabled = true;
new g_iWarmupWeaponSpriteColor[3] = {0, 160, 0};
new bool:g_bLeaderModeEnabled = true;
new g_iFirstKillReward = 300;
new g_iLeaderKillRewardStart = 300;
new g_iLeaderKillRewardStep = 100;
new g_iLeaderRewardGrowByLeaderKill = 50;
new g_iCurrentLeaderKillReward;

new const UNKNOWN_ARTIST_TITLE[] = "НЕИЗВЕСТНЫЙ ИСПОЛНИТЕЛЬ";

// Создает структуры плагина, читает конфиг и прекеширует ресурсы.
public plugin_precache()
{
	
	g_aWarm = ArrayCreate(WARM_STRUCT, 0);
	g_aPlugins = ArrayCreate(32, 0);
	g_aMusicFilesOnDisk = ArrayCreate(MAX_RESOURCE_PATH_LENGTH, 0);
	g_tMusicTitle = TrieCreate();
	g_tMusicDuration = TrieCreate();
	g_tKnownMusicFiles = TrieCreate();
	
	if (!ReadConfig())
		set_fail_state("Something went wrong");

	LoadWarmUpMusic();
	
	precache_sound("weapons/deagle-1.wav");
	precache_sound("events/task_complete.wav");
	g_iRingSprite = precache_model("sprites/shockwave.spr");
}

// Регистрирует плагин, события и игровые хуки.
public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR, URL, DESCRIPTIONPLUGIN);
	g_iMsgScreenFade = get_user_msgid("ScreenFade");
	g_iMsgStatusIcon = get_user_msgid("StatusIcon");
	
	register_event("TextMsg", "event_game_commencing", "a", "2=#Game_Commencing");
	
	DisableHookChain(g_hCheckMapConditions = RegisterHookChain(RG_CSGameRules_CheckMapConditions, "CSGameRules_CheckMapConditions", false));
	DisableHookChain(g_hDropPlayerItem = RegisterHookChain(RG_CBasePlayer_DropPlayerItem, "CBasePlayer_DropPlayerItem", false));
	DisableHookChain(g_hOnSpawnEquip = RegisterHookChain(RG_CBasePlayer_OnSpawnEquip, "CBasePlayer_OnSpawnEquip", true));
	
		/*top 5 */
	RegisterHookChain(RG_CSGameRules_RestartRound, "CSGameRules_RestartRound_Post", true);
	RegisterHookChain(RG_CBasePlayer_TakeDamage, "CBasePlayer_TakeDamage", true);
	g_iMaxPlayers = get_member_game(m_nMaxPlayers);
	cvar_name_sv_maxspeed = get_cvar_pointer( "sv_maxspeed" );
	
	if (g_pCvar[AUTO_AMMO]) {
		DisableHookChain(g_hKilled = RegisterHookChain(RG_CBasePlayer_Killed, "CBasePlayer_Killed", true));
	} else {
		//#pragma unused g_hKilled
	}
}

// Разблокирует условия карты и сбрасывает флаг m_bNotKilled живым игрокам.
public event_game_commencing()
{
	if (!g_bWarmupCompleted)
		EnableHookChain(g_hCheckMapConditions);
	
	//
	for (new i = MaxClients; i > 0; --i)
		if (is_user_alive(i))
			set_member(i, m_bNotKilled, false);
}

// Запускает разминку: применяет настройки, оружие, музыку и задачи таймера/подсветки.
public CSGameRules_CheckMapConditions()
{
	DisableHookChain(g_hCheckMapConditions);

	if (g_bWarmupCompleted)
		return;

	new iWarmModesCount = ArraySize(g_aWarm);
	if (iWarmModesCount <= 0)
	{
		log_amx("[ReAPI] Warm Up: no WEAPS entries loaded from %s. Warmup start aborted.", g_szWarmUpConfigPath);
		return;
	}
	
	EnableHookChain(g_hDropPlayerItem);
	EnableHookChain(g_hOnSpawnEquip);
	if (g_pCvar[AUTO_AMMO])
		EnableHookChain(g_hKilled);
	
	for (new i, pCvar; i < sizeof(g_eCvarsToDisable); i++)
	{
		pCvar = get_cvar_pointer(g_eCvarsToDisable[i][0]);
		
		get_pcvar_string(pCvar, g_pDefaultCvars[i], charsmax(g_pDefaultCvars[]));
		set_pcvar_string(pCvar, g_eCvarsToDisable[i][1]);
	}
	
	//
	if (g_pCvar[PAUSE_STATS])
	{
		set_cvar_num("csstats_pause", 1);
		set_cvar_num("aes_track_pause", 1);
	}
	
	new aWarm[WARM_STRUCT];
	ArrayGetArray(g_aWarm, random(iWarmModesCount), aWarm);
	
	// 
	set_cvar_num("mp_free_armor", aWarm[KEVLAR]);
	set_cvar_num("mp_falldamage", aWarm[FALL_DAMAGE]);
	
	set_cvar_float("mp_forcerespawn", aWarm[RESPAWN_TIME]);
	set_cvar_float("mp_respawn_immunitytime", aWarm[PROTECTION_TIME]);
	
	g_flMaxHealth = aWarm[HEALTH];
	g_iCountDown = ResolveWarmUpTime(aWarm[TIME]);
	g_iWarmUpTrackTime = g_iCountDown;
	
	copy(g_szWarmUpDescription, charsmax(g_szWarmUpDescription), aWarm[DESCRIPTION]);
	copy(g_szWarmUpTrack, charsmax(g_szWarmUpTrack), aWarm[TRACK]);
	ResolveWarmupWeaponSprites(aWarm[GUNS]);

	new bool:bRandomTrackPlayed = false;
	if (g_szMapWarmUpMusic[0])
	{
		bRandomTrackPlayed = true;
		new szMusicKey[MAX_RESOURCE_PATH_LENGTH];
		BuildMusicConfigKey(g_szMapWarmUpMusic, szMusicKey, charsmax(szMusicKey));

		g_szWarmUpTrack[0] = '^0';
		TrieGetString(g_tMusicTitle, szMusicKey, g_szWarmUpTrack, charsmax(g_szWarmUpTrack));
		if (!g_szWarmUpTrack[0])
			GetTrackName(g_szMapWarmUpMusic, g_szWarmUpTrack, charsmax(g_szWarmUpTrack));

		new iTrackDuration;
		if (TrieGetCell(g_tMusicDuration, szMusicKey, iTrackDuration) && iTrackDuration > 0)
		{
			g_iWarmUpTrackTime = iTrackDuration;
			if (iTrackDuration > g_iCountDown)
				g_iCountDown = iTrackDuration;
		}

		client_cmd(0, "stopsound; mp3 stop; wait; mp3 play ^"sound/%s^"", g_szMapWarmUpMusic);
	}
	
	// 
	FillWeapons(aWarm[GUNS]);
	
	//
	set_task(1.0, "Show_Timer", .flags = "b");
	if (g_bLeaderModeEnabled && (g_bHighlightRingEnabled || g_bHighlightModelEnabled))
	{
		set_task(g_flHighlightInterval, "Task_HighlightWarmupLeader", TASK_HIGHLIGHT_LEADER, .flags = "b");
	}
	ResetWarmupLeaderModelRendering();
	g_bFirstKillHappened = false;
	g_iWarmupLeader = 0;
	g_iHighlightedLeader = 0;
	g_iCurrentLeaderKillReward = g_iLeaderKillRewardStart;
	g_bWarmupRestartPending = false;
	
	// 
	for (new i; i < ArraySize(g_aPlugins); i++)
		pause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));

	ShowWarmupWeaponSpriteToAll();
	
	// Fallback: если папка с музыкой пуста, играем трек из конфигурации.
	if (!bRandomTrackPlayed && aWarm[MUSIC][0]) {
		client_cmd(0, "stopsound; mp3 stop; wait; mp3 play ^"sound/%s^"", aWarm[MUSIC]);
	}
}

// Блокирует выбрасывание оружия во время разминки.
public CBasePlayer_DropPlayerItem()
{
	SetHookChainReturn(ATYPE_INTEGER, NULLENT);
	return HC_SUPERCEDE;
}

// Выставляет игроку заданное здоровье при спавне.
public CBasePlayer_OnSpawnEquip(id)
{
	set_entvar(id, var_health, g_flMaxHealth);
	set_entvar(id, var_max_health, g_flMaxHealth);
}

// Обновляет статистику убийства, бонусы за лидера и текущего лидера разминки.
public CBasePlayer_Killed(Victim, Attacker, gib)
{
	if(!is_user_connected(Victim) || !is_user_connected(Attacker) || Victim == Attacker || !IsPlayer(Attacker) || get_member(Victim, m_iTeam) == get_member(Attacker, m_iTeam) || get_member(Victim, m_bKilledByGrenade))
		return;

	if (!g_bLeaderModeEnabled)
	{
		g_iPlayerKills[Attacker]++;
		g_bFirstKillHappened = true;
		return;
	}

	new iLeaderBeforeKill = g_iWarmupLeader;
	new bool:bLeaderExists = IsPlayer(iLeaderBeforeKill) && is_user_connected(iLeaderBeforeKill);
	new bool:bLeaderKilled = bLeaderExists && (Victim == iLeaderBeforeKill);
	new bool:bFirstLeaderKill = !bLeaderExists;

	if (!bLeaderExists && g_iCurrentLeaderKillReward <= 0)
		g_iCurrentLeaderKillReward = g_iLeaderKillRewardStart;

	g_iPlayerKills[Attacker]++;
	g_bFirstKillHappened = true;

	if (bLeaderExists && Attacker == iLeaderBeforeKill && !bLeaderKilled)
		g_iCurrentLeaderKillReward += g_iLeaderRewardGrowByLeaderKill;

	if (bLeaderKilled || bFirstLeaderKill)
	{
		new iLeaderReward;
		if (bFirstLeaderKill)
			iLeaderReward = g_iFirstKillReward;
		else
			iLeaderReward = max(g_iCurrentLeaderKillReward, g_iLeaderKillRewardStart);

		if (iLeaderReward > 0)
			g_iPlayerAward[Attacker] += iLeaderReward;

		if (bLeaderKilled)
			g_iCurrentLeaderKillReward += g_iLeaderKillRewardStep;
	}

	if (!bLeaderExists || bLeaderKilled)
		g_iWarmupLeader = Attacker;

	new pWeapon = get_member(Attacker, m_pActiveItem);
	if (is_nullent(pWeapon) || ~CSW_ALL_GUNS & 1 << get_member(pWeapon, m_iId))
		return;

	//rg_instant_reload_weapons(Attacker, pWeapon);
}

// Обновляет HUD таймер разминки и запускает показ итогов по завершению времени.
public Show_Timer()
{
	if (--g_iCountDown == 0)
	{
		remove_task(0);
		
		g_iOriginal_sv_maxspeed = get_pcvar_num(cvar_name_sv_maxspeed);
		log_amx("g_fOriginal_sv_maxspeed = %f", g_iOriginal_sv_maxspeed);
		set_pcvar_float(cvar_name_sv_maxspeed, 0.0 );
		
		
		/*DisableHookChain(g_hDropPlayerItem);
		DisableHookChain(g_hOnSpawnEquip);
		
		if (g_pCvar[AUTO_AMMO])
			DisableHookChain(g_hKilled);
		
		//
		for (new i; i < sizeof(g_eCvarsToDisable); i++) {
			set_pcvar_string(get_cvar_pointer(g_eCvarsToDisable[i][0]), g_pDefaultCvars[i]);
		}
		
		if (g_pCvar[PAUSE_STATS])
		{
			set_cvar_num("csstats_pause", 0);
			set_cvar_num("aes_track_pause", 0);
		}
		
		set_cvar_num("sv_restart", 1);
		if (g_pCvar[RESTART] > 1)
			set_task(1.5, "@restart", .flags = "a", .repeat = g_pCvar[RESTART] - 1);
		
		// 
		for (new i; i < ArraySize(g_aPlugins); i++)
		unpause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));*/
		set_task(0.5, "fnCompareDamage");
	}
	else
	{
		if (g_iWarmUpTrackTime > 0)
			g_iWarmUpTrackTime--;

		set_dhudmessage( .red = 255, .green = 0, .blue = 0, .x = -1.0, .y = 0.01, .effects = 0, .fxtime = 0.0, .holdtime = 1.1, .fadeintime = 0.0, .fadeouttime = 0.0);
		show_dhudmessage(0, "%s", g_szWarmUpDescription);
		ShowWarmupWeaponSpriteToAll();

		if(!g_szWarmUpTrack[0] || g_iWarmUpTrackTime <= 0){
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.04, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
			show_dhudmessage(0, "РАЗМИНКА ЗАКОНЧИТСЯ ЧЕРЕЗ %i СЕК", g_iCountDown);
			ShowLeaderRewardHud(0.07);
		}else{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.04, .effects = 0, .fxtime = 0.0, .holdtime = 1.1, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "СЕЙЧАС ИГРАЕТ: %s", g_szWarmUpTrack);
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.07, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
			show_dhudmessage(0, "РАЗМИНКА ЗАКОНЧИТСЯ ЧЕРЕЗ %i СЕК", g_iCountDown);
			ShowLeaderRewardHud(0.10);
		}

	}
}

stock ResolveWarmupWeaponSprites(const szGunList[])
{
	g_iWarmUpWeaponSpritesCount = 0;

	for (new i; i < sizeof(g_szWarmUpWeaponSprites); i++)
		g_szWarmUpWeaponSprites[i][0] = '^0';

	new szInput[128], szWeaponToken[16], szSprite[24];
	copy(szInput, charsmax(szInput), szGunList);

	while (argbreak(szInput, szWeaponToken, charsmax(szWeaponToken), szInput, charsmax(szInput)) != -1)
	{
		if (!szWeaponToken[0])
			continue;

		if (!WeaponTokenToSprite(szWeaponToken, szSprite, charsmax(szSprite)))
			continue;

		new bool:bExists;
		for (new i; i < g_iWarmUpWeaponSpritesCount; i++)
		{
			if (equali(g_szWarmUpWeaponSprites[i], szSprite))
			{
				bExists = true;
				break;
			}
		}

		if (bExists || g_iWarmUpWeaponSpritesCount >= sizeof(g_szWarmUpWeaponSprites))
			continue;

		copy(g_szWarmUpWeaponSprites[g_iWarmUpWeaponSpritesCount], charsmax(g_szWarmUpWeaponSprites[]), szSprite);
		g_iWarmUpWeaponSpritesCount++;
	}

	if (!g_iWarmUpWeaponSpritesCount)
	{
		copy(g_szWarmUpWeaponSprites[0], charsmax(g_szWarmUpWeaponSprites[]), "d_knife");
		g_iWarmUpWeaponSpritesCount = 1;
	}
}

stock bool:WeaponTokenToSprite(const szWeapon[], szSprite[], iSpriteLen)
{
	if (equali(szWeapon, "knife") || equali(szWeapon, "weapon_knife")) return bool:copy(szSprite, iSpriteLen, "d_knife");
	if (equali(szWeapon, "glock18")) return bool:copy(szSprite, iSpriteLen, "d_glock18");
	if (equali(szWeapon, "usp")) return bool:copy(szSprite, iSpriteLen, "d_usp");
	if (equali(szWeapon, "p228")) return bool:copy(szSprite, iSpriteLen, "d_p228");
	if (equali(szWeapon, "deagle")) return bool:copy(szSprite, iSpriteLen, "d_deagle");
	if (equali(szWeapon, "fiveseven")) return bool:copy(szSprite, iSpriteLen, "d_fiveseven");
	if (equali(szWeapon, "elite")) return bool:copy(szSprite, iSpriteLen, "d_elite");
	if (equali(szWeapon, "m3")) return bool:copy(szSprite, iSpriteLen, "d_m3");
	if (equali(szWeapon, "xm1014")) return bool:copy(szSprite, iSpriteLen, "d_xm1014");
	if (equali(szWeapon, "tmp")) return bool:copy(szSprite, iSpriteLen, "d_tmp");
	if (equali(szWeapon, "mac10")) return bool:copy(szSprite, iSpriteLen, "d_mac10");
	if (equali(szWeapon, "ump45")) return bool:copy(szSprite, iSpriteLen, "d_ump45");
	if (equali(szWeapon, "mp5") || equali(szWeapon, "mp5navy")) return bool:copy(szSprite, iSpriteLen, "d_mp5navy");
	if (equali(szWeapon, "p90")) return bool:copy(szSprite, iSpriteLen, "d_p90");
	if (equali(szWeapon, "galil")) return bool:copy(szSprite, iSpriteLen, "d_galil");
	if (equali(szWeapon, "famas")) return bool:copy(szSprite, iSpriteLen, "d_famas");
	if (equali(szWeapon, "ak47")) return bool:copy(szSprite, iSpriteLen, "d_ak47");
	if (equali(szWeapon, "m4a1")) return bool:copy(szSprite, iSpriteLen, "d_m4a1");
	if (equali(szWeapon, "scout")) return bool:copy(szSprite, iSpriteLen, "d_scout");
	if (equali(szWeapon, "sg552")) return bool:copy(szSprite, iSpriteLen, "d_sg552");
	if (equali(szWeapon, "aug")) return bool:copy(szSprite, iSpriteLen, "d_aug");
	if (equali(szWeapon, "sg550")) return bool:copy(szSprite, iSpriteLen, "d_sg550");
	if (equali(szWeapon, "g3sg1")) return bool:copy(szSprite, iSpriteLen, "d_g3sg1");
	if (equali(szWeapon, "awp")) return bool:copy(szSprite, iSpriteLen, "d_awp");
	if (equali(szWeapon, "m249")) return bool:copy(szSprite, iSpriteLen, "d_m249");
	if (equali(szWeapon, "hegrenade") || equali(szWeapon, "grenade")) return bool:copy(szSprite, iSpriteLen, "d_grenade");
	if (equali(szWeapon, "flash")) return bool:copy(szSprite, iSpriteLen, "d_flashbang");
	if (equali(szWeapon, "sgren")) return bool:copy(szSprite, iSpriteLen, "d_smokegrenade");

	return false;
}

stock ShowWarmupWeaponSpriteToAll()
{
	for (new id = 1; id <= MaxClients; id++)
	{
		if (!is_user_connected(id))
			continue;

		ShowWarmupWeaponSprite(id);
	}
}

stock HideWarmupWeaponSpriteForAll()
{
	for (new id = 1; id <= MaxClients; id++)
	{
		if (!is_user_connected(id))
			continue;

		HideWarmupWeaponSprite(id);
	}
}

stock ShowWarmupWeaponSprite(id)
{
	if (!g_iMsgStatusIcon || !is_user_connected(id))
		return;

	if (!g_bWarmupWeaponSpriteEnabled || !g_iWarmUpWeaponSpritesCount)
	{
		HideWarmupWeaponSprite(id);
		return;
	}

	for (new i; i < g_iWarmUpWeaponSpritesCount; i++)
	{
		message_begin(MSG_ONE, g_iMsgStatusIcon, {0, 0, 0}, id);
		write_byte(1);
		write_string(g_szWarmUpWeaponSprites[i]);
		write_byte(g_iWarmupWeaponSpriteColor[0]);
		write_byte(g_iWarmupWeaponSpriteColor[1]);
		write_byte(g_iWarmupWeaponSpriteColor[2]);
		message_end();
	}
}

stock HideWarmupWeaponSprite(id)
{
	if (!g_iMsgStatusIcon || !is_user_connected(id) || !g_iWarmUpWeaponSpritesCount)
		return;

	for (new i; i < g_iWarmUpWeaponSpritesCount; i++)
	{
		message_begin(MSG_ONE, g_iMsgStatusIcon, {0, 0, 0}, id);
		write_byte(0);
		write_string(g_szWarmUpWeaponSprites[i]);
		write_byte(0);
		write_byte(0);
		write_byte(0);
		message_end();
	}
}

stock ShowLeaderRewardHud(Float:flStartY)
{
	if (!g_bLeaderModeEnabled)
		return;

	if (!IsPlayer(g_iWarmupLeader) || !is_user_connected(g_iWarmupLeader))
		return;

	new szLeaderName[MAX_NAME_LENGTH];
	get_user_name(g_iWarmupLeader, szLeaderName, charsmax(szLeaderName));

	set_dhudmessage(.red = 255, .green = 255, .blue = 0, .x = -1.0, .y = flStartY, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
	show_dhudmessage(0, "РАЗЫСКИВАЕТСЯ - %s", szLeaderName);

	set_dhudmessage(.red = 255, .green = 200, .blue = 0, .x = -1.0, .y = flStartY + 0.03, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
	show_dhudmessage(0, "НАГРАДА ЗА УБИЙСТВО - %d$", max(g_iCurrentLeaderKillReward, 0));
}

// Периодически запускает подсветку лидера после первого убийства.
public Task_HighlightWarmupLeader()
{
	if (!g_bLeaderModeEnabled || (!g_bHighlightRingEnabled && !g_bHighlightModelEnabled))
		return;

	if (!g_bFirstKillHappened)
		return;

	HighlightWarmupLeader();
}

// Подсвечивает лидера эффектом модели и кольцом на земле.
stock HighlightWarmupLeader()
{
	static bool:bPulseExpand;
	new iPrevLeader = g_iHighlightedLeader;

	new iLeader = g_iWarmupLeader;
	if (!IsPlayer(iLeader) || !is_user_alive(iLeader))
	{
		if (IsPlayer(iPrevLeader))
			ResetLeaderModelRendering(iPrevLeader);

		g_iHighlightedLeader = 0;
		return;
	}

	g_iWarmupLeader = iLeader;
	g_iHighlightedLeader = iLeader;
	if (iPrevLeader != iLeader && IsPlayer(iPrevLeader))
		ResetLeaderModelRendering(iPrevLeader);

	if (g_bHighlightModelEnabled)
	{
		set_user_rendering(
			iLeader,
			kRenderFxGlowShell,
			g_iHighlightModelColor[0],
			g_iHighlightModelColor[1],
			g_iHighlightModelColor[2],
			kRenderNormal,
			16
		);
	}
	else
	{
		ResetLeaderModelRendering(iLeader);
	}

	if (g_bHighlightRingEnabled)
	{
		new Float:vecOrigin[3], Float:vecRingCenter[3], Float:flPulseRadius;
		get_entvar(iLeader, var_origin, vecOrigin);
		bPulseExpand = !bPulseExpand;
		flPulseRadius = g_flHighlightRadius + (bPulseExpand ? (g_flHighlightRadius / 5.0) : 0.0);

		vecRingCenter[0] = vecOrigin[0];
		vecRingCenter[1] = vecOrigin[1];
		vecRingCenter[2] = vecOrigin[2] + g_flHighlightHeight;

		message_begin(MSG_ALL, SVC_TEMPENTITY);
		write_byte(TE_BEAMCYLINDER);
		engfunc(EngFunc_WriteCoord, vecRingCenter[0]);
		engfunc(EngFunc_WriteCoord, vecRingCenter[1]);
		engfunc(EngFunc_WriteCoord, vecRingCenter[2]);
		engfunc(EngFunc_WriteCoord, vecRingCenter[0]);
		engfunc(EngFunc_WriteCoord, vecRingCenter[1]);
		engfunc(EngFunc_WriteCoord, vecRingCenter[2] + flPulseRadius);
		write_short(g_iRingSprite);
		write_byte(0);
		write_byte(0);
		write_byte(8);
		write_byte(20);
		write_byte(0);
		write_byte(g_iHighlightColor[0]);
		write_byte(g_iHighlightColor[1]);
		write_byte(g_iHighlightColor[2]);
		write_byte(200);
		write_byte(0);
		message_end();
	}
}
// Выполняет принудительный рестарт раунда и останавливает музыку.
@restart() 
{
	set_cvar_num("sv_maxspeed", g_iOriginal_sv_maxspeed);
	client_cmd(0, "stopsound; mp3 stop");
	set_cvar_num("sv_restart", 1);
}

// Разбирает список оружия и применяет соответствующие cvar выдачи.
stock FillWeapons(szGun[])
{
	new Trie:tPrimaryWeapon = TrieCreate(),
		Trie:tSecondaryWeapon = TrieCreate(),
		Trie:tGrenade = TrieCreate(),
		Trie:tKnife = TrieCreate();
	
	new szPrimaryWeapon[128],
		szSecondaryWeapon[128],
		szGrenade[64],
		szWeapon[11];

	szPrimaryWeapon[0] = '^0';
	szSecondaryWeapon[0] = '^0';
	szGrenade[0] = '^0';
	
	new bool:bKnife = false;
	new value;
	
	// Primary
	TrieSetCell(tPrimaryWeapon, "m3", value);
	TrieSetCell(tPrimaryWeapon, "xm1014", value);
	TrieSetCell(tPrimaryWeapon, "tmp", value);
	TrieSetCell(tPrimaryWeapon, "mac10", value);
	TrieSetCell(tPrimaryWeapon, "ump45", value);
	TrieSetCell(tPrimaryWeapon, "mp5navy", value);
	TrieSetCell(tPrimaryWeapon, "p90", value);
	TrieSetCell(tPrimaryWeapon, "galil", value);
	TrieSetCell(tPrimaryWeapon, "famas", value);
	TrieSetCell(tPrimaryWeapon, "ak47", value);
	TrieSetCell(tPrimaryWeapon, "m4a1", value);
	TrieSetCell(tPrimaryWeapon, "sg552", value);
	TrieSetCell(tPrimaryWeapon, "aug", value);
	TrieSetCell(tPrimaryWeapon, "sg550", value);
	TrieSetCell(tPrimaryWeapon, "g3sg1", value);
	TrieSetCell(tPrimaryWeapon, "awp", value);
	TrieSetCell(tPrimaryWeapon, "m249", value);
	
	// Secondary
	TrieSetCell(tSecondaryWeapon, "glock18", value);
	TrieSetCell(tSecondaryWeapon, "usp", value);
	TrieSetCell(tSecondaryWeapon, "p228", value);
	TrieSetCell(tSecondaryWeapon, "deagle", value);
	TrieSetCell(tSecondaryWeapon, "fiveseven", value);
	TrieSetCell(tSecondaryWeapon, "elite", value);
	
	// Nades
	TrieSetCell(tGrenade, "hegrenade", value);
	TrieSetCell(tGrenade, "grenade", value);
	TrieSetCell(tGrenade, "flash", value);
	TrieSetCell(tGrenade, "sgren", value);
	
	// Knife
	TrieSetCell(tKnife, "knife", value);
	
	while (argbreak(szGun, szWeapon, charsmax(szWeapon), szGun, strlen(szGun) - 1) != -1)
	{
		if (TrieGetCell(tKnife, szWeapon, value))
			bKnife = true;
		
		if (TrieGetCell(tPrimaryWeapon, szWeapon, value))
			strcat(szPrimaryWeapon, fmt("%s ", szWeapon), charsmax(szPrimaryWeapon));
		if (TrieGetCell(tSecondaryWeapon, szWeapon, value))
			strcat(szSecondaryWeapon, fmt("%s ", szWeapon), charsmax(szSecondaryWeapon));
		if (TrieGetCell(tGrenade, szWeapon, value))
			strcat(szGrenade, fmt("%s ", szWeapon), charsmax(szGrenade));
	}
	
	if (szPrimaryWeapon[0] != '^0')
	{
		set_cvar_string("mp_t_default_weapons_primary", szPrimaryWeapon);
		set_cvar_string("mp_ct_default_weapons_primary", szPrimaryWeapon);
	}
	
	if (szSecondaryWeapon[0] != '^0')
	{
		set_cvar_string("mp_t_default_weapons_secondary", szSecondaryWeapon);
		set_cvar_string("mp_ct_default_weapons_secondary", szSecondaryWeapon);
	}
	
	if (szGrenade[0] != '^0')
	{
		set_cvar_string("mp_t_default_grenades", szGrenade);
		set_cvar_string("mp_ct_default_grenades", szGrenade);
		
		if (szPrimaryWeapon[0] == '^0' && szSecondaryWeapon[0] == '^0')
			set_cvar_num("mp_infinite_grenades", 1);
		
		// 
		if (containi(szGrenade, "grenade") == -1)
			bKnife = true;
	}
	
	if (bKnife)
	{
		set_cvar_num("mp_t_give_player_knife", 1);
		set_cvar_num("mp_ct_give_player_knife", 1);
	}
	
	TrieDestroy(tPrimaryWeapon);
	TrieDestroy(tSecondaryWeapon);
	TrieDestroy(tGrenade);
	TrieDestroy(tKnife);
}


// Сканирует папку музыки, выбирает случайный трек и синхронизирует MUSIC_FILES.
stock LoadWarmUpMusic()
{
	g_szMapWarmUpMusic[0] = '^0';
	ArrayClear(g_aMusicFilesOnDisk);

	new szFile[MAX_RESOURCE_PATH_LENGTH], FileType:iType;
	new szFolderPath[MAX_RESOURCE_PATH_LENGTH];
	formatex(szFolderPath, charsmax(szFolderPath), "sound/%s", g_szWarmUpMusicDir);

	new hDir = open_dir(szFolderPath, szFile, charsmax(szFile), iType);

	if (!hDir)
	{
		RewriteMusicConfigSection();
		return;
	}

	new iFoundTracks;
	do
	{
		if (iType != FileType_File)
			continue;

		if (containi(szFile, ".mp3") == -1)
			continue;

		new szMusicPath[MAX_RESOURCE_PATH_LENGTH];
		new szMusicKey[MAX_RESOURCE_PATH_LENGTH];
		formatex(szMusicPath, charsmax(szMusicPath), "%s/%s", g_szWarmUpMusicDir, szFile);
		BuildMusicConfigKey(szMusicPath, szMusicKey, charsmax(szMusicKey));
		ArrayPushString(g_aMusicFilesOnDisk, szMusicPath);

		new iExists;
		new bool:bKnownFile = TrieGetCell(g_tKnownMusicFiles, szMusicKey, iExists);
		new szTrackTitle[64];
		new bool:bHasTitle = TrieGetString(g_tMusicTitle, szMusicKey, szTrackTitle, charsmax(szTrackTitle)) && szTrackTitle[0];

		if (!bKnownFile || !bHasTitle)
		{
			ReadMp3Meta(szMusicPath, szTrackTitle, charsmax(szTrackTitle));


			if (szTrackTitle[0])
				TrieSetString(g_tMusicTitle, szMusicKey, szTrackTitle);

			TrieSetCell(g_tKnownMusicFiles, szMusicKey, 1);
		}

		if (!bKnownFile)
		{
			new iTrackDuration;
			if (!TrieGetCell(g_tMusicDuration, szMusicKey, iTrackDuration) || iTrackDuration <= 0)
				TrieSetCell(g_tMusicDuration, szMusicKey, GetDefaultMusicDuration());
		}

		iFoundTracks++;
		if (random_num(1, iFoundTracks) == 1)
			copy(g_szMapWarmUpMusic, charsmax(g_szMapWarmUpMusic), szMusicPath);
	}
	while (next_file(hDir, szFile, charsmax(szFile), iType));

	close_dir(hDir);

	if (g_szMapWarmUpMusic[0])
		precache_generic(fmt("sound/%s", g_szMapWarmUpMusic));

	RewriteMusicConfigSection();
}

// Читает ID3v1 теги mp3 и формирует название трека.
stock ReadMp3Meta(const szMusicPath[], szTrackTitle[], iTitleLen)
{
	szTrackTitle[0] = '^0';

	new szFullPath[PLATFORM_MAX_PATH];
	formatex(szFullPath, charsmax(szFullPath), "sound/%s", szMusicPath);

	new hFile = fopen(szFullPath, "rb");
	if (!hFile)
		return;

	new iFileSize;
	fseek(hFile, 0, SEEK_END);
	iFileSize = ftell(hFile);


	new iTagPos = iFileSize - 128;
	if (iTagPos >= 0)
	{
		fseek(hFile, iTagPos, SEEK_SET);

		new aTag[128];
		if (fread_blocks(hFile, aTag, sizeof(aTag), BLOCK_BYTE) == sizeof(aTag))
		{
			if (aTag[0] == 'T' && aTag[1] == 'A' && aTag[2] == 'G')
			{
				new szArtist[MAX_ARTIST_NAME_LEN + 1], szTitleRaw[MAX_TRACK_NAME_LEN + 1];
				for (new i = 3, j = 0; i < 33 && j < iTitleLen - 1; i++)
				{
					if (!aTag[i])
						break;
					szTitleRaw[j++] = aTag[i];
					szTitleRaw[j] = '^0';
				}

				for (new i = 33, j = 0; i < 63 && j < charsmax(szArtist); i++)
				{
					if (!aTag[i])
						break;
					szArtist[j++] = aTag[i];
					szArtist[j] = '^0';
				}

				trim(szTitleRaw);
				trim(szArtist);

				if (!IsLikelyReadableTitle(szArtist) || !IsLikelyReadableTitle(szTitleRaw))
				{
					szArtist[0] = '^0';
					szTitleRaw[0] = '^0';
				}

				if (szArtist[0] && szTitleRaw[0])
					formatex(szTrackTitle, iTitleLen, "%s - %s", szArtist, szTitleRaw);
				else if (szTitleRaw[0])
					copy(szTrackTitle, iTitleLen, szTitleRaw);
			}
		}
	}

	fclose(hFile);

	if (!szTrackTitle[0])
		copy(szTrackTitle, iTitleLen, UNKNOWN_ARTIST_TITLE);

	NormalizeTrackTitle(szTrackTitle, iTitleLen);
}

// Полностью пересобирает секцию MUSIC_FILES в конфиге.
stock RewriteMusicConfigSection()
{
	if (!g_szWarmUpConfigPath[0])
		return;

	new Array:aLines = ArrayCreate(256, 0);
	new szLine[256], iLen;
	new bool:bInMusicSection;

	for (new i; read_file(g_szWarmUpConfigPath, i, szLine, charsmax(szLine), iLen); i++)
	{
		new szTrimmed[256];
		copy(szTrimmed, charsmax(szTrimmed), szLine);
		trim(szTrimmed);

		if (equal(szTrimmed, "[MUSIC_FILES]"))
		{
			bInMusicSection = true;
			continue;
		}

		if (bInMusicSection)
		{
			if (szTrimmed[0] == '[')
				bInMusicSection = false;
			else
				continue;
		}

		ArrayPushString(aLines, szLine);
	}

	delete_file(g_szWarmUpConfigPath);

	for (new i; i < ArraySize(aLines); i++)
	{
		ArrayGetString(aLines, i, szLine, charsmax(szLine));
		write_file(g_szWarmUpConfigPath, szLine, -1);
	}

	write_file(g_szWarmUpConfigPath, "", -1);
	write_file(g_szWarmUpConfigPath, "[MUSIC_FILES]", -1);

	for (new i; i < ArraySize(g_aMusicFilesOnDisk); i++)
	{
		new szMusicPath[MAX_RESOURCE_PATH_LENGTH], szTrackTitle[MAX_TRACK_TITLE_LEN + 1], szNewEntry[320];
		new szMusicKey[MAX_RESOURCE_PATH_LENGTH];

		ArrayGetString(g_aMusicFilesOnDisk, i, szMusicPath, charsmax(szMusicPath));
		BuildMusicConfigKey(szMusicPath, szMusicKey, charsmax(szMusicKey));
		TrieGetString(g_tMusicTitle, szMusicKey, szTrackTitle, charsmax(szTrackTitle));

		NormalizeTrackTitle(szTrackTitle, charsmax(szTrackTitle));

		new iTrackDuration;
		if (!TrieGetCell(g_tMusicDuration, szMusicKey, iTrackDuration))
			iTrackDuration = 0;

		if (!szTrackTitle[0])
			copy(szTrackTitle, charsmax(szTrackTitle), UNKNOWN_ARTIST_TITLE);

		if (iTrackDuration > 0)
			formatex(szNewEntry, charsmax(szNewEntry), "%s = %s | %d", szMusicKey, szTrackTitle, iTrackDuration);
		else
			formatex(szNewEntry, charsmax(szNewEntry), "%s = %s | УКАЖИТЕ ВРЕМЯ РАЗМИНКИ", szMusicKey, szTrackTitle);

		write_file(g_szWarmUpConfigPath, szNewEntry, -1);
	}

	ArrayDestroy(aLines);
}

// Получает название трека из имени файла без расширения.
stock GetTrackName(const szPath[], szTrack[], iLen)
{
	new iLastSlash = -1;
	for (new i; szPath[i] != '^0'; i++)
	{
		if (szPath[i] == '/')
			iLastSlash = i;
	}

	copy(szTrack, iLen, szPath[(iLastSlash + 1)]);

	new iExt = containi(szTrack, ".mp3");
	if (iExt != -1)
		szTrack[iExt] = '^0';

	NormalizeTrackTitle(szTrack, iLen);
}

// Формирует ключ трека для конфига по имени файла.
stock BuildMusicConfigKey(const szMusicPath[], szKey[], iKeyLen)
{
	new iLastSlash = -1;
	for (new i; szMusicPath[i] != '^0'; i++)
	{
		if (szMusicPath[i] == '/')
			iLastSlash = i;
	}

	copy(szKey, iKeyLen, szMusicPath[(iLastSlash + 1)]);
}

// Нормализует формат названия трека и удаляет лишние пробелы.
stock NormalizeTrackTitle(szTrack[], iLen)
{
	trim(szTrack);

	new iDelimiter = contain(szTrack, " - ");
	if (iDelimiter != -1)
	{
		new szArtist[MAX_ARTIST_NAME_LEN + 1], szTitle[MAX_TRACK_NAME_LEN + 1];

		copy(szArtist, charsmax(szArtist), szTrack);
		new iArtistEnd = iDelimiter;
		if (iArtistEnd > charsmax(szArtist))
			iArtistEnd = charsmax(szArtist);
		szArtist[iArtistEnd] = '^0';

		copy(szTitle, charsmax(szTitle), szTrack[iDelimiter + 3]);

		trim(szArtist);
		trim(szTitle);

		if (szArtist[0] && szTitle[0])
			formatex(szTrack, iLen, "%s - %s", szArtist, szTitle);
		else if (szTitle[0])
			copy(szTrack, iLen, szTitle);
		else
			copy(szTrack, iLen, szArtist);

		return;
	}

	new szTrimmed[MAX_TRACK_NAME_LEN + 1];
	copy(szTrimmed, charsmax(szTrimmed), szTrack);
	trim(szTrimmed);
	copy(szTrack, iLen, szTrimmed);
}


// Проверяет, что строка содержит читаемые ASCII-символы.
stock bool:IsLikelyReadableTitle(const szText[])
{
	new bool:bHasReadableChars;

	for (new i; szText[i] != '^0'; i++)
	{
		new iChar = szText[i];

		if (iChar < 32 || iChar > 126)
			return false;

		if ((iChar >= '0' && iChar <= '9') || (iChar >= 'A' && iChar <= 'Z') || (iChar >= 'a' && iChar <= 'z'))
			bHasReadableChars = true;
	}

	return bHasReadableChars;
}

// Ограничивает длительность разминки диапазоном 10..90 секунд.
stock ClampWarmTime(iTime)
{
	if (iTime < 10)
		return 10;
	if (iTime > 90)
		return 90;

	return iTime;
}

// Возвращает итоговое время разминки с учетом режима AUTO/ручного значения.
stock ResolveWarmUpTime(iDefaultWarmTime)
{
	if (!equali(g_szWarmUpTimeMode, "AUTO"))
	{
		new iManualTime = str_to_num(g_szWarmUpTimeMode);
		if (iManualTime >= 10 && iManualTime <= 90)
			return iManualTime;
	}


	return ClampWarmTime(iDefaultWarmTime);
}

// Возвращает дефолтную длительность трека для MUSIC_FILES.
stock GetDefaultMusicDuration()
{
	new iWarmTime = str_to_num(g_szWarmUpTimeMode);
	if (iWarmTime >= 10 && iWarmTime <= 90)
		return iWarmTime;

	return 60;
}

// Создает warm_up.ini с базовыми секциями и значениями по умолчанию.
stock CreateDefaultConfigFile()
{
	new const szDefaultConfig[][] =
	{
		";",
		"; Конфигурационный файл WARM UP v. 1.0.0 by Emma Jule",
		";",
		"; Некоторые настройки самой системы",
		"[VARIABLES]",
		"; RESTART - количество рестартов после разминки",
		"	RESTART = 1",
		"; AUTO_AMMO - автоперезарядка после убийства (0/1)",
		"	AUTO_AMMO = 1",
		"; PAUSE_STATS - пауза csstats/aes на время разминки (0/1)",
		"	PAUSE_STATS = 1",
		"; MUSIC_FOLDER - папка с mp3 в sound/",
		"	MUSIC_FOLDER = ms/Warm_Up",
		"; WARMUP_TIME - AUTO или число секунд (10..90)",
		"	WARMUP_TIME = AUTO",
		"; HIGHLIGHT_RING_ENABLED - включить кольцо подсветки лидера (0/1)",
		"	HIGHLIGHT_RING_ENABLED = 1",
		"; HIGHLIGHT_ENABLED - устаревшее имя, оставлено для совместимости",
		"; HIGHLIGHT_MODEL_ENABLED - glow на модели лидера (0/1)",
		"	HIGHLIGHT_MODEL_ENABLED = 1",
		"; HIGHLIGHT_INTERVAL - интервал подсветки лидера (0.1..5.0)",
		"	HIGHLIGHT_INTERVAL = 5.0",
		"; HIGHLIGHT_RADIUS - радиус кольца подсветки",
		"	HIGHLIGHT_RADIUS = 100.0",
		"; HIGHLIGHT_HEIGHT - смещение кольца по высоте",
		"	HIGHLIGHT_HEIGHT = 0.0",
		"; HIGHLIGHT_COLOR - цвет кольца (R G B)",
		"	HIGHLIGHT_COLOR = 0 255 0",
		"; HIGHLIGHT_MODEL_COLOR - цвет glow модели (R G B)",
		"	HIGHLIGHT_MODEL_COLOR = 255 0 0",
		"; WEAPON_SPRITE_ENABLED - показывать спрайт оружия разминки (0/1)",
		"	WEAPON_SPRITE_ENABLED = 1",
		"; WEAPON_SPRITE_COLOR - цвет спрайта оружия разминки (R G B)",
		"	WEAPON_SPRITE_COLOR = 0 160 0",
		"; RESULTS_FADE_ALPHA - затемнение экрана при итогах (0..255)",
		"	RESULTS_FADE_ALPHA = 180",
		"; LEADER_MODE_ENABLED - использовать режим с лидером (0/1)",
		"	LEADER_MODE_ENABLED = 1",
		"; FIRST_KILL_REWARD - награда в $ за первое убийство на разминке",
		"	FIRST_KILL_REWARD = 300",
		"; LEADER_KILL_REWARD_START - стартовая награда в $ за убийство лидера",
		"	LEADER_KILL_REWARD_START = 300",
		"; LEADER_KILL_REWARD_STEP - увеличение награды после каждого убийства лидера",
		"	LEADER_KILL_REWARD_STEP = 100",
		"; LEADER_REWARD_GROW_BY_LEADER_KILL - рост награды, если лидер убивает игрока, пока он лидер",
		"	LEADER_REWARD_GROW_BY_LEADER_KILL = 50",
		"",
		";",
		"; Список плагинов которые будут ставится на паузу в момент разминки",
		"; Примечание: вводите без .amxx",
		";",
		"[PLUGINS]",
		"	Knife_Duel",
		"	ms_throws_knife",
		"",
		";",
		"; Режим разминки (пикается рандомно)",
		"; Правила заполнения просты: вводите все пункты через символ | (примеры будут приведены ниже как по умолчанию)",
		"; ",
		"; 1. Оружие (вводите через пробел)",
		"; [",
		";    B1: glock18, usp, p228, deagle, fiveseven, elite",
		";    B2: m3, xm1014",
		";    B3: tmp, mac10, mp5, ump45, p90",
		";    B4: galil, famas, ak47, m4a1, scout, aug, sg552, sg550, g3sg1, awp",
		";    B5: m249",
		";    NADES: hegrenade, flash, sgren",
		"; ]",
		"; 2. Описание в HUD о разминке",
		"; 3. Кол-во здоровья",
		"; 4. Время защиты после спавна",
		"; 5. Время через которое игрок воскреснет вновь",
		"; 6. Время самой разминки (в секундах)",
		"; 7. Броня при спавне (0 - нет, 1 - броня, 2 - броня + шлем)",
		"; 8. Получает ли урон от падения?",
		";",
		"[WEAPS]",
		"knife | РАЗМИНКА | 35.0 | 1.0 | 1.0 | 60 | 2 | 1",
		"",
		"[MUSIC_FILES]"
	};

	for (new i; i < sizeof(szDefaultConfig); i++)
		write_file(g_szWarmUpConfigPath, szDefaultConfig[i], -1);
}

// Загружает конфиг разминки и создает его при отсутствии.
ReadConfig()
{
	g_iSection = NULL;

	get_localinfo("amxx_basedir", g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath));
	add(g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath), "/");
	add(g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath), WARMUP_CONFIG_FILE);
	
	if (!file_exists(g_szWarmUpConfigPath))
		CreateDefaultConfigFile();
	
	new INIParser:parser = INI_CreateParser();

	if (parser == Invalid_INIParser)
		return false;
	
	INI_SetReaders(parser, "values", "sections");
	INI_ParseFile(parser, g_szWarmUpConfigPath);
	INI_DestroyParser(parser);
	
	return true;
}

// Определяет текущую секцию INI-парсера.
public bool:sections(INIParser:handle, const section[], bool:invalid_tokens, bool:close_bracket)
{
	g_iSection = NULL;

	if (!close_bracket)
		return false;
	
	if (equal(section, "VARIABLES"))
	{
		g_iSection = VARIABLES;
		return true;
	}
	
	if (equal(section, "PLUGINS"))
	{
		g_iSection = PLUGINS;
		return true;
	}
	
	if (equal(section, "WEAPS"))
	{
		g_iSection = WEAPS;
		return true;
	}

	if (equal(section, "MUSIC_FILES"))
	{
		g_iSection = MUSIC_FILES;
		return true;
	}
	
	return true;
}

// Обрабатывает ключи INI и заполняет настройки плагина.
public bool:values(INIParser:handle, const key[], const value[])
{
	switch (g_iSection)
	{
		case NULL:
			return false;
        
		case VARIABLES:
		{
			if (equal(key, "RESTART"))
				g_pCvar[RESTART] = str_to_num(value);
			if (equal(key, "AUTO_AMMO"))
				g_pCvar[AUTO_AMMO] = str_to_num(value);
			if (equal(key, "PAUSE_STATS"))
				g_pCvar[PAUSE_STATS] = str_to_num(value);
			if (equal(key, "MUSIC_FOLDER"))
				copy(g_szWarmUpMusicDir, charsmax(g_szWarmUpMusicDir), value);
			if (equal(key, "WARMUP_TIME"))
				copy(g_szWarmUpTimeMode, charsmax(g_szWarmUpTimeMode), value);
			if (equal(key, "HIGHLIGHT_ENABLED") || equal(key, "HIGHLIGHT_RING_ENABLED"))
				g_bHighlightRingEnabled = bool:clamp(str_to_num(value), 0, 1);
			if (equal(key, "HIGHLIGHT_MODEL_ENABLED"))
				g_bHighlightModelEnabled = bool:clamp(str_to_num(value), 0, 1);
			if (equal(key, "HIGHLIGHT_INTERVAL"))
				g_flHighlightInterval = floatclamp(str_to_float(value), 0.1, 5.0);
			if (equal(key, "HIGHLIGHT_RADIUS"))
				g_flHighlightRadius = floatclamp(str_to_float(value), 10.0, 500.0);
			if (equal(key, "HIGHLIGHT_HEIGHT"))
				g_flHighlightHeight = floatclamp(str_to_float(value), -100.0, 100.0);
			if (equal(key, "HIGHLIGHT_COLOR"))
				ParseHighlightColor(value);
			if (equal(key, "HIGHLIGHT_MODEL_COLOR"))
				ParseHighlightModelColor(value);
			if (equal(key, "WEAPON_SPRITE_ENABLED"))
				g_bWarmupWeaponSpriteEnabled = bool:clamp(str_to_num(value), 0, 1);
			if (equal(key, "WEAPON_SPRITE_COLOR"))
				ParseWarmupWeaponSpriteColor(value);
			if (equal(key, "RESULTS_FADE_ALPHA"))
				g_iWarmupResultsFadeAlpha = clamp(str_to_num(value), 0, 255);
			if (equal(key, "LEADER_MODE_ENABLED"))
				g_bLeaderModeEnabled = bool:clamp(str_to_num(value), 0, 1);
			if (equal(key, "FIRST_KILL_REWARD"))
				g_iFirstKillReward = clamp(str_to_num(value), 0, 16000);
			if (equal(key, "LEADER_KILL_REWARD_START"))
				g_iLeaderKillRewardStart = clamp(str_to_num(value), 0, 16000);
			if (equal(key, "LEADER_KILL_REWARD_STEP"))
				g_iLeaderKillRewardStep = clamp(str_to_num(value), 0, 16000);
			if (equal(key, "LEADER_REWARD_GROW_BY_LEADER_KILL"))
				g_iLeaderRewardGrowByLeaderKill = clamp(str_to_num(value), 0, 16000);
		}
		
		case PLUGINS:
			ArrayPushString(g_aPlugins, fmt("%s.amxx", key));
		
		case WEAPS:
		{
			new aData[11][256], aWarm[WARM_STRUCT];
			new szWarmLine[256];

			copy(szWarmLine, charsmax(szWarmLine), key);
			if (!szWarmLine[0])
				copy(szWarmLine, charsmax(szWarmLine), value);

			new iParts = explode_string(szWarmLine, " | ", aData, sizeof(aData), charsmax(aData[]));
			if (iParts == 8 || iParts == 11)
			{
				copy(aWarm[GUNS], charsmax(aWarm[GUNS]), aData[0]);
				copy(aWarm[DESCRIPTION], charsmax(aWarm[DESCRIPTION]), aData[1]);
				aWarm[HEALTH] = floatmax(1.0, str_to_float(aData[2]));
				aWarm[PROTECTION_TIME] = str_to_float(aData[3]);
				aWarm[RESPAWN_TIME] = floatmax(0.1, str_to_float(aData[4]));
				aWarm[TIME] = str_to_num(aData[5]);
				aWarm[KEVLAR] = str_to_num(aData[6]);
				aWarm[FALL_DAMAGE] = str_to_num(aData[7]);

				if (iParts == 11)
				{
					copy(aWarm[MUSIC], charsmax(aWarm[MUSIC]), aData[8]);
					copy(aWarm[TRACK], charsmax(aWarm[TRACK]), aData[10]);
				}
				else
				{
					aWarm[MUSIC] = '^0';
					aWarm[TRACK] = '^0';
				}

				if (!file_exists(fmt("sound/%s", aWarm[MUSIC])) /* && containi(aWarm[MUSIC], ".mp3") != -1 no care */ )
				{
					aWarm[MUSIC] = '^0';
				}
				ArrayPushArray(g_aWarm, aWarm);
			}
		}

		case MUSIC_FILES:
		{
			new szTrackTitle[256], aMusicData[3][256];
			new szMusicKey[MAX_RESOURCE_PATH_LENGTH];
			BuildMusicConfigKey(key, szMusicKey, charsmax(szMusicKey));
			szTrackTitle[0] = '^0';
			new iParts = explode_string(value, " | ", aMusicData, sizeof(aMusicData), charsmax(aMusicData[]));

			if (iParts >= 1)
				copy(szTrackTitle, charsmax(szTrackTitle), aMusicData[0]);

			trim(szTrackTitle);
			if (!equal(szTrackTitle, "УКАЖИТЕ НАЗВАНИЕ ТРЕКА") && !equal(szTrackTitle, UNKNOWN_ARTIST_TITLE) && szTrackTitle[0])
			{
				NormalizeTrackTitle(szTrackTitle, charsmax(szTrackTitle));
				TrieSetString(g_tMusicTitle, szMusicKey, szTrackTitle);
			}

			if (iParts >= 2)
			{
				new iTrackDuration = str_to_num(aMusicData[1]);
				if (iTrackDuration > 0)
					TrieSetCell(g_tMusicDuration, szMusicKey, iTrackDuration);
			}

			TrieSetCell(g_tKnownMusicFiles, szMusicKey, 1);
		}
	}
	
	return true;
}

// Парсит цвет кольца подсветки из строки R G B.
stock ParseHighlightColor(const szValue[])
{
	new szColor[3][12];
	if (explode_string(szValue, " ", szColor, sizeof(szColor), charsmax(szColor[])) < 3)
		return;

	for (new i; i < sizeof(g_iHighlightColor); i++)
		g_iHighlightColor[i] = clamp(str_to_num(szColor[i]), 0, 255);
}

// Парсит цвет glow-подсветки модели из строки R G B.
stock ParseHighlightModelColor(const szValue[])
{
	new szColor[3][12];
	if (explode_string(szValue, " ", szColor, sizeof(szColor), charsmax(szColor[])) < 3)
		return;

	for (new i; i < sizeof(g_iHighlightModelColor); i++)
		g_iHighlightModelColor[i] = clamp(str_to_num(szColor[i]), 0, 255);
}

stock ParseWarmupWeaponSpriteColor(const szValue[])
{
	new szColor[3][12];
	if (explode_string(szValue, " ", szColor, sizeof(szColor), charsmax(szColor[])) < 3)
		return;

	for (new i; i < sizeof(g_iWarmupWeaponSpriteColor); i++)
		g_iWarmupWeaponSpriteColor[i] = clamp(str_to_num(szColor[i]), 0, 255);
}

/*top 5*/
// Сбрасывает статистику и рендер игрока при входе на сервер.
public client_putinserver(id)
{
	// начальные значения зашедшему игроку
	g_iPlayerDmg[id] = 0;
	g_iPlayerKills[id] = 0;
	g_iPlayerAward[id] = 0;
	ResetLeaderModelRendering(id);

	if (!g_bWarmupCompleted)
		ShowWarmupWeaponSprite(id);
}

// Сбрасывает лидера/рендер при выходе игрока.
public client_disconnected(id)
{
	if (id == g_iWarmupLeader)
		g_iWarmupLeader = 0;
	if (id == g_iHighlightedLeader)
		g_iHighlightedLeader = 0;

	ResetLeaderModelRendering(id);
}

// Накапливает урон атакующего.
public CBasePlayer_TakeDamage(const pevVictim, pevInflictor, const pevAttacker, Float:flDamage, bitsDamageType)
{
	if(pevVictim == pevAttacker || !IsPlayer(pevAttacker) || (bitsDamageType & DMG_BLAST))
		return HC_CONTINUE;

	if(rg_is_player_can_takedamage(pevVictim, pevAttacker))
		g_iPlayerDmg[pevAttacker] += floatround(flDamage);
	
	return HC_CONTINUE;
}

// Готовит топ игроков по урону/киллам и запускает показ результатов.
public fnCompareDamage()
{
	new iPlayers[MAX_PLAYERS], iNum, iPlayer;

	get_players(iPlayers, iNum, "h");
	g_iTopPlayersCount = iNum;
	g_iPlayerTop = 0;
	
	// цикл сбора инфы по всем игрокам
	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i];
		
		g_arrData[i][PLAYER_ID] = iPlayer;
		g_arrData[i][DAMAGE] = _:g_iPlayerDmg[iPlayer];
		g_arrData[i][KILLS] = _:g_iPlayerKills[iPlayer];
		g_arrData[i][AWARD] = _:g_iPlayerAward[iPlayer];
	}
	
	// сортировка массива
	SortCustom2D(g_arrData, sizeof(g_arrData), "SortRoundDamage");
	remove_task(TASK_HIGHLIGHT_LEADER);
	HideWarmupWeaponSpriteForAll();
	ResetWarmupLeaderModelRendering();
	g_iHighlightedLeader = 0;
	StripPlayersWeaponsBeforeWarmupResults();
	FreezePlayersBeforeWarmupResults();

	client_cmd(0, "spk sound/events/task_complete.wav");
	set_task(0.5, "ShowStats",.flags = "b");
	return PLUGIN_HANDLED;
}


// Замораживает игроков перед выводом итогов разминки.
stock FreezePlayersBeforeWarmupResults()
{
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");

	new Float:flZeroVelocity[3];
	for (new i; i < iNum; i++)
	{
		new id = iPlayers[i];
		set_entvar(id, var_velocity, flZeroVelocity);
		set_entvar(id, var_maxspeed, 1.0);
		set_entvar(id, var_flags, get_entvar(id, var_flags) | FL_FROZEN);
		ShowWarmupResultFade(id);
	}
}

// Накладывает затемнение экрана игроку во время итогов.
stock StripPlayersWeaponsBeforeWarmupResults()
{
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "h");

	for (new i; i < iNum; i++)
	{
		new id = iPlayers[i];
		if (!is_user_alive(id))
			continue;

		strip_user_weapons(id);
		set_pev(id, pev_weapons, 0);
		set_member(id, m_flNextAttack, get_gametime() + 8.0);
		set_entvar(id, var_viewmodel, "");
		set_entvar(id, var_weaponmodel, "");
	}
}

stock ShowWarmupResultFade(id)
{
	if (!g_iMsgScreenFade || g_iWarmupResultsFadeAlpha <= 0)
		return;

	message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id);
	write_short(1<<12);
	write_short(1<<12);
	write_short(0x0004); // FFADE_STAYOUT
	write_byte(0);
	write_byte(0);
	write_byte(0);
	write_byte(g_iWarmupResultsFadeAlpha);
	message_end();
}

// Снимает затемнение экрана у игрока.
stock ClearWarmupResultFade(id)
{
	if (!g_iMsgScreenFade)
		return;

	message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id);
	write_short(1<<10);
	write_short(0);
	write_short(0x0001); // FFADE_IN
	write_byte(0);
	write_byte(0);
	write_byte(0);
	write_byte(0);
	message_end();
}

// Размораживает игроков и очищает fade после итогов.
stock UnfreezePlayersAfterWarmupResults()
{
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");

	for (new i; i < iNum; i++)
	{
		new id = iPlayers[i];
		set_entvar(id, var_flags, get_entvar(id, var_flags) & ~FL_FROZEN);
		ClearWarmupResultFade(id);
	}
}

// функция сравнения для сортировки
// Функция сортировки игроков по урону (по убыванию).
public SortRoundDamage(const elem1[], const elem2[])
{
	if (elem1[KILLS] != elem2[KILLS])
		return (elem1[KILLS] < elem2[KILLS]) ? 1 : -1;

	if (elem1[DAMAGE] != elem2[DAMAGE])
		return (elem1[DAMAGE] < elem2[DAMAGE]) ? 1 : -1;

	return 0;
}

// Выдает денежные награды игрокам после рестарта раунда.
public CSGameRules_RestartRound_Post()
{
	if (!g_bWarmupRestartPending)
		return;

	UnfreezePlayersAfterWarmupResults();
	g_bWarmupRestartPending = false;

	new iPlayers[MAX_PLAYERS], iNum, iPlayer;
	
	get_players(iPlayers, iNum, "h");
	
	for(new i=0; i < iNum; i++)
	{
		iPlayer = g_arrData[i][PLAYER_ID];
		if(!is_user_connected(iPlayer) || !IsPlayer(iPlayer) || g_arrData[i][AWARD] <= 0)
		{
			// Награда не выдается невалидным/отключившимся игрокам.
			continue;
		}
		rg_add_account(g_arrData[i][PLAYER_ID], g_arrData[i][AWARD], AS_ADD, true);
		g_arrData[i][AWARD] = 0;
	}
}

// Пошагово выводит DHUD-таблицу победителей разминки и завершает warmup.
public ShowStats()
{
	if (g_iPlayerTop >= g_iTopPlayersCount || g_iPlayerTop >= sizeof(g_arrData))
	{
		FinishWarmupAndRestart();
		return;
	}

	new szName[MAX_NAME_LENGTH];
	
	new iPlayer = g_arrData[g_iPlayerTop][PLAYER_ID];
	get_user_name(iPlayer, szName, charsmax(szName));

	new iWarmupAward = g_arrData[g_iPlayerTop][KILLS] * 50 + g_arrData[g_iPlayerTop][DAMAGE];
	new iLeaderAward = g_iPlayerAward[iPlayer];
	new iTotalAward = iWarmupAward + iLeaderAward;
	g_arrData[g_iPlayerTop][AWARD] = iTotalAward;
	new iCount = g_iPlayerTop + 1;

	switch(g_iCounter)
	{
		case 0:
		{
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.15, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "ПОБЕДИТЕЛИ РАЗМИНКИ");
			g_iCounter++;
		}
		case 1..3:{g_iCounter++;}
		case 4:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.20, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d + %d = %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], iWarmupAward, iLeaderAward, iTotalAward);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 5:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.25, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d + %d = %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], iWarmupAward, iLeaderAward, iTotalAward);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 6:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.30, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d + %d = %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], iWarmupAward, iLeaderAward, iTotalAward);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 7:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.35, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d + %d = %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], iWarmupAward, iLeaderAward, iTotalAward);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 8:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.40, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d + %d = %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], iWarmupAward, iLeaderAward, iTotalAward);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 9..11:
		{
			g_iCounter++;
		}
		case 12:
		{
			ClearDHUDMessages();
			g_iCounter++;
		}
		case 13..15:
		{
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.45, .effects = 0, .fxtime = 0.0, .holdtime = 5.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "ПЕРЕЗАГРУЗКА");
			g_iCounter++;
		}
		case 16:
		{
			FinishWarmupAndRestart();
		}
		default:
		{
			FinishWarmupAndRestart();
		}
	}
}

stock FinishWarmupAndRestart()
{
	remove_task(0);
	remove_task(TASK_HIGHLIGHT_LEADER);
	HideWarmupWeaponSpriteForAll();
	ResetWarmupLeaderModelRendering();
	g_bWarmupRestartPending = true;
	g_bWarmupCompleted = true;
	g_bFirstKillHappened = false;
	g_iWarmupLeader = 0;
	g_iHighlightedLeader = 0;
	g_iCounter = 0;
	g_iPlayerTop = 0;
	DisableHookChain(g_hDropPlayerItem);
	DisableHookChain(g_hOnSpawnEquip);

	if (g_pCvar[AUTO_AMMO])
		DisableHookChain(g_hKilled);

	for (new i; i < sizeof(g_eCvarsToDisable); i++)
		set_pcvar_string(get_cvar_pointer(g_eCvarsToDisable[i][0]), g_pDefaultCvars[i]);

	if (g_pCvar[PAUSE_STATS])
	{
		set_cvar_num("csstats_pause", 0);
		set_cvar_num("aes_track_pause", 0);
	}

	for (new i; i < ArraySize(g_aPlugins); i++)
		unpause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));

	ClearDHUDMessages();

	set_cvar_num("sv_restart", 1);
	set_cvar_num("sv_maxspeed", g_iOriginal_sv_maxspeed);
	client_cmd(0, "stopsound; mp3 stop");
}

//	Очистка DHUD сообщений
// Очищает все каналы DHUD сообщений.
stock ClearDHUDMessages()
        for (new iDHUD = 0; iDHUD < 8; iDHUD++)
                show_dhudmessage(0, ""); 

// Сбрасывает рендер игрока к стандартному виду.
stock ResetLeaderModelRendering(id)
{
	if (!IsPlayer(id) || !is_user_connected(id))
		return;

	set_user_rendering(id);
}

// Сбрасывает рендер у всех игроков на сервере.
stock ResetWarmupLeaderModelRendering()
{
	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "h");

	for (new i; i < iNum; i++)
		ResetLeaderModelRendering(iPlayers[i]);
}
