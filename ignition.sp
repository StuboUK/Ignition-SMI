#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <csgocolors>
#include <clientprefs>
#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <updater>
#pragma semicolon 1
ConVar g_hCvar_Trail_Enable,
g_hCvar_Trail_AdminOnly,
g_hCvar_Trail_Duration,
g_hCvar_Trail_Fade_Duration,
g_hCvar_Trail_Width,
g_hCvar_Trail_End_Width,
g_hCvar_Trail_Per_Round;

Handle g_Cookie_Trail = null,
g_TrailTimer[MAXPLAYERS+1],
g_SpawnTimer[MAXPLAYERS+1];

float g_fCvar_Trail_Duration,
g_fCvar_Trail_Width,
g_fCvar_Trail_End_Width,
g_fPosition[MAXPLAYERS+1][3];

bool g_bCvar_Trail_Enable,
g_bCvar_Trail_AdminOnly,
g_bTrail[MAXPLAYERS+1] = { false, ... },
g_bSpamCheck[MAXPLAYERS+1] = { false, ... },
g_bTimerCheck[MAXPLAYERS+1] = { false, ... };

int g_iSpamCMD = 0,
g_iTrailIndex,
g_iTrailcolor[MAXPLAYERS+1][4],
g_iCvar_Trail_Fade_Duration,
g_iCvar_Trail_Per_Round,
g_iMatches[MAXPLAYERS+1],
g_iButtons[MAXPLAYERS+1],
g_iCookieTrail[MAXPLAYERS+1];

char TTag[][] = {"red", "orange", "yellow", "green", "blue", "purple", "pink", "cyan", "white", "none"};
char TTagCode[][] = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"};

#define CHAT_BANNER             "[Ignition]"
#define MAX_TCOLORS             10

new Handle:g_hDatabase = INVALID_HANDLE;
new String:g_sError[256];

ConVar line1;

public Action:ignition_say(int args)
{
	char arg[128];
	GetCmdArg(1, arg, sizeof(arg));
	PrintToChatAll(arg);
	return Plugin_Handled;
}


public Plugin:myinfo = {
	name        = "Ignition",
	author      = "StuboUK",
	description = "Used to connect Source Servers to Infrastructure",
	version     = "1.1"
};

public OnPluginStart()
{
	g_hDatabase = CreateConVar("sm_plugin_database", "default", "This is the name you will enter into databases.cfg");
	PrintToServer("[Ignition] #- We are online!");
	decl String:sDatabase[32];
	GetConVarString(g_hDatabase, sDatabase, sizeof(sDatabase));
	g_hDatabase = SQL_Connect(sDatabase, true, g_sError, sizeof(g_sError));
	RegServerCmd("ign_say", ignition_say);
	HookEvent("player_spawn", playerSpawn); // Hook Player Death
	
	if (g_hDatabase == INVALID_HANDLE)
	LogError("[SQL_Connect] Could not connect to database: %s", g_sError);
	
	LoadTranslations("common.phrases");

    CreateConVar( "sm_playertrails_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD );

    g_hCvar_Trail_Enable = CreateConVar("sm_trail_enable", "1", "Enable or Disable all features of the plugin.", _, true, 0.0, true, 1.0);
    g_hCvar_Trail_AdminOnly = CreateConVar("sm_trail_adminonly", "0", "Enable trails only for Admins (VOTE Flag).", _, true, 0.0, true, 1.0);
    g_hCvar_Trail_Duration = CreateConVar("sm_trail_duration", "1.0", "Duration of the trail.", _, true, 1.0, true, 100.0);
    g_hCvar_Trail_Fade_Duration = CreateConVar("sm_trail_fade_duration", "1", "Duration of the trail.", _, true, 1.0, true, 100.0);
    g_hCvar_Trail_Width = CreateConVar("sm_trail_width", "5.0", "Width of the trail.", _, true, 1.0, true, 100.0);
    g_hCvar_Trail_End_Width = CreateConVar("sm_trail_end_width", "1.0", "Width of the trail.", _, true, 1.0, true, 100.0);
    g_hCvar_Trail_Per_Round = CreateConVar("sm_trail_per_round", "5", "How many times per round a client can use the command.", _, true, 1.0, true, 100.0);
    g_Cookie_Trail = RegClientCookie("TrailColor", "TrailColor", CookieAccess_Protected);

    HookConVarChange(g_hCvar_Trail_Enable, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_AdminOnly, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_Duration, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_Fade_Duration, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_Width, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_End_Width, OnSettingsChange);
    HookConVarChange(g_hCvar_Trail_Per_Round, OnSettingsChange);

    AutoExecConfig(true, "playertrails");

    RegConsoleCmd("sm_trail", Command_Trail, "Opens a menu for players to choose their trail colors.");
    RegConsoleCmd("sm_trails", Command_Trail, "Opens a menu for players to choose their trail colors.");

    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && IsValidClient(i) && AreClientCookiesCached(i))
        {
            OnClientCookiesCached(i);
        }
    }

    UpdateConVars();

    if (GetEngineVersion() != Engine_CSGO)
    {
        SetFailState("ERROR: This plugin is designed only for CS:GO.");
    }

    if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public Action:playerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid")); 
    decl String:steamID[64]; 
    char dID[32];
	char team[32];
    char sQuery[256];
    char name[64];
    GetClientAuthId(client, AuthId_SteamID64, steamID, 55, true);
    new clientId = GetClientOfUserId(GetEventInt(event, "userid"));
	Format(sQuery, sizeof(sQuery), "SELECT did FROM `txsn`.`members` WHERE steamid64 = '%s';", steamID);
	
	DBResultSet query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, dID, sizeof(dID));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	Format(sQuery, sizeof(sQuery), "SELECT name FROM `txsn`.`members` WHERE did = '%s';", dID);	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, name, sizeof(team));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	SetClientName(client, name);
	
	Format(sQuery, sizeof(sQuery), "SELECT team FROM `txsn`.`teams` WHERE userid = '%s';", dID);	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, team, sizeof(team));
		} 
		
		/* Free the Handle */
		delete query;
	}

	if((StrEqual(team, "Green"))) {
		SetEntityHealth(clientId, 500);
		CS_SetClientClanTag(client, "Panacea");
		TrailSelection(client, 4, false);
		SetEntityRenderColor(client, 0, 255, 0);
	}
	if((StrEqual(team, "Blue"))) {
		SetEntityHealth(clientId, 100);
		CS_SetClientClanTag(client, "Elysium");
		TrailSelection(client, 5, false);
		SetEntityRenderColor(client, 0, 0, 255);
	}
	if((StrEqual(team, "Red"))) {
		SetEntityHealth(clientId, 100);
		CS_SetClientClanTag(client, "Nostromo");
		SetEntityRenderColor(client, 255, 0, 0);
		TrailSelection(client, 1, false);
	}
} 

public OnClientAuthorized(client)
{
	char steamID[32];
	char dID[32];
	char team[32];
	char sname[32];
	char dMSG[127];
	char kMSG[128];

	
	GetClientAuthId(client, AuthId_SteamID64, steamID, 55, true);
	GetClientName(client, sname, 32);
	
	char sQuery[256]; 
	Format(sQuery, sizeof(sQuery), "SELECT did FROM `txsn`.`members` WHERE steamid64 = '%s';", steamID);	
	
	DBResultSet query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
		
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, dID, sizeof(dID));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	
	Format(sQuery, sizeof(sQuery), "SELECT team FROM `txsn`.`teams` WHERE userid = '%s';", dID);	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, team, sizeof(team));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	
	
	Format(sQuery, sizeof(sQuery), "SELECT team FROM `txsn`.`teams` WHERE userid = '%s';", dID);	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, team, sizeof(team));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	if(StrEqual(dID, "")){
		Format(kMSG, sizeof(kMSG), "Please do !steamid64 %s in the Ignition Channel and then rejoin", steamID);
		KickClient(client, kMSG);
		Format(kMSG, sizeof(kMSG), "%s, Please do !steamid64 %s in <#504478523654799361> and then rejoin.", sname, steamID);
		IGN_DGENMessage(kMSG);
		return;
	}
	if((StrEqual(team, "Green"))) {
		Format(team, sizeof(team), "Panacea");
		Format(dMSG, sizeof(dMSG), "*** PANACEA MEMBER <@%s> JOINED CS:GO OPERATION SERVER - http://txsn.uk/joinoperation.php***", dID);	
		IGN_DGENMessage(dMSG);
	}
	if((StrEqual(team, "Blue"))) {
		Format(team, sizeof(team), "Elysium");
		Format(dMSG, sizeof(dMSG), "*** ELYSIUM MEMBER <@%s> JOINED CS:GO OPERATION SERVER - http://txsn.uk/joinoperation.php***", dID);	
		IGN_DGENMessage(dMSG);
	}
	if((StrEqual(team, "Red"))) {
		Format(team, sizeof(team), "Nostromo");
		Format(dMSG, sizeof(dMSG), "*** NOSTROMO MEMBER <@%s> JOINED CS:GO OPERATION SERVER - http://txsn.uk/joinoperation.php***", dID);	
		IGN_DGENMessage(dMSG);
	}
}

public SQL_Callback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	LogError("There's an error: %s", error);
}

public IGN_DMessage(const char msg[128])
{
	new String:sQuery[512]; 
	Format(sQuery, sizeof(sQuery), "INSERT INTO `txsn`.`tasks` (`taskname`, `arg1`, `arg2`) VALUES ('say', '759455406711111680', '%s');", msg); 
	SQL_TQuery(g_hDatabase, SQL_Callback, sQuery);
}

public IGN_DGENMessage(const char msg[128])
{
	new String:sQuery[512]; 
	Format(sQuery, sizeof(sQuery), "INSERT INTO `txsn`.`tasks` (`taskname`, `arg1`, `arg2`) VALUES ('say', '504467832587812877', '%s');", msg); 
	SQL_TQuery(g_hDatabase, SQL_Callback, sQuery);
}

public IGN_GrantTP(const char dID[32])
{
	new String:sQuery[256]; 
	Format(sQuery, sizeof(sQuery), "INSERT INTO `txsn`.`tasks` (`taskname`, `assocuser`, `arg2`) VALUES ('granttp', '%s', '2');", dID); 
	SQL_TQuery(g_hDatabase, SQL_Callback, sQuery);
}

public IGN_GrantXP(const char dID[32])
{
	new String:sQuery[256]; 
	Format(sQuery, sizeof(sQuery), "INSERT INTO `txsn`.`tasks` (`taskname`, `assocuser`, `arg2`) VALUES ('grantxp', '%s', '5');", dID); 
	SQL_TQuery(g_hDatabase, SQL_Callback, sQuery);
}

public IGN_GrantTPP(const char dID[32])
{
	new String:sQuery[256]; 
	Format(sQuery, sizeof(sQuery), "INSERT INTO `txsn`.`tasks` (`taskname`, `assocuser`, `arg2`) VALUES ('granttp', '%s', '8');", dID); 
	SQL_TQuery(g_hDatabase, SQL_Callback, sQuery);
}


public void OnConfigsExecuted()
{
    UpdateConVars();
}

public void OnLibraryAdded(const String:name[])
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnLibraryRemoved(const String:name[])
{
    if (StrEqual(name, "updater"))
    {
        Updater_RemovePlugin();
    }
}

public void OnMapStart()
{
    g_iTrailIndex = PrecacheModel(MODEL_TRAIL, true);
}

public void OnClientCookiesCached(int client)
{
    char CookieTrail[64];
    GetClientCookie(client, g_Cookie_Trail, CookieTrail, sizeof(CookieTrail));
    if (StringToInt(CookieTrail) <= -1)
    {
        g_iCookieTrail[client] = 0;
    }
    else
    {
        g_iCookieTrail[client] = StringToInt(CookieTrail);
    }
}

public void OnClientPutInServer(int client)
{
    g_fPosition[client] = view_as<float>({0.0, 0.0, 0.0});
    g_iButtons[client] = 0;
    g_iMatches[client] = 0;
}

public void OnClientPostAdminCheck(int client)
{
    if (IsFakeClient(client))
        return;

    if (g_iCookieTrail[client] > 0)
    {
        g_bTrail[client] = true;
    }
    else
    {
        g_bTrail[client] = false;
    }
}

public void OnClientDisconnect(int client)
{
    if (AreClientCookiesCached(client))
    {
        char CookieTrail[64];
        Format(CookieTrail, sizeof(CookieTrail), "%i", g_iCookieTrail[client]);
        SetClientCookie(client, g_Cookie_Trail, CookieTrail);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && g_bCvar_Trail_Enable && g_bTrail[client] && (GetClientTeam(client) != CS_TEAM_SPECTATOR))
    {
        if (g_bCvar_Trail_AdminOnly)
        {
            if (!CheckCommandAccess(client, "sm_playertrails_override", ADMFLAG_RESERVATION))
            {
                g_bTrail[client] = false;
                return Plugin_Handled;
            }
        }

        g_iSpamCMD = 0;
        if (IsValidClient(client))
        {
            GetClientAbsOrigin(client, g_fPosition[client]);
            g_iButtons[client] = GetClientButtons(client);
            g_iMatches[client] = 0;
            g_bTimerCheck[client] = false;
            g_SpawnTimer[client] = CreateTimer(1.0, Timer_TrailsCheck, GetClientSerial(client), TIMER_REPEAT);
        }
        if (g_TrailTimer[client] == null)
        {
            CreateTimer(1.5, Timer_SpawnTrail, GetClientSerial(client));
        }
    }
    return Plugin_Handled;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client) && g_bCvar_Trail_Enable && g_bTrail[client])
    {
        g_iSpamCMD = 0;
        if (IsValidClient(client))
        {
            if (g_SpawnTimer[client] != null)
            {
                ResetTimer(g_SpawnTimer[client]);
                ResetTimer(g_TrailTimer[client]);
            }
        }
    }

    char vdID[32];
	char vteam[32];
	char adID[32];
	char ateam[32];
	char steamID[32];
    char sQuery[256];
    
    GetClientAuthId(client, AuthId_SteamID64, steamID, 55, true);
    Format(sQuery, sizeof(sQuery), "SELECT did FROM `txsn`.`members` WHERE steamid64 = '%s';", steamID);
	
	client = GetClientOfUserId(event.GetInt("userid")); 
	DBResultSet query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, vdID, sizeof(vdID));
		} 
		
		/* Free the Handle */
		delete query;
	}

	
	Format(sQuery, sizeof(sQuery), "SELECT team FROM `txsn`.`teams` WHERE userid = '%s';", vdID);	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, vteam, sizeof(vteam));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	client = GetClientOfUserId(event.GetInt("attacker"));
	GetClientAuthId(client, AuthId_SteamID64, steamID, 55, true);
	Format(sQuery, sizeof(sQuery), "SELECT did FROM `txsn`.`members` WHERE steamid64 = '%s';", steamID);
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, adID, sizeof(adID));
		} 
		
		/* Free the Handle */
		delete query;
	}

	
	Format(sQuery, sizeof(sQuery), "SELECT team FROM `txsn`.`teams` WHERE userid = '%s';", adID);	
	
	query = SQL_Query(g_hDatabase, sQuery);
	if (query == null)
	{
		char error[255];
		SQL_GetError(g_hDatabase, error, sizeof(error));
		PrintToServer("Failed to query (error: %s)", error);
	} 
	else 
	{
		if (SQL_FetchRow(query))
		{
			SQL_FetchString(query, 0, ateam, sizeof(ateam));
		} 
		
		/* Free the Handle */
		delete query;
	}
	
	if((StrEqual(ateam, "Green"))) {
		Format(ateam, sizeof(ateam), "Panacea");
		
	}
	if((StrEqual(ateam, "Blue"))) {
		Format(ateam, sizeof(ateam), "Elysium");
	}
	if((StrEqual(ateam, "Red"))) {
		Format(ateam, sizeof(ateam), "Nostromo");
	}
	
	if((StrEqual(vteam, "Green"))) {
		Format(vteam, sizeof(vteam), "Panacea");
	}
	if((StrEqual(vteam, "Blue"))) {
		Format(vteam, sizeof(vteam), "Elysium");
	}
	if((StrEqual(vteam, "Red"))) {
		Format(vteam, sizeof(vteam), "Nostromo");
	}
	
	char dMSG[128];
	if(StrEqual(ateam, "Elysium") && StrEqual(vteam, "Nostromo")) {
		IGN_GrantTP(adID);
	}
	if(StrEqual(ateam, "Nostromo") && StrEqual(vteam, "Elysium")) {
		IGN_GrantTP(adID);
	}
	if(StrEqual(ateam, "Elysium") && StrEqual(vteam, "Panacea")) {
		Format(dMSG, sizeof(dMSG), "***:small_blue_diamond: <@%s> has killed Panacea member <@%s> and gained 8TP***", adID, vdID);	
		IGN_DMessage(dMSG);
		IGN_GrantTPP(adID);
	}
	if(StrEqual(ateam, "Nostromo") && StrEqual(vteam, "Panacea")) {
		Format(dMSG, sizeof(dMSG), "***:small_red_triangle_down: <@%s> has killed Panacea member <@%s> and gained 8TP***", adID, vdID);	
		IGN_DMessage(dMSG);
		IGN_GrantTPP(adID);
	}
	IGN_GrantXP(adID);
    return Plugin_Handled;
}

public int MenuHandler1(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));
            TrailSelection(param1, StringToInt(info), false);
        }

        case MenuAction_End:
        {
            delete menu;
        }
    }

    return;
}

public Action Command_Trail(int client, int args)
{
    if (!g_bCvar_Trail_Enable)
        return Plugin_Handled;

    if (!IsValidClient(client))
    {
        CPrintToChat(client, "%s {red}ERROR{default}: You must be alive and not a spectator!", CHAT_BANNER);
        return Plugin_Handled;
    }

    if (g_bCvar_Trail_AdminOnly)
    {
        if (!CheckCommandAccess(client, "sm_playertrails_override", ADMFLAG_RESERVATION))
        {
            CPrintToChat(client, "%s {red}ERROR{default}: Only admins may use this command.", CHAT_BANNER);
            return Plugin_Handled;
        }
    }

    g_iSpamCMD += 1;
    if (g_iSpamCMD >= g_iCvar_Trail_Per_Round)
    {
        CPrintToChat(client, "%s {red}ERROR{default}: You must wait until next round!", CHAT_BANNER);
        return Plugin_Handled;
    }

    if (args < 1)
    {
        Menu menu = new Menu(MenuHandler1, MENU_ACTIONS_ALL);
        menu.SetTitle("Trail Colors Menu:");
        menu.AddItem("1", "red");
        menu.AddItem("2", "orange");
        menu.AddItem("3", "yellow");
        menu.AddItem("4", "green");
        menu.AddItem("5", "blue");
        menu.AddItem("6", "purple");
        menu.AddItem("7", "pink");
        menu.AddItem("8", "cyan");
        menu.AddItem("9", "white");
        menu.AddItem("0", "none");
        menu.ExitButton = false;
        menu.Display(client, MENU_TIME_FOREVER);

        return Plugin_Handled;
    }

    if (args == 1)
    {
        char text[24];
        GetCmdArgString(text, sizeof(text));
        StripQuotes(text);
        TrimString(text);

        for (int i = 0; i < MAX_TCOLORS; i++)
        {
            if (StrContains(text, TTag[i], false) == -1)
                continue;

            ReplaceString(text, 24, TTag[i], TTagCode[i], false);
        }
        TrailSelection(client, StringToInt(text), false);
    }

    if (args > 2)
    {
        CReplyToCommand(client, "{green}Usage{default}: sm_trail <color> [{red}red, {darkorange}orange, {orange}yellow, {green}green, {blue}blue, {purple}purple, {pink}pink, {lightblue}cyan, {default}white, none]");
        return Plugin_Handled;
    }

    return Plugin_Handled;
}

public Action Timer_SpawnTrail(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!IsValidClient(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    TrailSelection(client, g_iCookieTrail[client], true);

    return Plugin_Handled;
}

public Action Timer_CreateTrail(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!IsValidClient(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    if (!g_bTrail[client])
        return Plugin_Stop;

    if (g_bSpamCheck[client])
        return Plugin_Stop;

    if (g_TrailTimer[client] != null)
        ResetTimer(g_TrailTimer[client]);

    g_bSpamCheck[client] = true;
    int ent = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(ent))
        ent = client;

    TE_SetupBeamFollow(client, g_iTrailIndex, 0, g_fCvar_Trail_Duration, g_fCvar_Trail_Width, g_fCvar_Trail_End_Width, g_iCvar_Trail_Fade_Duration, g_iTrailcolor[client]);
    TE_SendToAll();

    return Plugin_Handled;
}

public Action Timer_TrailsCheck(Handle Timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!IsValidClient(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    if (g_bTimerCheck[client])
        return Plugin_Stop;

    if (g_bCvar_Trail_Enable && g_bTrail[client])
    {
        if (g_bCvar_Trail_AdminOnly)
        {
            if (!CheckCommandAccess(client, "sm_playertrails_override", ADMFLAG_RESERVATION))
            {
                CPrintToChat(client, "%s {red}ERROR{default}: You do not have access to trails!", CHAT_BANNER);
                return Plugin_Continue;
            }
        }

        float fPosition[3];
        GetClientAbsOrigin(client, fPosition);
        int iButtons = GetClientButtons(client);

        if (!bVectorsEqual(fPosition, g_fPosition[client]))
        {
            g_iMatches[client] += 1;
        }

        if (iButtons == g_iButtons[client])
        {
            g_iMatches[client] += 1;
        }

        if (g_iMatches[client] < 2)
        {
            g_iMatches[client] = 0;
        }

        if (g_iMatches[client] >= 4)
        {
            g_iMatches[client] = 0;
            g_bSpamCheck[client] = false;
            g_bTimerCheck[client] = true;
            CreateTimer(g_fCvar_Trail_Duration, Timer_TrailCooldown, GetClientSerial(client));
            CreateTrails(client);
        }
    }

    g_SpawnTimer[client] = null;

    return Plugin_Continue;
}

public Action Timer_TrailCooldown(Handle Timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!IsValidClient(client))
        return Plugin_Stop;

    if (!IsPlayerAlive(client))
        return Plugin_Stop;

    g_bTimerCheck[client] = false;

    return Plugin_Handled;
}

public OnSettingsChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_hCvar_Trail_Enable)
        g_bCvar_Trail_Enable = StringToInt(newValue) ? true : false;
    else if (convar == g_hCvar_Trail_AdminOnly)
        g_bCvar_Trail_AdminOnly = StringToInt(newValue) ? true : false;
    else if (convar == g_hCvar_Trail_Duration)
        g_fCvar_Trail_Duration = StringToFloat(newValue);
    else if (convar == g_hCvar_Trail_Fade_Duration)
        g_iCvar_Trail_Fade_Duration = StringToInt(newValue);
    else if (convar == g_hCvar_Trail_Width)
        g_fCvar_Trail_Width = StringToFloat(newValue);
    else if (convar == g_hCvar_Trail_End_Width)
        g_fCvar_Trail_End_Width = StringToFloat(newValue);
    else if (convar == g_hCvar_Trail_Per_Round)
        g_iCvar_Trail_Per_Round = StringToInt(newValue);
}

void TrailSelection(int client, int arg, bool spawned)
{
    g_iCookieTrail[client] = arg;
    char buffer[64];
    Format(buffer, sizeof(buffer), "%i", arg);
    SetClientCookie(client, g_Cookie_Trail, buffer);
    g_iTrailcolor[client][3] = 255;

    switch(g_iCookieTrail[client])
    {
        case 0:
        {
            g_bTrail[client] = false;
        }
        case 1:
        {
            g_iTrailcolor[client][0] = 255;
            g_iTrailcolor[client][1] = 0;
            g_iTrailcolor[client][2] = 0;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 2:
        {
            g_iTrailcolor[client][0] = 255;
            g_iTrailcolor[client][1] = 128;
            g_iTrailcolor[client][2] = 0;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 3:
        {
            g_iTrailcolor[client][0] = 255;
            g_iTrailcolor[client][1] = 255;
            g_iTrailcolor[client][2] = 0;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 4:
        {
            g_iTrailcolor[client][0] = 0;
            g_iTrailcolor[client][1] = 255;
            g_iTrailcolor[client][2] = 0;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 5:
        {
            g_iTrailcolor[client][0] = 0;
            g_iTrailcolor[client][1] = 0;
            g_iTrailcolor[client][2] = 255;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 6:
        {
            g_iTrailcolor[client][0] = 127;
            g_iTrailcolor[client][1] = 0;
            g_iTrailcolor[client][2] = 127;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 7:
        {
            g_iTrailcolor[client][0] = 255;
            g_iTrailcolor[client][1] = 0;
            g_iTrailcolor[client][2] = 127;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 8:
        {
            g_iTrailcolor[client][0] = 0;
            g_iTrailcolor[client][1] = 255;
            g_iTrailcolor[client][2] = 255;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
        case 9:
        {
            g_iTrailcolor[client][0] = 255;
            g_iTrailcolor[client][1] = 255;
            g_iTrailcolor[client][2] = 255;
            g_bTrail[client] = true;
            CreateTrails(client);
            if (!spawned) {
            }
        }
    }
}

void CreateTrails(int client)
{
    g_TrailTimer[client] = CreateTimer(0.1, Timer_CreateTrail, GetClientSerial(client));
}

void ResetTimer(Handle Timer)
{
    KillTimer(Timer);
    Timer = null;
}

stock bool bVectorsEqual(float[3] v1, float[3] v2)
{
    return (v1[0] == v2[0] && v1[1] == v2[1] && v1[2] == v2[2]);
}

stock bool IsValidClient(int client)
{
    if (!(0 < client <= MaxClients)) return false;
    if (!IsClientConnected(client)) return false;
    if (!IsClientInGame(client)) return false;
    if (IsFakeClient(client)) return false;
    return true;
}

UpdateConVars()
{
    g_bCvar_Trail_Enable = GetConVarBool(g_hCvar_Trail_Enable);
    g_bCvar_Trail_AdminOnly = GetConVarBool(g_hCvar_Trail_AdminOnly);
    g_fCvar_Trail_Duration = GetConVarFloat(g_hCvar_Trail_Duration);
    g_iCvar_Trail_Fade_Duration = GetConVarInt(g_hCvar_Trail_Fade_Duration);
    g_fCvar_Trail_Width = GetConVarFloat(g_hCvar_Trail_Width);
    g_fCvar_Trail_End_Width = GetConVarFloat(g_hCvar_Trail_End_Width);
    g_iCvar_Trail_Per_Round = GetConVarInt(g_hCvar_Trail_Per_Round);
} 