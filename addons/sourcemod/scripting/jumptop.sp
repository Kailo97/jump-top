// © Maxim "Kailo" Telezhenko, 2015
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>

#include <jumpstats>

#define TABLENAME "jumptop"
#define STEAMID_LEN 18
#define NAME_LEN 40

new Handle:g_db = INVALID_HANDLE;
new Handle:g_confname = INVALID_HANDLE;
new Float:g_distances[MAXPLAYERS+1][sizeof(g_saJumpTypes)];
new Float:g_top10distances[sizeof(g_saJumpTypes)][11];
new String:g_top10Names[sizeof(g_saJumpTypes)][11][NAME_LEN+1];
new String:g_top10SteamIds[sizeof(g_saJumpTypes)][11][STEAMID_LEN+1];

public Plugin:myinfo =
{
	name = "Jump Top",
	author = "Maxim 'Kailo' Telezhenko",
	description = "Jump leaderboard",
	version = "0.0.1-dev-alpha",
	url = "http://steamcommunity.com/id/kailo97/"
};

public OnPluginStart()
{
	Log(" ");
	Log("Plugin started.");
	
	LoadTranslations("jumptop.phrases");
	
	g_confname = CreateConVar("jumptop_confname", "", "Config name for SQL connect. If not stated — default.");
	AutoExecConfig(true);

	RegConsoleCmd("sm_ljtop", Command_Redict);
	RegConsoleCmd("sm_top", Command_Redict);
	RegConsoleCmd("sm_jumptop", Command_ShowTop);
	RegConsoleCmd("sm_jt", Command_ShowTop);
	RegConsoleCmd("sm_rec", Command_ShowRecord);
	RegConsoleCmd("sm_record", Command_ShowRecord);
	
	// Connect to db
	new String:error[255], String:confname[64];
	GetConVarString(g_confname, confname, 64);
	if (strlen(confname) == 0)
		confname = "default";
	g_db = SQL_Connect(confname, false, error, 255);
	if (g_db == INVALID_HANDLE) {
		LogError("Could not connect: %s", error);
	}
	
	// Check table exist
	new String:querypart[512];
	for(new JumpType:type = Jump_LJ;type<Jump_End;type++)
		Format(querypart, 512, "%s, `%s` float(6,3) DEFAULT '0.000'", querypart, g_saJumpTypes[type]);
	new String:query[512];
	Format(query, 512, "CREATE TABLE IF NOT EXISTS `%s` (`steamid` varchar(%d) NOT NULL PRIMARY KEY, `name` varchar(%d) NOT NULL%s) DEFAULT CHARSET=utf8mb4;", TABLENAME, NAME_LEN, STEAMID_LEN, querypart);
	Log("%s", query);
	if (!SQL_FastQuery(g_db, query))
	{
		SQL_GetError(g_db, error, 255);
		LogError("Failed to query (error: %s)", error);
	}
	
	// Get first 10 places from DB
	for(new JumpType:type = Jump_LJ;type<Jump_End;type++) {
		Format(query, 512, "SELECT `steamid`, `name`, `%s` FROM `%s` ORDER BY `%s` DESC LIMIT 10;", g_saJumpTypes[type], TABLENAME, g_saJumpTypes[type]);
		Log("%s", query);
		new Handle:hndl = SQL_Query(g_db, query);
		if(hndl == INVALID_HANDLE) {
			SQL_GetError(g_db, error, 255);
			LogError("Failed to query (error: %s)", error);
		} else {
			new end=SQL_GetRowCount(hndl);
			Log("Rows = %d", end);
			for(new i=1;i<=end;i++) {
				SQL_FetchRow(hndl);
				g_top10distances[type][i] = SQL_FetchFloat(hndl, 2);
				if(g_top10distances[type][i] == 0.0)
					break;
				SQL_FetchString(hndl, 0, g_top10SteamIds[type][i], STEAMID_LEN+1);
				SQL_FetchString(hndl, 1, g_top10Names[type][i], NAME_LEN+1);
			}
			CloseHandle(hndl);
		}
	}
}

public OnClientPutInServer(client)
{
	Log("%N joined.", client);
	new String:query[255], String:steamid[STEAMID_LEN+1], String:select[255];
	GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
	for(new JumpType:type = Jump_LJ;type<Jump_End;type++)
		(type == Jump_LJ) ? Format(select, 255, "`%s`", g_saJumpTypes[type]) : Format(select, 255, "%s, `%s`", select, g_saJumpTypes[type]);
	Format(query, 255, "SELECT %s FROM `%s` WHERE `steamid` LIKE '%s';", select, TABLENAME, steamid);
	Log("%s", query);
	SQL_TQuery(g_db, T_ReadPlayerRecords, query, client);
}

public T_ReadPlayerRecords(Handle:owner, Handle:hndl, const String:error[], any:data) // data = client
{
	if (hndl == INVALID_HANDLE)
		LogError("Failed to query (error: %s)", error);
	else if(SQL_GetRowCount(hndl)) {
		SQL_FetchRow(hndl);
		Log("%N", data);
		for(new JumpType:type = Jump_LJ;type<Jump_End;type++) {
			g_distances[data][type] = SQL_FetchFloat(hndl, _:type - 1);
			Log("%s %.3f", g_saJumpTypes[type], g_distances[data][type]);
		}
		Log(" ");
	} else {
		Log("%N not in DB. All distances = 0.000", data);
		for(new JumpType:type = Jump_LJ;type<Jump_End;type++)
			g_distances[data][type] = 0.0;
		new String:query[255], String:steamid[STEAMID_LEN+1];
		GetClientAuthId(data, AuthId_Steam2, steamid, STEAMID_LEN+1);
		Format(query, 255, "INSERT INTO `%s` (`steamid`, `name`) VALUES ('%s', '%N');", TABLENAME, steamid, data);
		Log("%s", query);
		SQL_TQuery(g_db, T_InsertPlayerRecords, query);
	}
}

public T_InsertPlayerRecords(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
		LogError("Failed to query (error: %s)", error);
}

public OnJump(client, JumpType:type, Float:distance)
{
	if(distance > g_distances[client][type]) {
		g_distances[client][type] = distance;
		new String:query[255], String:steamid[STEAMID_LEN+1];
		GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
		Format(query, 255, "UPDATE `%s` SET `%s` = '%.3f' WHERE `steamid` = '%s';", TABLENAME, g_saJumpTypes[type], distance, steamid);
		Log("%s", query);
		SQL_TQuery(g_db, T_WritePlayerRecords, query);
		PrintToChat(client, "%t", "New Own Record", g_saJumpTypes[type], distance);
		
		//Player was in top 10?
		new lastrealplace;
		for(new place=1;place<=10;place++) {
			// If player in top 10
			if (!strcmp(g_top10SteamIds[type][place], steamid)) {
				if(distance > g_top10distances[type][place]) {
					while (distance > g_top10distances[type][place-1] && place != 1) {
						g_top10distances[type][place] = g_top10distances[type][place-1];
						g_top10Names[type][place] = g_top10Names[type][place-1];
						g_top10SteamIds[type][place] = g_top10SteamIds[type][place-1];
						place--;
					}
					g_top10distances[type][place] = distance;
					GetClientName(client, g_top10Names[type][place], NAME_LEN+1);
					g_top10SteamIds[type][place] = steamid;
					PrintToChatAll("%t", "New Record", g_top10Names[type][place], g_saPrettyJumpTypes[type], g_top10distances[type][place], place);
					return;
				} else
					return;
			}
			if (strcmp("", steamid)) {
				lastrealplace = place;
			}
		}
		
		Log("lastrealplace = %d", lastrealplace);
		
		// If player not in top 10
		if(lastrealplace == 10) {
			if (distance > g_top10distances[type][lastrealplace]) {
				new place = 10;
				while (distance > g_top10distances[type][place-1] && place != 1) {
					g_top10distances[type][place] = g_top10distances[type][place-1];
					g_top10Names[type][place] = g_top10Names[type][place-1];
					g_top10SteamIds[type][place] = g_top10SteamIds[type][place-1];
					place--;
				}
				g_top10distances[type][place] = distance;
				GetClientName(client, g_top10Names[type][place], NAME_LEN+1);
				g_top10SteamIds[type][place] = steamid;
				PrintToChatAll("%t", "New Record", g_top10Names[type][place], g_saPrettyJumpTypes[type], g_top10distances[type][place], place);
				return;
			} else
				return;
		} else if(lastrealplace != 0) {
			new place = lastrealplace + 1;
			while (distance > g_top10distances[type][place-1] && place != 1) {
				g_top10distances[type][place] = g_top10distances[type][place-1];
				g_top10Names[type][place] = g_top10Names[type][place-1];
				g_top10SteamIds[type][place] = g_top10SteamIds[type][place-1];
				place--;
			}
			g_top10distances[type][place] = distance;
			GetClientName(client, g_top10Names[type][place], NAME_LEN+1);
			g_top10SteamIds[type][place] = steamid;
			PrintToChatAll("%t", "New Record", g_top10Names[type][place], g_saPrettyJumpTypes[type], g_top10distances[type][place], place);
			return;
		} else {
			g_top10distances[type][1] = distance;
			GetClientName(client, g_top10Names[type][1], NAME_LEN+1);
			g_top10SteamIds[type][1] = steamid;
			PrintToChatAll("%t", "New Record", g_top10Names[type][1], g_saPrettyJumpTypes[type], g_top10distances[type][1], 1);
			return;
		}
	}
}

public T_WritePlayerRecords(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
		LogError("Failed to query (error: %s)", error);
}

public Action:Command_Redict(client, args)
{
	ReplyToCommand(client, "Use /jumptop or /jt instead.");
}

public Action:Command_ShowTop(client, args)
{
	new Handle:menu = CreateMenu(TopMenuHandler);
	SetMenuTitle(menu, "What Jump Type?");
	for(new JumpType:jumptype = Jump_LJ;jumptype<Jump_End;jumptype++)
	{
		AddMenuItem(menu, g_saJumpTypes[jumptype], g_saJumpTypes[jumptype]);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 10);
 
	return Plugin_Handled;
}

public TopMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		new Handle:panel = CreatePanel();
		SetPanelTitle(panel, g_saJumpTypes[param2+1]);
		for(new i=1;i<=10;i++) {
			new String:buffer[128];
			(i == 10) ? Format(buffer, 128, "%s%d  %.3f %s", (i < 10) ? "0" : "", i, g_top10distances[param2+1][i], g_top10Names[param2+1][i]) : Format(buffer, 128, "%s%d  %.3f %s\n", (i < 10) ? "0" : "", i, g_top10distances[param2+1][i], g_top10Names[param2+1][i]);
			DrawPanelText(panel, buffer);
		}
		SendPanelToClient(panel, param1, TopPanelHandler, 10);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public TopPanelHandler(Handle:menu, MenuAction:action, param1, param2)
{
    //nothing to do
}

public Action:Command_ShowRecord(client, args)
{
	new Handle:panel = CreatePanel(), String:title[128];
	Format(title, 128, "%N's Records", client);
	SetPanelTitle(panel, title);
	for(new JumpType:type = Jump_LJ;type<Jump_End;type++)
	{
		new String:buffer[128];
		(type == Jump_LJ) ? Format(buffer, 128, "%.3f %s", g_distances[client][type], g_saJumpTypes[type]) : Format(buffer, 128, "\n%.3f %s", g_distances[client][type], g_saJumpTypes[type]);
		DrawPanelText(panel, buffer);
	}
	SendPanelToClient(panel, client, TopPanelHandler, 10);
 
	return Plugin_Handled;
}

// For Debug
public Log(const String:fromat[], any:...)
{
	new String:logfile[512], String:buffer[1024];
	VFormat(buffer, sizeof(buffer), fromat, 2);
	GetPluginFilename(INVALID_HANDLE, logfile, 512);
	ReplaceString(logfile, 512, ".smx", "");
	Format(logfile, 512, "addons/sourcemod/logs/%s.logs.txt", logfile);
	LogToFileEx(logfile, "%s", buffer);
}