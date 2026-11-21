-- Opt-in only. The launcher sets these variables for bot client processes.
-- Normal clients never enter this path.
local function env(name)
	if os and type(os.getenv) == "function" then
		local ok, value = pcall(os.getenv, name)
		if ok then
			return value
		end
	end
	return nil
end

local botMode = env("SC_PLAYERBOT_MODE") == "1"
if not botMode then
	return
end

local state = rawget(_G, "SCPlayerBotState")
if not state then
	state = { enabled = true, loginStarted = false, undockPending = false, undockStarted = false }
	_G.SCPlayerBotState = state
end

state.login = env("SC_PLAYERBOT_LOGIN")
state.password = env("SC_PLAYERBOT_PASSWORD")

local function log(message)
	if sys and sys.log then
		sys.log("SC_PLAYERBOT: " .. message)
	end
end

if not state.login or state.login == "" or not state.password or state.password == "" then
	state.enabled = false
	log("missing bot credentials in process environment; automation disabled")
	return
end

if UI.LoginWnd and not state.loginHooked then
	local originalLoginShown = UI.LoginWnd.F_OnAfterShowOnScreen
	UI.LoginWnd.F_OnAfterShowOnScreen = function(self, ...)
		if originalLoginShown then
			originalLoginShown(self, ...)
		end

		if state.enabled and not state.loginStarted and self.waitMode == self.waitModes.NONE then
			UI.Login_AccountEditWnd:SetEditText(state.login)
			UI.Login_PasswordEditWnd:SetEditText(state.password)
			if UI.Login_RememberCheckBox and UI.Login_RememberCheckBox.Check then
				UI.Login_RememberCheckBox:Check(false)
			end
			state.loginStarted = true
			log("authenticating local bot account " .. state.login)
			self:OnLogIn()
		end
	end
	state.loginHooked = true

	local originalProceedToHangar = UI.LoginWnd.ProceedToHangar
	UI.LoginWnd.ProceedToHangar = function(self, ...)
		if originalProceedToHangar then
			originalProceedToHangar(self, ...)
		end
		state.undockPending = true
	end
	state.hangarTransitionHooked = true
end

if UI.HangarWnd and not state.hangarHooked then
	local originalHangarFrame = UI.HangarWnd.F_OnNewFrame
	UI.HangarWnd.F_OnNewFrame = function(self, hSender, dt_sys, dt_game)
		if originalHangarFrame then
			originalHangarFrame(self, hSender, dt_sys, dt_game)
		end

		if state.enabled and state.undockPending and not state.undockStarted and self:IsOnScreen() then
			state.undockDelay = (state.undockDelay or 0) + (dt_sys or 0)
			if state.undockDelay >= 3 and self.prepareState == self.prepareStates.NONE then
				local getZoneId = _G.MasterServer_GetSpaceStationZoneId
				local ok, zoneId = false, nil
				if type(getZoneId) == "function" then
					ok, zoneId = pcall(getZoneId)
				end
				if ok and type(zoneId) == "number" and zoneId >= 0 then
					state.undockStarted = true
					self.freeSpaceRequestId = 0
					self.prepareGameParams = { mode = "FREE_SPACE", battleSlot = 1, zoneId = zoneId }
					self:StartMatchMaking()
					if self.freeSpaceRequestId and self.freeSpaceRequestId ~= 0 then
						log("requested open-space entry for " .. state.login)
						state.undockPending = false
					else
						log("open-space request was rejected for " .. state.login)
					end
				else
					state.undockStarted = true
					log("could not resolve the account's station zone; open-space request skipped")
				end
			end
		end
	end
	state.hangarHooked = true
end

-- The UI scripts expose no supported API for giving an authenticated player
-- ship NPC behavior. Do not call guessed AI methods: that can break a client
-- without making it a functioning playerbot.
