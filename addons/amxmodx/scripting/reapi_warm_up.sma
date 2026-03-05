#include <amxmisc>
#include <fakemeta>
#include <reapi>

#define PLUGIN "[ReAPI] Warm UP"
#define VERSION "1.0.0.0-23.11.2025"
#define AUTHOR "Emma Jule"
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
new bool:g_bHighlightEnabled = true;
new Float:g_flHighlightInterval = 5.0;
new g_iHighlightColor[3] = {255, 0, 0};

stock BuildMusicConfigKey(const szMusicPath[], szKey[], iKeyLen);


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

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR, URL, DESCRIPTIONPLUGIN);
	
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

public event_game_commencing()
{
	EnableHookChain(g_hCheckMapConditions);
	
	//
	for (new i = MaxClients; i > 0; --i)
		if (is_user_alive(i))
			set_member(i, m_bNotKilled, false);
}

public CSGameRules_CheckMapConditions()
{
	DisableHookChain(g_hCheckMapConditions);
	
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
	ArrayGetArray(g_aWarm, random(ArraySize(g_aWarm)), aWarm);
	
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
	if (g_bHighlightEnabled)
		set_task(g_flHighlightInterval, "Task_HighlightWarmupLeader", TASK_HIGHLIGHT_LEADER, .flags = "b");
	g_bFirstKillHappened = false;
	g_iWarmupLeader = 0;
	
	// 
	for (new i; i < ArraySize(g_aPlugins); i++)
		pause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));
	
	// Fallback: если папка с музыкой пуста, играем трек из конфигурации.
	if (!bRandomTrackPlayed && aWarm[MUSIC][0]) {
		client_cmd(0, "stopsound; mp3 stop; wait; mp3 play ^"sound/%s^"", aWarm[MUSIC]);
	}
}

public CBasePlayer_DropPlayerItem()
{
	SetHookChainReturn(ATYPE_INTEGER, NULLENT);
	return HC_SUPERCEDE;
}

public CBasePlayer_OnSpawnEquip(id)
{
	set_entvar(id, var_health, g_flMaxHealth);
	set_entvar(id, var_max_health, g_flMaxHealth);
}

public CBasePlayer_Killed(Victim, Attacker, gib)
{

	if(!is_user_connected(Victim) || !is_user_connected(Attacker) || Victim == Attacker || !IsPlayer(Attacker) || get_member(Victim, m_iTeam) == get_member(Attacker, m_iTeam) || get_member(Victim, m_bKilledByGrenade))
		return;
	
	g_iPlayerKills[Attacker]++;
	g_bFirstKillHappened = true;
	g_iWarmupLeader = GetWarmupLeaderByStats();

	new pWeapon = get_member(Attacker, m_pActiveItem);
	if (is_nullent(pWeapon) || ~CSW_ALL_GUNS & 1 << get_member(pWeapon, m_iId))
		return;
	
	//rg_instant_reload_weapons(Attacker, pWeapon);
}

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
		if(!g_szWarmUpTrack[0] || g_iWarmUpTrackTime <= 0){
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.04, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
			show_dhudmessage(0, "РАЗМИНКА ЗАКОНЧИТСЯ ЧЕРЕЗ %i СЕК", g_iCountDown);
		}else{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.04, .effects = 0, .fxtime = 0.0, .holdtime = 1.1, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "СЕЙЧАС ИГРАЕТ: %s", g_szWarmUpTrack);
			set_dhudmessage( .red = 0, .green = 255, .blue = 0, .x = -1.0, .y = 0.07, .effects = 0, .fxtime = 0.0, .holdtime = 1.0, .fadeintime = 0.0, .fadeouttime = 0.1);
			show_dhudmessage(0, "РАЗМИНКА ЗАКОНЧИТСЯ ЧЕРЕЗ %i СЕК", g_iCountDown);
		}

	}
}

public Task_HighlightWarmupLeader()
{
	if (!g_bFirstKillHappened)
		return;

	HighlightWarmupLeader();
}

stock HighlightWarmupLeader()
{
	new iLeader = g_iWarmupLeader;
	if (!IsPlayer(iLeader) || !is_user_alive(iLeader))
		iLeader = GetWarmupLeaderByStats();

	if (!IsPlayer(iLeader) || !is_user_alive(iLeader))
		return;

	g_iWarmupLeader = iLeader;

	new Float:vecOrigin[3], Float:vecRingTop[3];
	get_entvar(iLeader, var_origin, vecOrigin);

	vecRingTop[0] = vecOrigin[0];
	vecRingTop[1] = vecOrigin[1];
	vecRingTop[2] = vecOrigin[2];
	vecRingTop[2] += 170.0 + (float(g_iCountDown & 1) * 35.0);

	message_begin(MSG_ALL, SVC_TEMPENTITY);
	write_byte(TE_BEAMCYLINDER);
	engfunc(EngFunc_WriteCoord, vecOrigin[0]);
	engfunc(EngFunc_WriteCoord, vecOrigin[1]);
	engfunc(EngFunc_WriteCoord, vecOrigin[2] + 5.0);
	engfunc(EngFunc_WriteCoord, vecRingTop[0]);
	engfunc(EngFunc_WriteCoord, vecRingTop[1]);
	engfunc(EngFunc_WriteCoord, vecRingTop[2]);
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

stock GetWarmupLeaderByStats()
{
	new iLeader, iMaxDamage = -1, iMaxKills = -1;

	for (new id = 1; id <= g_iMaxPlayers; id++)
	{
		if (!is_user_connected(id) || !is_user_alive(id))
			continue;

		if (g_iPlayerDmg[id] > iMaxDamage || (g_iPlayerDmg[id] == iMaxDamage && g_iPlayerKills[id] > iMaxKills))
		{
			iMaxDamage = g_iPlayerDmg[id];
			iMaxKills = g_iPlayerKills[id];
			iLeader = id;
		}
	}

	return iLeader;
}

@restart() 
{
	set_cvar_num("sv_maxspeed", g_iOriginal_sv_maxspeed);
	client_cmd(0, "stopsound; mp3 stop");
	set_cvar_num("sv_restart", 1);
}

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


stock LoadWarmUpMusic()
{
	g_szMapWarmUpMusic[0] = '^0';
	ArrayClear(g_aMusicFilesOnDisk);

	new szFile[MAX_RESOURCE_PATH_LENGTH], FileType:iType;
	new szFolderPath[MAX_RESOURCE_PATH_LENGTH];
	formatex(szFolderPath, charsmax(szFolderPath), "sound/%s", g_szWarmUpMusicDir);

	new hDir = open_dir(szFolderPath, szFile, charsmax(szFile), iType);

	if (!hDir)
		return;

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
		GetTrackName(szMusicPath, szTrackTitle, iTitleLen);

	NormalizeTrackTitle(szTrackTitle, iTitleLen);
}

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
			copy(szTrackTitle, charsmax(szTrackTitle), "УКАЖИТЕ НАЗВАНИЕ ТРЕКА");

		if (iTrackDuration > 0)
			formatex(szNewEntry, charsmax(szNewEntry), "%s = %s | %d", szMusicKey, szTrackTitle, iTrackDuration);
		else
			formatex(szNewEntry, charsmax(szNewEntry), "%s = %s | УКАЖИТЕ ВРЕМЯ РАЗМИНКИ", szMusicKey, szTrackTitle);

		write_file(g_szWarmUpConfigPath, szNewEntry, -1);
	}

	ArrayDestroy(aLines);
}

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


stock bool:IsLikelyReadableTitle(const szText[])
{
	for (new i; szText[i] != '^0'; i++)
	{
		if (szText[i] < 32 || szText[i] > 126)
			return false;
	}

	return true;
}

stock ClampWarmTime(iTime)
{
	if (iTime < 10)
		return 10;
	if (iTime > 90)
		return 90;

	return iTime;
}

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

stock GetDefaultMusicDuration()
{
	new iWarmTime = str_to_num(g_szWarmUpTimeMode);
	if (iWarmTime >= 10 && iWarmTime <= 90)
		return iWarmTime;

	return 60;
}

ReadConfig()
{
	get_localinfo("amxx_basedir", g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath));
	add(g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath), "/");
	add(g_szWarmUpConfigPath, charsmax(g_szWarmUpConfigPath), WARMUP_CONFIG_FILE);
	
	if (!file_exists(g_szWarmUpConfigPath))
		return false;
	
	new INIParser:parser = INI_CreateParser();

	if (parser == Invalid_INIParser)
		return false;
	
	INI_SetReaders(parser, "values", "sections");
	INI_ParseFile(parser, g_szWarmUpConfigPath);
	INI_DestroyParser(parser);
	
	return true;
}

public bool:sections(INIParser:handle, const section[], bool:invalid_tokens, bool:close_bracket)
{
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
	
	return false;
}

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
			if (equal(key, "HIGHLIGHT_ENABLED"))
				g_bHighlightEnabled = bool:clamp(str_to_num(value), 0, 1);
			if (equal(key, "HIGHLIGHT_INTERVAL"))
				g_flHighlightInterval = floatclamp(str_to_float(value), 0.1, 5.0);
			if (equal(key, "HIGHLIGHT_COLOR"))
				ParseHighlightColor(value);
		}
		
		case PLUGINS:
			ArrayPushString(g_aPlugins, fmt("%s.amxx", key));
		
		case WEAPS:
		{
			new aData[11][256], aWarm[WARM_STRUCT];
			if (explode_string(key, " | ", aData, sizeof(aData), charsmax(aData[])) == 11)
			{
				copy(aWarm[GUNS], charsmax(aWarm[GUNS]), aData[0]);
				copy(aWarm[DESCRIPTION], charsmax(aWarm[DESCRIPTION]), aData[1]);
				aWarm[HEALTH] = floatmax(1.0, str_to_float(aData[2]));
				aWarm[PROTECTION_TIME] = str_to_float(aData[3]);
				aWarm[RESPAWN_TIME] = floatmax(0.1, str_to_float(aData[4]));
				aWarm[TIME] = str_to_num(aData[5]);
				aWarm[KEVLAR] = str_to_num(aData[6]);
				aWarm[FALL_DAMAGE] = str_to_num(aData[7]);
				copy(aWarm[MUSIC], charsmax(aWarm[MUSIC]), aData[8]);
				copy(aWarm[TRACK], charsmax(aWarm[TRACK]), aData[10]);
				
				
				
				if (file_exists(fmt("sound/%s", aWarm[MUSIC])) /* && containi(aWarm[MUSIC], ".mp3") != -1 no care */ )
				{
					precache_generic(fmt("sound/%s", aWarm[MUSIC]));
				} else {
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
			if (!equal(szTrackTitle, "УКАЖИТЕ НАЗВАНИЕ ТРЕКА") && szTrackTitle[0])
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

stock ParseHighlightColor(const szValue[])
{
	new szColor[3][12];
	if (explode_string(szValue, " ", szColor, sizeof(szColor), charsmax(szColor[])) < 3)
		return;

	for (new i; i < sizeof(g_iHighlightColor); i++)
		g_iHighlightColor[i] = clamp(str_to_num(szColor[i]), 0, 255);
}

/*top 5*/
public client_putinserver(id)
{
	// начальные значения зашедшему игроку
	g_iPlayerDmg[id] = 0;
	g_iPlayerKills[id] = 0;
	g_iPlayerAward[id] = 0;
}

public CBasePlayer_TakeDamage(const pevVictim, pevInflictor, const pevAttacker, Float:flDamage, bitsDamageType)
{
	if(pevVictim == pevAttacker || !IsPlayer(pevAttacker) || (bitsDamageType & DMG_BLAST))
		return HC_CONTINUE;
	
	if(rg_is_player_can_takedamage(pevVictim, pevAttacker))
		g_iPlayerDmg[pevAttacker] += floatround(flDamage);
	
	return HC_CONTINUE;
}

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

	client_cmd(0, "spk sound/events/task_complete.wav");
	set_task(0.5, "ShowStats",.flags = "b");
	return PLUGIN_HANDLED;
}

// функция сравнения для сортировки
public SortRoundDamage(const elem1[], const elem2[])
{
	// сравнение дамага
	return (elem1[DAMAGE] < elem2[DAMAGE]) ? 1 : (elem1[DAMAGE] > elem2[DAMAGE]) ? -1 : 0;
}

public CSGameRules_RestartRound_Post()
{
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
	}
}

public ShowStats()
{
	if (g_iPlayerTop >= g_iTopPlayersCount || g_iPlayerTop >= sizeof(g_arrData))
	{
		remove_task(0);
		remove_task(TASK_HIGHLIGHT_LEADER);
		g_bFirstKillHappened = false;
		g_iWarmupLeader = 0;
		g_iCounter = 0;
		g_iPlayerTop = 0;
		return;
	}

	new szName[MAX_NAME_LENGTH];
	
	get_user_name(g_arrData[g_iPlayerTop][PLAYER_ID], szName, charsmax(szName));
	new i_Award = g_arrData[g_iPlayerTop][AWARD] = g_arrData[g_iPlayerTop][KILLS] * 50 + g_arrData[g_iPlayerTop][DAMAGE];
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
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], i_Award);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 5:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.25, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], i_Award);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 6:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.30, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], i_Award);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 7:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.35, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], i_Award);
			client_cmd(0, "spk sound/weapons/deagle-1.wav");
			g_iCounter++;
			g_iPlayerTop++;
		}
		case 8:
		{
			set_dhudmessage( .red = 255, .green = 255, .blue = 255, .x = -1.0, .y = 0.40, .effects = 0, .fxtime = 0.0, .holdtime = 10.0, .fadeintime = 0.0, .fadeouttime = 0.0);
			show_dhudmessage(0, "%d: %s - УБИЙСТВА: %d - УРОН: %d - НАГРАДА: %d$", iCount, szName, g_arrData[g_iPlayerTop][KILLS], g_arrData[g_iPlayerTop][DAMAGE], i_Award);
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
			remove_task(0);
			remove_task(TASK_HIGHLIGHT_LEADER);
			g_bFirstKillHappened = false;
			g_iWarmupLeader = 0;
			g_iCounter = 0;
			g_iPlayerTop = 0;
			DisableHookChain(g_hDropPlayerItem);
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
			
			for (new i; i < ArraySize(g_aPlugins); i++)
			unpause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));
				
			ClearDHUDMessages();
			
			set_cvar_num("sv_restart", 1);
			set_cvar_num("sv_maxspeed", g_iOriginal_sv_maxspeed);
			client_cmd(0, "stopsound; mp3 stop");
		}
		default:
		{
			remove_task(0);
			remove_task(TASK_HIGHLIGHT_LEADER);
			g_bFirstKillHappened = false;
			g_iWarmupLeader = 0;
			g_iCounter = 0;
			g_iPlayerTop = 0;
			DisableHookChain(g_hDropPlayerItem);
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
			
			for (new i; i < ArraySize(g_aPlugins); i++)
			unpause("ac", fmt("%a", ArrayGetStringHandle(g_aPlugins, i)));
				
			ClearDHUDMessages();
			
			set_cvar_num("sv_restart", 1);
			set_cvar_num("sv_maxspeed", g_iOriginal_sv_maxspeed);
			client_cmd(0, "stopsound; mp3 stop");
		}
	}
}

//	Очистка DHUD сообщений
stock ClearDHUDMessages()
        for (new iDHUD = 0; iDHUD < 8; iDHUD++)
                show_dhudmessage(0, ""); 
