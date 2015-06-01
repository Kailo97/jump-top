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

#pragma newdecls required

#define TABLENAME "jumptop"
#define STEAMID_LEN 20

// Log switch
public const bool g_bLog = true;

Database g_db;
ConVar g_confname;
float g_distances[MAXPLAYERS+1][sizeof(g_saJumpTypes)];
float g_top10distances[sizeof(g_saJumpTypes)][11];
char g_top10Names[sizeof(g_saJumpTypes)][11][MAX_NAME_LENGTH+1];
char g_top10SteamIds[sizeof(g_saJumpTypes)][11][STEAMID_LEN+1];
int g_deletedtype;

public Plugin myinfo =
{
	name = "Jump Top",
	author = "Maxim 'Kailo' Telezhenko",
	description = "Jump leaderboard",
	version = "0.0.3-alpha-2-dev",
	url = "http://steamcommunity.com/id/kailo97/"
};

public void OnPluginStart()
{
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
	
	RegAdminCmd("sm_jtclear", Command_Clear, ADMFLAG_SLAY);
	
	// Connect to db
	char error[255], confname[64];
	g_confname.GetString(confname, 64);
	if (strlen(confname) == 0)
		confname = "default";
	g_db = SQL_Connect(confname, false, error, 255);
	if (g_db == null) {
		SetFailState("Could not connect to database: %s", error);
		//LogError("Could not connect: %s", error);
	}
	g_db.SetCharset("utf8");
	
	// Check table exist
	char querypart[512];
	for(JumpType type = Jump_LJ;type<Jump_End;type++)
		Format(querypart, 512, "%s, `%s` float(6,3) DEFAULT '0.000'", querypart, g_saJumpTypes[type]);
	char query[512];
	Format(query, 512, "CREATE TABLE IF NOT EXISTS `%s` (`steamid` varchar(%d) NOT NULL PRIMARY KEY, `name` varchar(%d) NOT NULL%s) DEFAULT CHARSET=utf8mb4;", TABLENAME, STEAMID_LEN, MAX_NAME_LENGTH, querypart);
	Log("%s", query);
	if (!SQL_FastQuery(g_db, query))
	{
		SQL_GetError(g_db, error, 255);
		LogError("Failed to query (error: %s)", error);
	}
	
	// Get first 10 places from DB
	for(JumpType type = Jump_LJ;type<Jump_End;type++) {
		Format(query, 512, "SELECT `steamid`, `name`, `%s` FROM `%s` ORDER BY `%s` DESC LIMIT 10;", g_saJumpTypes[type], TABLENAME, g_saJumpTypes[type]);
		Log("%s", query);
		Handle hndl = SQL_Query(g_db, query);
		if(hndl == null) {
			SQL_GetError(g_db, error, 255);
			LogError("Failed to query (error: %s)", error);
		} else {
			int end = SQL_GetRowCount(hndl);
			Log("Rows = %d", end);
			for(int i=1;i<=end;i++) {
				SQL_FetchRow(hndl);
				g_top10distances[type][i] = SQL_FetchFloat(hndl, 2);
				if(g_top10distances[type][i] == 0.0)
					break;
				SQL_FetchString(hndl, 0, g_top10SteamIds[type][i], STEAMID_LEN+1);
				SQL_FetchString(hndl, 1, g_top10Names[type][i], MAX_NAME_LENGTH+1);
			}
			CloseHandle(hndl);
		}
	}
	
	// Check for players on server
	for(int client=1;client<MaxClients;client++)
		if(IsClientInGame(client)) {
			GetPlayerRecords(client);
		}
}

public void OnPluginEnd()
{
	Log(" ");
}

public void T_NoResult(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
		LogError("Failed to query (error: %s)", error);
}

public void OnClientPutInServer(int client)
{
	GetPlayerRecords(client);
}

public void GetPlayerRecords(int client)
{
	Log("%N joined.", client);
	char query[255], steamid[STEAMID_LEN+1], select[255];
	GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
	for(JumpType type=Jump_LJ; type<Jump_End; type++)
		Format(select, 255, "%s, `%s`", select, g_saJumpTypes[type]);
	Format(query, 255, "SELECT `name`%s FROM `%s` WHERE `steamid` LIKE '%s';", select, TABLENAME, steamid);
	Log("%s", query);
	g_db.Query(T_ReadPlayerRecords, query, client);
}

public void T_ReadPlayerRecords(Database db, DBResultSet results, const char[] error, any client)
{
	if (results == null)
		LogError("Failed to query (error: %s)", error);
	else if(results.RowCount) {
		results.FetchRow();
		Log("%N", client);
		for(JumpType type=Jump_LJ; type<Jump_End; type++) {
			g_distances[client][type] = results.FetchFloat(view_as<int>(type));
			Log("%s %.3f", g_saJumpTypes[type], g_distances[client][type]);
		}
		Log(" ");
		char oldname[MAX_NAME_LENGTH+1], name[MAX_NAME_LENGTH+1];
		results.FetchString(0, oldname, MAX_NAME_LENGTH+1);
		GetClientName(client, name, MAX_NAME_LENGTH+1);
		if (!StrEqual(name, oldname)) {
			char escapedname[sizeof(name)*2+1], query[255], steamid[STEAMID_LEN+1];
			g_db.Escape(name, escapedname, sizeof(escapedname));
			GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
			Format(query, 255, "UPDATE `%s` SET `name` = '%s' WHERE `steamid` = '%s';", TABLENAME, escapedname, steamid);
			g_db.Query(T_NoResult, query);
		}
	} else {
		Log("%N not in DB. All distances = 0.000", client);
		for(JumpType type = Jump_LJ;type<Jump_End;type++)
			g_distances[client][type] = 0.0;
		char query[255], steamid[STEAMID_LEN+1];
		GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
		char name[MAX_NAME_LENGTH+1];
		GetClientName(client, name, MAX_NAME_LENGTH+1);
		char escapedname[sizeof(name)*2+1];
		g_db.Escape(name, escapedname, sizeof(escapedname));
		Format(query, 255, "INSERT INTO `%s` (`steamid`, `name`) VALUES ('%s', '%s');", TABLENAME, steamid, escapedname);
		Log("%s", query);
		g_db.Query(T_NoResult, query);
	}
}

public void OnJump(int client, JumpType type, float distance)
{
	if(distance > g_distances[client][type] && distance < 300.0) {
		g_distances[client][type] = distance;
		char query[255], steamid[STEAMID_LEN+1];
		GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
		Format(query, 255, "UPDATE `%s` SET `%s` = '%.3f' WHERE `steamid` = '%s';", TABLENAME, g_saJumpTypes[type], distance, steamid);
		Log("%s", query);
		SQL_TQuery(g_db, T_WritePlayerRecords, query);
		PrintToChat(client, "%t", "New Own Record", g_saPrettyJumpTypes[type], distance);
		
		//Player was in top 10?
		int lastrealplace;
		for(int place=1;place<=10;place++) {
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
					GetClientName(client, g_top10Names[type][place], MAX_NAME_LENGTH+1);
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
				int place = 10;
				while (distance > g_top10distances[type][place-1] && place != 1) {
					g_top10distances[type][place] = g_top10distances[type][place-1];
					g_top10Names[type][place] = g_top10Names[type][place-1];
					g_top10SteamIds[type][place] = g_top10SteamIds[type][place-1];
					place--;
				}
				g_top10distances[type][place] = distance;
				GetClientName(client, g_top10Names[type][place], MAX_NAME_LENGTH+1);
				g_top10SteamIds[type][place] = steamid;
				PrintToChatAll("%t", "New Record", g_top10Names[type][place], g_saPrettyJumpTypes[type], g_top10distances[type][place], place);
				return;
			} else
				return;
		} else if(lastrealplace != 0) {
			int place = lastrealplace + 1;
			while (distance > g_top10distances[type][place-1] && place != 1) {
				g_top10distances[type][place] = g_top10distances[type][place-1];
				g_top10Names[type][place] = g_top10Names[type][place-1];
				g_top10SteamIds[type][place] = g_top10SteamIds[type][place-1];
				place--;
			}
			g_top10distances[type][place] = distance;
			GetClientName(client, g_top10Names[type][place], MAX_NAME_LENGTH+1);
			g_top10SteamIds[type][place] = steamid;
			PrintToChatAll("%t", "New Record", g_top10Names[type][place], g_saPrettyJumpTypes[type], g_top10distances[type][place], place);
			return;
		} else {
			g_top10distances[type][1] = distance;
			GetClientName(client, g_top10Names[type][1], MAX_NAME_LENGTH+1);
			g_top10SteamIds[type][1] = steamid;
			PrintToChatAll("%t", "New Record", g_top10Names[type][1], g_saPrettyJumpTypes[type], g_top10distances[type][1], 1);
			return;
		}
	}
}

public void T_WritePlayerRecords(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
		LogError("Failed to query (error: %s)", error);
}

public Action Command_Redict(int client, int args)
{
	ReplyToCommand(client, "Use /jumptop or /jt instead.");
}

public Action Command_ShowTop(int client, int args)
{
	Menu menu = CreateMenu(TopMenuHandler);
	menu.SetTitle("What Jump Type?");
	for(JumpType jumptype = Jump_LJ;jumptype<Jump_End;jumptype++)
		menu.AddItem(g_saJumpTypes[jumptype], g_saJumpTypes[jumptype]);
	menu.Display(client, 10);
 
	return Plugin_Handled;
}

public int TopMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		Panel panel = CreatePanel();
		panel.SetTitle(g_saJumpTypes[param2+1], false);
		for(int i=1;i<=10;i++) {
			char buffer[128];
			(i == 10) ? Format(buffer, 128, "%s%d  %.3f %s", (i < 10) ? "0" : "", i, g_top10distances[param2+1][i], g_top10Names[param2+1][i]) : Format(buffer, 128, "%s%d  %.3f %s\n", (i < 10) ? "0" : "", i, g_top10distances[param2+1][i], g_top10Names[param2+1][i]);
			panel.DrawText(buffer);
		}
		panel.Send(param1, TopPanelHandler, 10);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int TopPanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
    //nothing to do
}

public Action Command_ShowRecord(int client, int args)
{
	if (client == 0) {
		PrintToServer("It in-game cmd. You can't use it via console.");
		return Plugin_Handled;
	}
	if (GetCmdArgs() > 0) {
		char ArgString[MAX_NAME_LENGTH+1];
		GetCmdArgString(ArgString, sizeof(ArgString));
		if (strlen(ArgString) < 2 || strlen(ArgString) > 32) {
			ReplyToCommand(client, "Name need contain more 1 character.");
			return Plugin_Handled;
		}
		char EscapedArgString[sizeof(ArgString)*2+1];
		g_db.Escape(ArgString, EscapedArgString, sizeof(EscapedArgString));
		char query[255];
		Format(query, 255, "SELECT * FROM `%s` WHERE `name` RLIKE '%s';", TABLENAME, EscapedArgString);
		g_db.Query(T_FindPlayerRecord, query, client);
	} else {
		Panel panel = new Panel();
		char title[128];
		Format(title, 128, "%N's Records", client);
		panel.SetTitle(title, false);
		for(JumpType type=Jump_LJ; type<Jump_End; type++)
		{
			char buffer[128];
			(type == Jump_LJ) ? Format(buffer, 128, "%.3f %s", g_distances[client][type], g_saJumpTypes[type]) : Format(buffer, 128, "\n%.3f %s", g_distances[client][type], g_saJumpTypes[type]);
			panel.DrawText(buffer);
		}
		panel.Send(client, TopPanelHandler, 10);
	}
	
	return Plugin_Handled;
}

public void T_FindPlayerRecord(Database db, DBResultSet results, const char[] error, any client)
{
	if (results == null)
		LogError("Failed to query (error: %s)", error);
	else {
		switch (results.RowCount) {
			case 0: {
				PrintToChat(client, "No players with the same name.");
			}
			case 1: {
				results.FetchRow();
				Panel panel = new Panel();
				char namebuffer[MAX_NAME_LENGTH+1];
				results.FetchString(1, namebuffer, MAX_NAME_LENGTH+1);
				char title[128];
				Format(title, 128, "%s's Records", namebuffer);
				panel.SetTitle(title, false);
				for(JumpType type=Jump_LJ; type<Jump_End; type++)
				{
					char buffer[128];
					int field = 1+view_as<int>(type);
					(type == Jump_LJ) ? Format(buffer, 128, "%.3f %s", results.FetchFloat(field), g_saJumpTypes[type]) : Format(buffer, 128, "\n%.3f %s", results.FetchFloat(field), g_saJumpTypes[type]);
					panel.DrawText(buffer);
				}
				panel.Send(client, TopPanelHandler, 10);
			}
			default: {
				char names[512];
				for (int i=1; i<=results.RowCount; i++) {
					results.FetchRow();
					char namebuffer[MAX_NAME_LENGTH+1];
					results.FetchString(1, namebuffer, MAX_NAME_LENGTH+1);
					StrEqual(names, "") ? Format(names, 512, "%s", namebuffer) : Format(names, 512, "%s, %s", names, namebuffer);
				}
				PrintToChat(client, "Do more specific request. May be: %s", names);
			}
		}
	}
}

/*void ShowRecordPanel(int client, DataPack Pack=null)
{
	
}*/

public Action Command_Clear(int client, int args)
{
	Menu menu = CreateMenu(DeleteMenuHandler1);
	menu.SetTitle("What Jump Type?");
	for(JumpType jumptype = Jump_LJ;jumptype<Jump_End;jumptype++)
		menu.AddItem(g_saJumpTypes[jumptype], g_saJumpTypes[jumptype]);
	menu.Display(client, 10);
	
	return Plugin_Handled;
}

public int DeleteMenuHandler1(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		g_deletedtype = param2+1;
		Menu menu2 = CreateMenu(DeleteMenuHandler2);
		menu2.SetTitle("What Place?");
		for(int place=1;place<=10;place++)
		{
			char info[64], display[64];
			Format(info, 64, "%d", place);
			Format(display, 64, "%s%d %.3f %s", (place < 10) ? "0" : "", place, g_top10distances[param2+1][place], g_top10Names[param2+1][place]);
			menu2.AddItem(info, display);
		}
		menu2.Display(param1, 10);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public int DeleteMenuHandler2(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int place = param2+1;
		LogAction(param1, -1, "\"%L\" delete %d place (%s %.3f %s) from %s top.", param1, place, g_top10SteamIds[g_deletedtype][place], g_top10distances[g_deletedtype][place], g_top10Names[g_deletedtype][place], g_saPrettyJumpTypes[g_deletedtype]);
		for(int i=1;i<MaxClients;i++)
			if(IsClientInGame(i)) {
				char steamid[STEAMID_LEN+1];
				GetClientAuthId(i, AuthId_Steam2, steamid, STEAMID_LEN+1);
				if(!strcmp(steamid, g_top10SteamIds[g_deletedtype][place]))
					g_distances[i][g_deletedtype] = 0.0;
			}
		char query[255];
		Format(query, 255, "UPDATE `%s` SET `%s` = '0.000' WHERE `steamid` = '%s';", TABLENAME, g_saJumpTypes[g_deletedtype], g_top10SteamIds[g_deletedtype][place]);
		Log("%s", query);
		SQL_TQuery(g_db, T_DeletePlayerRecord1, query);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void T_DeletePlayerRecord1(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
		LogError("Failed to query (error: %s)", error);
	else {
		char query[255];
		Format(query, 512, "SELECT `steamid`, `name`, `%s` FROM `%s` ORDER BY `%s` DESC LIMIT 10;", g_saJumpTypes[g_deletedtype], TABLENAME, g_saJumpTypes[g_deletedtype]);
		Log("%s", query);
		SQL_TQuery(g_db, T_DeletePlayerRecord2, query);
	}
}

public void T_DeletePlayerRecord2(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null)
		LogError("Failed to query (error: %s)", error);
	else {
		for(int i=1;i<=10;i++) {
			g_top10distances[g_deletedtype][i] = 0.0;
			g_top10SteamIds[g_deletedtype][i] = "";
			g_top10Names[g_deletedtype][i] = "";
		}
		int end = SQL_GetRowCount(hndl);
		Log("Rows = %d", end);
		for(int i=1;i<=end;i++) {
			SQL_FetchRow(hndl);
			g_top10distances[g_deletedtype][i] = SQL_FetchFloat(hndl, 2);
			if(g_top10distances[g_deletedtype][i] == 0.0)
				break;
			SQL_FetchString(hndl, 0, g_top10SteamIds[g_deletedtype][i], STEAMID_LEN+1);
			SQL_FetchString(hndl, 1, g_top10Names[g_deletedtype][i], MAX_NAME_LENGTH+1);
		}
	}
}

// For Debug
void Log(const char[] fromat, any ...)
{
	if(!g_bLog)
		return;
	char logfile[512], buffer[1024];
	VFormat(buffer, 1024, fromat, 2);
	GetPluginFilename(null, logfile, 512);
	ReplaceString(logfile, 512, ".smx", "");
	Format(logfile, 512, "addons/sourcemod/logs/%s.logs.txt", logfile);
	LogToFileEx(logfile, "%s", buffer);
}