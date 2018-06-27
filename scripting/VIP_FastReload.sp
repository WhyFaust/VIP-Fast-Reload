#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>
#include <vip_core>

#pragma newdecls required

public Plugin myinfo =
{
	name = "[VIP] FastReload",
	author = "BaFeR",
	version = "1.0"
};

static const char g_sFeature[] = "FastReload";

bool g_bLateLoaded;

public void VIP_OnVIPLoaded()
{
	VIP_RegisterFeature(g_sFeature, FLOAT);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoaded = late;
	
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS && engine != Engine_CSGO)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("vip_modules.phrases");
	if(VIP_IsVIPLoaded())
	{
		VIP_OnVIPLoaded();
	}
	
	if(g_bLateLoaded)
	{
		int iEntities = GetMaxEntities();
		for(int i=MaxClients+1;i<=iEntities;i++)
		{
			// Hook shotguns.
			if(IsValidEntity(i) && HasEntProp(i, Prop_Send, "m_reloadState"))
			{
				SDKHook(i, SDKHook_ReloadPost, Hook_OnReloadPost);
			}
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// Hook shotguns - they reload differently.
	if(HasEntProp(entity, Prop_Send, "m_reloadState"))
		SDKHook(entity, SDKHook_ReloadPost, Hook_OnReloadPost);
}

public bool OnItemDisplay(int iClient, const char[] sFeatureName, char[] sDisplay, int iMaxLen)
{
	if(VIP_IsClientFeatureUse(iClient, g_sFeature))
	{
		FormatEx(sDisplay, iMaxLen, "%T", g_sFeature, iClient);
		return true;
	}

	return false;
}

public void OnPluginEnd() 
{
	if(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "VIP_UnregisterFeature") == FeatureStatus_Available)
	{
		VIP_UnregisterFeature(g_sFeature);
	}
}

void IncreaseReloadSpeed(int iClient)
{
	if(IsFakeClient(iClient) && VIP_IsClientVIP(iClient) && !VIP_IsClientFeatureUse(iClient, g_sFeature))
		return;
	
	char sWeapon[64];
	int iWeapon = Client_GetActiveWeaponName(iClient, sWeapon, sizeof(sWeapon));
	
	if(iWeapon == INVALID_ENT_REFERENCE)
		return;
	
	bool bIsShotgun = HasEntProp(iWeapon, Prop_Send, "m_reloadState");
	if(bIsShotgun)
	{
		int iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
		if(iReloadState == 0)
			return;
	}
	
	float fNextAttack = GetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack");
	float fGameTime = GetGameTime();
	
	float fReloadIncrease = 1.0 / (1.0 + VIP_GetClientFeatureFloat(iClient, g_sFeature));
	
	SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	int iViewModel = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0 / fReloadIncrease);
	
	float fNextAttackNew = (fNextAttack - fGameTime) * fReloadIncrease;
	
	if(bIsShotgun)
	{
		DataPack hData;
		CreateDataTimer(0.01, Timer_CheckShotgunEnd, hData, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		hData.WriteCell(EntIndexToEntRef(iWeapon));
		hData.WriteCell(GetClientUserId(iClient));
	}
	else
	{
		DataPack hData;
		CreateDataTimer(fNextAttackNew, Timer_ResetPlaybackRate, hData, TIMER_FLAG_NO_MAPCHANGE);
		hData.WriteCell(EntIndexToEntRef(iWeapon));
		hData.WriteCell(GetClientUserId(iClient));
	}
	
	fNextAttackNew += fGameTime;
	SetEntPropFloat(iWeapon, Prop_Send, "m_flTimeWeaponIdle", fNextAttackNew);
	SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", fNextAttackNew);
	SetEntPropFloat(iClient, Prop_Send, "m_flNextAttack", fNextAttackNew);
}

public Action Timer_ResetPlaybackRate(Handle timer, DataPack data)
{
	data.Reset();
	
	int iWeapon = EntRefToEntIndex(data.ReadCell());
	int iClient = GetClientOfUserId(data.ReadCell());
	
	if(iWeapon != INVALID_ENT_REFERENCE)	
		SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
	
	if(iClient > 0)
		ResetClientViewModel(iClient);
	
	return Plugin_Stop;
}


public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	static bool ClientIsReloading[MAXPLAYERS+1];
	if(!IsClientInGame(iClient))
		return Plugin_Continue;

	char sWeapon[64];
	int iWeapon = Client_GetActiveWeaponName(iClient, sWeapon, sizeof(sWeapon));
	if(iWeapon == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	bool bIsReloading = Weapon_IsReloading(iWeapon);
	if(!bIsReloading && HasEntProp(iWeapon, Prop_Send, "m_reloadState") && GetEntProp(iWeapon, Prop_Send, "m_reloadState") > 0)
		bIsReloading = true;
	
	if(bIsReloading && !ClientIsReloading[iClient])
	{
		IncreaseReloadSpeed(iClient);
	}
	
	ClientIsReloading[iClient] = bIsReloading;
	
	return Plugin_Continue;
}

public Action Timer_CheckShotgunEnd(Handle timer, DataPack data)
{
	data.Reset();
	
	int iWeapon = EntRefToEntIndex(data.ReadCell());
	int iClient = GetClientOfUserId(data.ReadCell());
	
	if(iWeapon == INVALID_ENT_REFERENCE)
	{
		if(iClient > 0)
			ResetClientViewModel(iClient);
		return Plugin_Stop;
	}
	
	int iOwner = Weapon_GetOwner(iWeapon);
	if(iOwner <= 0)
	{
		if(iClient > 0)
			ResetClientViewModel(iClient);
		
		SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
		
		return Plugin_Stop;
	}

	int iReloadState = GetEntProp(iWeapon, Prop_Send, "m_reloadState");
	
	if(iReloadState > 0)
		return Plugin_Continue;
	
	SetEntPropFloat(iWeapon, Prop_Send, "m_flPlaybackRate", 1.0);
	
	
	if(iClient > 0)
		ResetClientViewModel(iClient);
	
	return Plugin_Stop;
}

public void Hook_OnReloadPost(int weapon, bool bSuccessful)
{
	int iClient = Weapon_GetOwner(weapon);
	if(iClient <= 0)
		return;
	
	if(GetEntProp(weapon, Prop_Send, "m_reloadState") != 2)
		return;
	
	if(IsFakeClient(iClient) && VIP_IsClientVIP(iClient) && !VIP_IsClientFeatureUse(iClient, g_sFeature))
		return;
	
	float fReloadIncrease = 1.0 / (1.0 + VIP_GetClientFeatureFloat(iClient, g_sFeature));
	
	float fIdleTime = GetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle");
	float fGameTime = GetGameTime();
	float fIdleTimeNew = (fIdleTime - fGameTime) * fReloadIncrease + fGameTime;

	SetEntPropFloat(weapon, Prop_Send, "m_flTimeWeaponIdle", fIdleTimeNew);
}

stock void ResetClientViewModel(int iClient)
{
	int iViewModel = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
	if(iViewModel != INVALID_ENT_REFERENCE)
		SetEntPropFloat(iViewModel, Prop_Send, "m_flPlaybackRate", 1.0);
}