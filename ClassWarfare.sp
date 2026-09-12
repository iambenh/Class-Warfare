#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

#define PL_VERSION "0.3"

#define TF_CLASS_DEMOMAN		4
#define TF_CLASS_ENGINEER		9
#define TF_CLASS_HEAVY			6
#define TF_CLASS_MEDIC			5
#define TF_CLASS_PYRO				7
#define TF_CLASS_SCOUT			1
#define TF_CLASS_SNIPER			2
#define TF_CLASS_SOLDIER		3
#define TF_CLASS_SPY				8
#define TF_CLASS_UNKNOWN		0

#define TF_TEAM_BLU					3
#define TF_TEAM_RED					2

#define SIZE_OF_INT		2147483647		// without 0

//This code is based on the Class Restrictions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104

public Plugin:myinfo =
{
    name        = "Class Warfare",
    author      = "Tsunami,JonathanFlynn,Sound Fix by Phaiz, fixes by dumb dog",
    description = "Class Vs Class",
    version     = PL_VERSION,
    url         = "https://github.com/iambenh/Class-Warfare"
}

new g_iClass[MAXPLAYERS + 1];
new Handle:g_hEnabled;
new Handle:g_hFlags;
new Handle:g_hImmunity;
new Handle:g_hClassChangeInterval;
new Handle:g_hClassesPerTeam;
new Handle:g_hVotePercent;
new Handle:g_hRerollImmediate;
new Handle:g_hBlacklist1v1;
new Handle:g_hBlacklist2v2;

new bool:g_bVotedReroll[MAXPLAYERS + 1];
new g_iVotedMode[MAXPLAYERS + 1];
new Handle:g_hClassChangeTimer 	= INVALID_HANDLE;
new Float:g_hLimits[4][10];
new String:g_sSounds[10][24] = {"", "vo/scout_no03.mp3",   "vo/sniper_no04.mp3", "vo/soldier_no01.mp3",
    "vo/demoman_no03.mp3", "vo/medic_no03.mp3",  "vo/heavy_no02.mp3",
    "vo/pyro_no01.mp3",    "vo/spy_no02.mp3",    "vo/engineer_no03.mp3"};

static String:ClassNames[TFClassType][] = {"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer" };

new Handle:g_hVoteDelayTimer 		= INVALID_HANDLE;
new bool:g_bVoteAllowed = true;

new g_iBlueClass1;
new g_iRedClass1;

new g_iBlueClass2;
new g_iRedClass2;

new g_iClassesThisRound = 1;



new RandomizedThisRound = 0;

public OnPluginStart()
{
    CreateConVar("sm_classwarfare_version", PL_VERSION, "Class Warfare in TF2.", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

    g_hEnabled                                = CreateConVar("sm_classwarfare_enabled",       "1",  "Enable/disable the Class Warfare mod in TF2.");
    g_hFlags                                  = CreateConVar("sm_classwarfare_flags",         "",   "Admin flags for restricted classes in TF2.");
    g_hImmunity                               = CreateConVar("sm_classwarfare_immunity",      "0",  "Enable/disable admins being immune for restricted classes in TF2.");
    g_hClassChangeInterval                    = CreateConVar("sm_classwarfare_change_interval",   "0",  "Shuffle the classes every x minutes, 0 for round only");
    g_hClassesPerTeam                         = CreateConVar("sm_classwarfare_classes",       "1",  "Amount of classes per team (i.e 1v1, 2v2)", _, true, 1.0, true, 2.0);
    g_hVotePercent                            = CreateConVar("sm_classwarfare_vote_percent",  "60", "Percent of players that must type a vote command for it to pass", _, true, 1.0, true, 100.0);
    g_hRerollImmediate                        = CreateConVar("sm_classwarfare_reroll_immediate", "0", "Whether rerolls take place imediately", _, true, 0.0, true, 1.0);
    g_hBlacklist1v1                           = CreateConVar("sm_classwarfare_blacklist_1v1", "",   "Classes banned in 1v1");
    g_hBlacklist2v2                           = CreateConVar("sm_classwarfare_blacklist_2v2", "",   "Classes banned in 2v2");
    HookEvent("player_changeclass", Event_PlayerClass);
    HookEvent("player_spawn",       Event_PlayerSpawn);
    HookEvent("player_team",        Event_PlayerTeam);
    
    HookEvent("teamplay_round_start", Event_RoundStart);
    HookEvent("teamplay_setup_finished",Event_SetupFinished);
    
    HookEvent("teamplay_round_win",Event_RoundOver);
    
    RegConsoleCmd("say", Command_Say);
    RegConsoleCmd("sm_cw_reroll", Command_CwReroll, "Vote to reroll classes");
    RegConsoleCmd("sm_cw_modevote", Command_ModeVote, "Vote to change class count per team");
    RegConsoleCmd("sm_1v1", Command_Vote1v1, "Vote for 1v1 next round");
    RegConsoleCmd("sm_2v2", Command_Vote2v2, "Vote for 2v2 next round");
    RegAdminCmd("sm_cw_forcescramble", Command_Scramble, ADMFLAG_GENERIC, "Force scramble");
    RegAdminCmd("sm_cw_setmode", Command_SetMode, ADMFLAG_GENERIC, "Set class count per team");

    new seeds[1];
    seeds[0] = GetTime();
    SetURandomSeed(seeds, 1);

    // for (new i = 0; i < 10; i++) {
    // LogError("Random[%i] = %i", i, Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER));
    // }

}

public OnMapEnd()
{
    g_hClassChangeTimer = INVALID_HANDLE;
    g_hVoteDelayTimer = INVALID_HANDLE;
    g_bVoteAllowed = true;
}

public OnMapStart()
{
    SetupClassRestrictions();
    RandomizedThisRound = 1;

    decl i, String:sSound[32];
    for(i = 1; i < sizeof(g_sSounds); i++)
    {
        Format(sSound, sizeof(sSound), "sound/%s", g_sSounds[i]);
        PrecacheSound(g_sSounds[i]);
        AddFileToDownloadsTable(sSound);
    }
}

public Action:Command_CwReroll(client, args)
{
    CastRerollVote(client);
    return Plugin_Handled;
}

public Action:Command_Scramble(client, args)
{
    SetupClassRestrictions();
    ApplyReroll();
    ShowActivity2(client, "\x04[SM]\x01 ", "scrambled the classes.");
    PrintStatus();
    return Plugin_Handled;
}

public Action:Command_SetMode(client, args)
{
    decl String:sArg[8];
    GetCmdArg(1, sArg, sizeof(sArg));
    new mode = StringToInt(sArg);
    if (args < 1 || mode < 1 || mode > 2)
    {
        ReplyToCommand(client, "\x01\x04[SM]\x01 Usage: sm_cw_setmode <1|2>");
        return Plugin_Handled;
    }
    SetConVarInt(g_hClassesPerTeam, mode);
    ShowActivity2(client, "\x04[SM]\x01 ", "set the class mode to %s.", mode == 2 ? "2v2" : "1v1");
    return Plugin_Handled;
}

public Action:Command_ModeVote(client, args)
{
    CastModeVote(client, GetConVarInt(g_hClassesPerTeam) == 2 ? 1 : 2);
    return Plugin_Handled;
}

public Action:Command_Vote1v1(client, args)
{
    CastModeVote(client, 1);
    return Plugin_Handled;
}

public Action:Command_Vote2v2(client, args)
{
    CastModeVote(client, 2);
    return Plugin_Handled;
}

CountVoters()
{
    new count = 0;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && !IsFakeClient(i)) {
            count++;
        }
    }
    return count;
}

VotesNeeded()
{
    new needed = RoundToCeil(float(CountVoters()) * GetConVarFloat(g_hVotePercent) / 100.0);
    return needed < 1 ? 1 : needed;
}

CastModeVote(client, mode)
{
    if (!client || !IsClientInGame(client)) {
        return;
    }
    if (GetConVarInt(g_hClassesPerTeam) == mode) {
        ReplyToCommand(client, "\x01\x04[SM]\x01 Next round is already %s.", mode == 2 ? "2v2" : "1v1");
        return;
    }
    if (g_iVotedMode[client] == mode) {
        ReplyToCommand(client, "\x01\x04[SM]\x01 You already voted for %s.", mode == 2 ? "2v2" : "1v1");
        return;
    }
    g_iVotedMode[client] = mode;

    new votes = 0;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && g_iVotedMode[i] == mode) {
            votes++;
        }
    }
    new needed = VotesNeeded();

    PrintToChatAll("\x01\x04[SM]\x01 %N wants %s next round (%d/%d votes, type !%s)", client, mode == 2 ? "2v2" : "1v1", votes, needed, mode == 2 ? "2v2" : "1v1");

    if (votes >= needed) {
        SetConVarInt(g_hClassesPerTeam, mode);
        ResetModeVotes();
        PrintCenterTextAll("Vote Passed. Next round will be %s.", mode == 2 ? "2v2" : "1v1");
        PrintToChatAll("\x01\x04[SM]\x01 Vote Passed. Next round will be %s.", mode == 2 ? "2v2" : "1v1");
    }
}

ResetModeVotes()
{
    for (new i = 0; i <= MaxClients; i++) {
        g_iVotedMode[i] = 0;
    }
}

ResetRerollVotes()
{
    for (new i = 0; i <= MaxClients; i++) {
        g_bVotedReroll[i] = false;
    }
}

public Action:Command_Say(client, args)
{
    if (!client)
    {
        return Plugin_Continue;
    }

    decl String:text[192];
    if (!GetCmdArgString(text, sizeof(text)))
    {
        return Plugin_Continue;
    }
    
    new startidx = 0;
    if(text[strlen(text)-1] == '"')
    {
        text[strlen(text)-1] = '\0';
        startidx = 1;
    }

    if (strcmp(text[startidx], "nextclass", false) == 0)
    {
        CastRerollVote(client);
    }

    return Plugin_Continue;
}

CastRerollVote(client)
{
    if (!client || !IsClientInGame(client)) {
        return;
    }
    if (!g_bVoteAllowed)
    {
        ReplyToCommand(client, "\x01\x04[SM]\x01 %s", "The classes were just changed, wait a bit before voting again.");
        return;
    }
    if (g_bVotedReroll[client]) {
        ReplyToCommand(client, "\x01\x04[SM]\x01 You already voted to reroll.");
        return;
    }
    g_bVotedReroll[client] = true;

    new votes = 0;
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && g_bVotedReroll[i]) {
            votes++;
        }
    }
    new needed = VotesNeeded();

    PrintToChatAll("\x01\x04[SM]\x01 %N wants to reroll the classes (%d/%d votes, type !cw_reroll)", client, votes, needed);

    if (votes >= needed) {
        DelayPublicVoteTriggering(true);
        SetupClassRestrictions();
        ApplyReroll();
        PrintCenterTextAll("%s", "Vote Passed." );
        PrintToChatAll("\x01\x04[SM]\x01 %s", "Vote Passed."  );
        PrintStatus();
    }
}

DelayPublicVoteTriggering(bool:success = false)  // success means a vote happened... longer delay
{
    ResetRerollVotes();
    g_bVoteAllowed = false;
    if (g_hVoteDelayTimer != INVALID_HANDLE)
    {
        KillTimer(g_hVoteDelayTimer);
        g_hVoteDelayTimer = INVALID_HANDLE;
    }
    new Float:fDelay = 60.0;
    if (success) {
        fDelay = fDelay * 2.0;
    }
    g_hVoteDelayTimer = CreateTimer(fDelay, TimerEnable, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:TimerEnable(Handle:timer)
{
    g_bVoteAllowed = true;
    g_hVoteDelayTimer = INVALID_HANDLE;
    return Plugin_Handled;
}

public Event_RoundOver(Handle:event, const String:name[], bool:dontBroadcast) {

    //new WinnerTeam = GetEventInt(event, "team"); 
    new FullRound = GetEventInt(event, "full_round"); 
    //new WinReason = GetEventInt(event, "winreason"); 
    //new FlagCapLimit = GetEventInt(event, "flagcaplimit"); 

    //PrintToChatAll("Full Round? %d | WinnerTeam: %d | WinReason: %d | FlagCapLimit: %d", FullRound, WinnerTeam, WinReason, FlagCapLimit); 
    
    //On Dustbowl, each stage is a mini-round.  If we switch up between minirounds,
    //the teams may end up in a stalemate with lots of times on the clock... 
    
    if(FullRound == 1) 
    {
        RandomizedThisRound = 0;
    }
}

public OnClientPutInServer(client)
{
    g_iClass[client] = TF_CLASS_UNKNOWN;
    g_bVotedReroll[client] = false;
    g_iVotedMode[client] = 0;
}

public Event_PlayerClass(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!GetConVarBool(g_hEnabled))
    return;
    
    new iClient = GetClientOfUserId(GetEventInt(event, "userid")),
    iClass  = GetEventInt(event, "class");
    
    if(!IsValidClass(iClient, iClass))
    {
        new iTeam   = GetClientTeam(iClient);
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
        if (iClass > TF_CLASS_UNKNOWN && iClass <= TF_CLASS_ENGINEER) {
            EmitSoundToClient(iClient, g_sSounds[iClass]);
        }
        //TF2_SetPlayerClass(iClient, TFClassType:g_iClass[iClient]);

        decl String:sTeamClasses[32];
        TeamClassString(iTeam, sTeamClasses, sizeof(sTeamClasses));
        PrintCenterText(iClient, "%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", sTeamClasses );
        PrintToChat(iClient, "%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", sTeamClasses);

        AssignValidClass(iClient);
    }    
}


public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    RoundClassRestrictions();
    PrintStatus();
} 

public Action:Event_SetupFinished(Handle:event,  const String:name[], bool:dontBroadcast) 
{   
    PrintStatus();
}  

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new iClient = GetClientOfUserId(GetEventInt(event, "userid"));  
    g_iClass[iClient] = _:TF2_GetPlayerClass(iClient);
    
    if(!IsValidClass(iClient,g_iClass[iClient]))
    {   //new iTeam   = GetClientTeam(iClient);       
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
        //EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
        
        AssignValidClass(iClient);
    }
}

public Event_PlayerTeam(Handle:event,  const String:name[], bool:dontBroadcast)
{   
    new iClient = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(!IsValidClass(iClient,g_iClass[iClient]))
    {
        //new iTeam   = GetClientTeam(iClient);
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
        //EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
        AssignValidClass(iClient);
    }
}

bool:IsValidClass(iClient, iClass) {

    new iTeam = GetClientTeam(iClient);
    
    if(!(GetConVarBool(g_hImmunity) && IsImmune(iClient)) && IsFull(iTeam, iClass)) {
        return false;
    }
    return true;   
}

bool:IsFull(iTeam, iClass)
{
    // If plugin is disabled, or team or class is invalid, class is not full
    if(!GetConVarBool(g_hEnabled) || iTeam < TF_TEAM_RED || iClass < TF_CLASS_SCOUT)
    return false;
    
    // Get team's class limit
    new iLimit,
Float:flLimit = g_hLimits[iTeam][iClass];
    
    // If limit is a percentage, calculate real limit
    if(flLimit > 0.0 && flLimit < 1.0)
    iLimit = RoundToNearest(flLimit * GetTeamClientCount(iTeam));
    else
    iLimit = RoundToNearest(flLimit);
    
    // If limit is -1, class is not full
    if(iLimit == -1)
    return false;
    // If limit is 0, class is full
    else if(iLimit == 0)
    return true;
    
    // Loop through all clients
    for(new i = 1, iCount = 0; i <= MaxClients; i++)
    {
        // If client is in game, on this team, has this class and limit has been reached, class is full
        if(IsClientInGame(i) && GetClientTeam(i) == iTeam && _:TF2_GetPlayerClass(i) == iClass && ++iCount > iLimit)
        return true;
    }
    
    return false;
}

PrintStatus() {
    if(!GetConVarBool(g_hEnabled))
    return;
    
    decl String:sRed[32], String:sBlue[32];
    TeamClassString(TF_TEAM_RED, sRed, sizeof(sRed));
    TeamClassString(TF_TEAM_BLU, sBlue, sizeof(sBlue));
    PrintCenterTextAll("%s%s%s%s", "This is Class Warfare: Red ", sRed, " vs Blue ", sBlue );
    PrintToChatAll("%s%s%s%s", "This is Class Warfare: Red ", sRed, " vs Blue ", sBlue );
}

TeamClassString(iTeam, String:buffer[], maxlen) {
    new iClass1 = (iTeam == TF_TEAM_BLU) ? g_iBlueClass1 : g_iRedClass1;
    new iClass2 = (iTeam == TF_TEAM_BLU) ? g_iBlueClass2 : g_iRedClass2;
    if (g_iClassesThisRound == 2 && iClass1 != iClass2) {
        Format(buffer, maxlen, "%s and %s", ClassNames[iClass1], ClassNames[iClass2]);
    } else {
        Format(buffer, maxlen, "%s", ClassNames[iClass1]);
    }
}
bool:IsImmune(iClient)
{
    if(!iClient || !IsClientInGame(iClient))
    return false;
    
    decl String:sFlags[32];
    GetConVarString(g_hFlags, sFlags, sizeof(sFlags));
    
    // If flags are specified and client has generic or root flag, client is immune
    return !StrEqual(sFlags, "") && GetUserFlagBits(iClient) & (ReadFlagString(sFlags)|ADMFLAG_ROOT);
}

AssignPlayerClasses() {
    for (new i = 1; i <= MaxClients; ++i) {
        if (IsClientInGame(i) && GetClientTeam(i) >= TF_TEAM_RED) {
            g_iClass[i] = _:TF2_GetPlayerClass(i);
            if (!IsValidClass(i, g_iClass[i])) {
                AssignValidClass(i);
                if (IsFakeClient(i)) {
                    TF2_RespawnPlayer(i); //If bots don't respawn, they seem to get stuck sometimes?
                }
            }
        }
    }
}


// Run once per real round (event fires multiple times)
RoundClassRestrictions() {
    if ( RandomizedThisRound == 0) {
        SetupClassRestrictions();
        ResetRerollVotes();
        ResetModeVotes();
    } 
    RandomizedThisRound = 1;
    AssignPlayerClasses();
}

ApplyReroll() {
    if (GetConVarBool(g_hRerollImmediate)) {
        AssignPlayerClasses();
    } else {
        AssignBotClasses();
    }
}

AssignBotClasses() {
    for (new i = 1; i <= MaxClients; ++i) {
        if (IsClientInGame(i) && IsFakeClient(i) && GetClientTeam(i) >= TF_TEAM_RED) {
            g_iClass[i] = _:TF2_GetPlayerClass(i);
            if (!IsValidClass(i, g_iClass[i])) {
                AssignValidClass(i);
                TF2_RespawnPlayer(i);
            }
        }
    }
}

RandomAllowedClass(exclude = TF_CLASS_UNKNOWN)
{
    decl String:sBlacklist[128];
    GetConVarString(g_iClassesThisRound == 2 ? g_hBlacklist2v2 : g_hBlacklist1v1, sBlacklist, sizeof(sBlacklist));

    new iClass, tries = 0;
    do {
        iClass = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    } while (iClass == exclude || (tries++ < 100 && StrContains(sBlacklist, ClassNames[iClass], false) != -1));
    return iClass;
}

SetupClassRestrictions() {

    for(new i = TF_CLASS_SCOUT; i <= TF_CLASS_ENGINEER; i++)
    {
        g_hLimits[TF_TEAM_BLU][i] = 0.0;
        g_hLimits[TF_TEAM_RED][i] = 0.0;
    }
    
 
    g_iClassesThisRound = GetConVarInt(g_hClassesPerTeam);

    g_iBlueClass1 = RandomAllowedClass();
    g_iRedClass1 = RandomAllowedClass();

    if (g_iClassesThisRound == 2) {
        g_iBlueClass2 = RandomAllowedClass(g_iBlueClass1);
        g_iRedClass2 = RandomAllowedClass(g_iRedClass1);
    } else {
        g_iBlueClass2 = g_iBlueClass1;
        g_iRedClass2 = g_iRedClass1;
    }

    g_hLimits[TF_TEAM_BLU][g_iBlueClass1] = -1.0;
    g_hLimits[TF_TEAM_RED][g_iRedClass1] = -1.0;

    g_hLimits[TF_TEAM_BLU][g_iBlueClass2] = -1.0;
    g_hLimits[TF_TEAM_RED][g_iRedClass2] = -1.0;

    if (g_hClassChangeTimer != INVALID_HANDLE) {
        KillTimer(g_hClassChangeTimer);
        g_hClassChangeTimer = INVALID_HANDLE;
    }
    new seconds = GetConVarInt(g_hClassChangeInterval) * 60;
    if (seconds > 0) {
        g_hClassChangeTimer = CreateTimer(float(seconds), TimerClassChange, _, TIMER_FLAG_NO_MAPCHANGE);
    }

}

public Action:TimerClassChange(Handle:timer, any:client)
{
    g_hClassChangeTimer = INVALID_HANDLE;
    SetupClassRestrictions();
    ApplyReroll();
    PrintToChatAll("%s", "Mid Round Class Change!");
    PrintStatus();
    return Plugin_Stop;
}

/* AssignValidClass(iClient)
{
    // Loop through all classes, starting at random class
    for(new i = (TF_CLASS_SCOUT, TF_CLASS_ENGINEER), iClass = i, iTeam = GetClientTeam(iClient);;)
    {
        // If team's class is not full, set client's class
        if(!IsFull(iTeam, i))
        {
            TF2_SetPlayerClass(iClient, TFClassType:i);
            TF2_RegeneratePlayer(iClient);  
            if (!IsPlayerAlive(iClient)) {
                TF2_RespawnPlayer(iClient);
            }
            g_iClass[iClient] = i;
            break;
        }
        // If next class index is invalid, start at first class
        else if(++i > TF_CLASS_ENGINEER)
        i = TF_CLASS_SCOUT;
        // If loop has finished, stop searching
        else if(i == iClass)
        break;
    }
} */

AssignValidClass(iClient)
{
    
    new i = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    new iTeam = GetClientTeam(iClient);
    
    while (IsFull(iTeam, i)) {
    i = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    }
    g_iClass[iClient] = i;
    
    TF2_SetPlayerClass(iClient, TFClassType:i);
    TF2_RegeneratePlayer(iClient);  
    if (!IsPlayerAlive(iClient)) {
        TF2_RespawnPlayer(iClient);
    }
  
}


stock Math_GetRandomInt(min, max)
{
    new random = GetURandomInt();
    
    if (random == 0) {
        random++;
    }

    return RoundToCeil(float(random) / (float(SIZE_OF_INT) / float(max - min + 1))) + min - 1;
}