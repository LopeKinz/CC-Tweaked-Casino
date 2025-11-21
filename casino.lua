-- casino.lua - CASINO LOUNGE (RS Bridge Support, Pending-Payout Lock)
-- Version 4.2.4 - Player Detector Fix
--
-- Changelog v4.2.4:
-- + FIXED: Player Detector now properly handles both string and table player data
-- + FIXED: Improved error handling with pcall for getPlayersInRange
-- + FIXED: Better fallback to Guest when no players detected
-- + FIXED: Consistent player name extraction from detector results
-- + FIXED: Removed redundant peripheral presence checks
--
-- Changelog v4.2.3:
-- + FIXED: Game card text now visible (was being overwritten by addButton)
-- + Button registration now separated from drawing to prevent text overwrites
-- + Game cards now properly show icons and labels on colored backgrounds

---------------- CONFIG ----------------

local DIAMOND_ID = "minecraft:diamond"
local IO_CHEST_DIR = "front"  -- Richtung der IO-Chest von der Bridge aus
local PLAYER_DETECTION_RANGE = 15  -- Reichweite fuer Player Detector (in Bloecken)
local STATS_PAGE_SIZE = 6  -- Anzahl der Spieler pro Seite in der Statistik-Ansicht

-- Bridge-Typen die wir suchen
local BRIDGE_TYPES = { "meBridge", "me_bridge", "rsBridge", "rs_bridge" }

-- Farbschema (Modern Dark Theme) - Optimized for 5x4 block monitor
local COLORS = {
    -- Base colors
    BG           = colors.black,
    BG_DARK      = colors.gray,

    -- Header & Chrome
    HEADER_BG    = colors.cyan,
    HEADER_ACC   = colors.lightBlue,
    HEADER_TEXT  = colors.white,
    FOOTER_BG    = colors.gray,
    FOOTER_TEXT  = colors.lightGray,
    FRAME        = colors.cyan,

    -- Panels & Cards
    PANEL        = colors.gray,
    PANEL_DARK   = colors.black,
    PANEL_LIGHT  = colors.lightGray,
    CARD_BG      = colors.gray,
    CARD_BORDER  = colors.lightBlue,

    -- Status colors
    HIGHLIGHT    = colors.lime,
    WARNING      = colors.red,
    INFO         = colors.lightBlue,
    GOLD         = colors.yellow,
    SUCCESS      = colors.lime,
    DISABLED     = colors.gray,
    ACCENT       = colors.orange,

    -- Game colors (vibrant and distinct)
    GAME_ROULETTE  = colors.red,
    GAME_SLOTS     = colors.purple,
    GAME_COINFLIP  = colors.yellow,
    GAME_HILO      = colors.orange,
    GAME_BLACKJACK = colors.green,

    -- Player Stats Theme
    STATS_HEADER = colors.cyan,
    STATS_BORDER = colors.lightBlue,
    STATS_ONLINE = colors.lime,
    MEDAL_GOLD   = colors.yellow,
    MEDAL_SILVER = colors.lightGray,
    MEDAL_BRONZE = colors.orange,
    STREAK_WIN   = colors.lime,
    STREAK_LOSS  = colors.red,

    -- Admin colors
    ADMIN_BG     = colors.purple,
    ADMIN_BORDER = colors.pink
}

-- Commonly used color aliases (to avoid typing COLORS. everywhere)
local COLOR_BG          = COLORS.BG
local COLOR_PANEL       = COLORS.PANEL
local COLOR_PANEL_DARK  = COLORS.PANEL_DARK
local COLOR_HIGHLIGHT   = COLORS.HIGHLIGHT
local COLOR_WARNING     = COLORS.WARNING
local COLOR_INFO        = COLORS.INFO
local COLOR_GOLD        = COLORS.GOLD
local COLOR_SUCCESS     = COLORS.SUCCESS
local COLOR_ACCENT      = COLORS.ACCENT

-- Game-Status Datei
local GAME_STATUS_FILE = "game_status.dat"

-- Zentrale Spiel-Konfiguration (Game IDs, Labels, Farben)
local GAME_CONFIG = {
    roulette = {
        id = "roulette",
        label = "  ROULETTE",
        icon = "@",
        mainButtonId = "game_roulette",
        toggleButtonId = "toggle_roulette",
        enabledColor = COLORS.GAME_ROULETTE,
        enabledFg = colors.white
    },
    slots = {
        id = "slots",
        label = "  SLOTS",
        icon = "$",
        mainButtonId = "game_slots",
        toggleButtonId = "toggle_slots",
        enabledColor = COLORS.GAME_SLOTS,
        enabledFg = colors.white
    },
    coinflip = {
        id = "coinflip",
        label = "  MUENZWURF",
        icon = "O",
        mainButtonId = "game_coin",
        toggleButtonId = "toggle_coinflip",
        enabledColor = COLORS.GAME_COINFLIP,
        enabledFg = colors.black
    },
    hilo = {
        id = "hilo",
        label = "  HIGH/LOW",
        icon = "^",
        mainButtonId = "game_hilo",
        toggleButtonId = "toggle_hilo",
        enabledColor = COLORS.GAME_HILO,
        enabledFg = colors.white
    },
    blackjack = {
        id = "blackjack",
        label = "  BLACKJACK",
        icon = "#",
        mainButtonId = "game_blackjack",
        toggleButtonId = "toggle_blackjack",
        enabledColor = COLORS.GAME_BLACKJACK,
        enabledFg = colors.white
    }
}

-- Standard: Alle Spiele aktiv
local gameStatus = {
    roulette = true,
    slots = true,
    coinflip = true,
    hilo = true,
    blackjack = true
}

-- Lade Game-Status aus Datei (mit Validierung)
local function loadGameStatus()
    local success, err = pcall(function()
        if fs.exists(GAME_STATUS_FILE) then
            local file = fs.open(GAME_STATUS_FILE, "r")
            if file then
                local data = file.readAll()
                file.close()
                if data and data ~= "" then
                    local decoded = textutils.unserialise(data)
                    if decoded and type(decoded) == "table" then
                        for gameId, _ in pairs(gameStatus) do
                            if decoded[gameId] ~= nil then
                                gameStatus[gameId] = decoded[gameId] and true or false
                            end
                        end
                        print("[INFO] Game-Status geladen")
                    else
                        print("[WARNUNG] Game-Status Datei korrupt, verwende Standard")
                    end
                end
            end
        else
            print("[INFO] Keine Game-Status Datei gefunden, alle Spiele aktiv")
        end
    end)
    if not success then
        print("[FEHLER] Fehler beim Laden des Game-Status: " .. tostring(err))
    end
end

-- Speichere Game-Status in Datei
local function saveGameStatus()
    local success, err = pcall(function()
        local file = fs.open(GAME_STATUS_FILE, "w")
        if file then
            file.write(textutils.serialise(gameStatus))
            file.close()
            print("[INFO] Game-Status gespeichert")
        else
            print("[FEHLER] Konnte Game-Status Datei nicht oeffnen")
        end
    end)
    if not success then
        print("[FEHLER] Fehler beim Speichern des Game-Status: " .. tostring(err))
    end
end

-- Lade Status beim Start
loadGameStatus()

--------------- PERIPHERALS ------------

local monitor = peripheral.find("monitor")
if not monitor then error("Kein Monitor gefunden") end

monitor.setTextScale(0.5)
local mw, mh = monitor.getSize()

-- Bridge suchen
local bridge
for _, t in ipairs(BRIDGE_TYPES) do
    bridge = peripheral.find(t)
    if bridge then 
        print("Bridge gefunden: " .. peripheral.getName(bridge))
        break 
    end
end
if not bridge then
    error("Keine meBridge/rsBridge gefunden!")
end

-- Player Detector suchen (nur peripheral.find, kein Fallback mehr)
local player_detector = peripheral.find("player_detector")

if player_detector then
    print("Player Detector gefunden: " .. peripheral.getName(player_detector))
    print("Erkennungsreichweite: " .. PLAYER_DETECTION_RANGE .. " Bloecke")
else
    print("WARNUNG: Kein Player Detector gefunden!")
    print("Fallback: 'Guest' Spieler wird verwendet")
end

print("Casino gestartet auf Monitor: " .. peripheral.getName(monitor))
print("Monitor-Größe: " .. mw .. "x" .. mh)
print("IO-Chest Richtung: " .. IO_CHEST_DIR)

math.randomseed(os.epoch("utc"))

--------------- UI-HELPER --------------

local function mclearRaw()
    monitor.setBackgroundColor(COLOR_BG)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function mwrite(x,y,text,fg,bg)
    if y < 1 or y > mh then return end
    if bg then monitor.setBackgroundColor(bg) end
    if fg then monitor.setTextColor(fg) end
    monitor.setCursorPos(x,y)
    monitor.write(text)
end

local function mcenter(y,text,fg,bg)
    text = tostring(text)
    local x = math.floor((mw - #text)/2)+1
    if x < 1 then x = 1 end
    mwrite(x,y,text,fg,bg)
end

local function drawBox(x1,y1,x2,y2,bg)
    monitor.setBackgroundColor(bg or COLOR_PANEL)
    for y=y1,y2 do
        monitor.setCursorPos(x1,y)
        monitor.write(string.rep(" ",x2-x1+1))
    end
end

local function drawBorder(x1,y1,x2,y2,color)
    monitor.setTextColor(color or COLORS.FRAME)
    for x=x1,x2 do
        monitor.setCursorPos(x,y1)
        monitor.write("-")
        monitor.setCursorPos(x,y2)
        monitor.write("-")
    end
    for y=y1,y2 do
        monitor.setCursorPos(x1,y)
        monitor.write("|")
        monitor.setCursorPos(x2,y)
        monitor.write("|")
    end
    monitor.setCursorPos(x1,y1); monitor.write("+")
    monitor.setCursorPos(x2,y1); monitor.write("+")
    monitor.setCursorPos(x1,y2); monitor.write("+")
    monitor.setCursorPos(x2,y2); monitor.write("+")
end

-- Helper: Zeige ein deaktiviertes Spiel
local function drawDisabledGameButton(x1, y1, x2, y2, label)
    drawBox(x1, y1, x2, y2, COLORS.DISABLED)
    local labelX = x1 + math.floor((x2 - x1 + 1 - #label) / 2)
    local midY = y1 + math.floor((y2 - y1) / 2)
    mwrite(labelX, midY, label, colors.gray, COLORS.DISABLED)
    mwrite(labelX - 1, midY + 1, "[DEAKTIVIERT]", colors.gray, COLORS.DISABLED)
end

local function drawChrome(title, footer)
    mclearRaw()

    -- Modern header design with double line
    monitor.setBackgroundColor(COLORS.HEADER_BG)
    monitor.setTextColor(COLORS.HEADER_TEXT)
    monitor.setCursorPos(1,1)
    monitor.write(string.rep(" ",mw))
    monitor.setCursorPos(1,2)
    monitor.write(string.rep(" ",mw))

    -- Title on first line
    local titleText = "  "..title.."  "
    if #titleText > mw then titleText = titleText:sub(1,mw) end
    mcenter(1,titleText,COLORS.HEADER_TEXT,COLORS.HEADER_BG)

    -- Decorative line on second line
    monitor.setBackgroundColor(COLORS.HEADER_ACC)
    monitor.setCursorPos(1,2)
    monitor.write(string.rep(" ",mw))
    local divider = string.rep("=", math.min(#titleText + 4, mw-4))
    mcenter(2,divider,COLORS.HEADER_TEXT,COLORS.HEADER_ACC)

    -- Enhanced border with rounded corners effect
    drawBorder(1,3,mw,mh-1,COLORS.FRAME)

    -- Modern footer with player info
    monitor.setBackgroundColor(COLORS.FOOTER_BG)
    monitor.setCursorPos(1,mh)
    monitor.write(string.rep(" ",mw))
    if footer then
        local footerText = footer
        if currentPlayer and currentPlayer ~= "Guest" then
            footerText = "Spieler: "..currentPlayer.." | "..footer
        end
        mcenter(mh,footerText,COLORS.FOOTER_TEXT,COLORS.FOOTER_BG)
    end

    monitor.setBackgroundColor(COLOR_BG)
    monitor.setTextColor(colors.white)
end

-------------- BUTTONS -----------------

local buttons = {}

local function clearButtons()
    buttons = {}
end

local function addButton(id,x1,y1,x2,y2,label,fg,bg)
    table.insert(buttons,{
        id=id,x1=x1,y1=y1,x2=x2,y2=y2,
        label=label,fg=fg or colors.white,bg=bg or COLOR_PANEL
    })

    drawBox(x1,y1,x2,y2,bg or COLOR_PANEL)

    monitor.setTextColor(colors.white)
    for x=x1,x2 do
        monitor.setCursorPos(x,y1)
        monitor.write("-")
    end

    local lines = {}
    for line in label:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local h = y2-y1+1
    local startY = y1 + math.floor((h - #lines) / 2)

    for i, line in ipairs(lines) do
        local w = x2-x1+1
        local tx = x1 + math.floor((w-#line)/2)
        local ty = startY + i - 1
        if tx < x1 then tx = x1 end
        if tx + #line - 1 > x2 then
            line = line:sub(1,x2-tx+1)
        end
        mwrite(tx,ty,line,fg,bg)
    end
end

local function deduplicateStakes(values)
    local seen = {}
    local result = {}
    for _, v in ipairs(values) do
        if not seen[v] then
            seen[v] = true
            table.insert(result, v)
        end
    end
    return result
end

local function hitButton(x,y)
    for _,b in ipairs(buttons) do
        if x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then
            return b.id
        end
    end
    return nil
end

----------- PLAYER STATISTIKEN ------------

local STATS_FILE = "player_stats.dat"
local playerStats = {}
local lastSeenPlayers = {}

local function sanitizeStats(stats)
    stats.totalVisits = tonumber(stats.totalVisits) or 0
    stats.totalTimeSpent = tonumber(stats.totalTimeSpent) or 0
    stats.gamesPlayed = tonumber(stats.gamesPlayed) or 0
    stats.totalWagered = tonumber(stats.totalWagered) or 0
    stats.totalWon = tonumber(stats.totalWon) or 0
    stats.totalLost = tonumber(stats.totalLost) or 0
    stats.biggestWin = tonumber(stats.biggestWin) or 0
    stats.biggestLoss = tonumber(stats.biggestLoss) or 0
    stats.currentStreak = tonumber(stats.currentStreak) or 0
    stats.longestWinStreak = tonumber(stats.longestWinStreak) or 0
    stats.longestLoseStreak = tonumber(stats.longestLoseStreak) or 0
    stats.firstSeen = tonumber(stats.firstSeen) or os.epoch("utc")
    stats.lastSeen = tonumber(stats.lastSeen) or os.epoch("utc")
    return stats
end

local function loadPlayerStats()
    local success, err = pcall(function()
        if not fs.exists(STATS_FILE) then
            playerStats = {}
            return
        end

        local file = fs.open(STATS_FILE, "r")
        if not file then
            error("Konnte Datei nicht öffnen: "..STATS_FILE)
        end

        local content = file.readAll()
        file.close()

        if not content or content == "" then
            playerStats = {}
            return
        end

        local deserialized = textutils.unserialize(content)
        if not deserialized or type(deserialized) ~= "table" then
            error("Ungültige Daten in Statistik-Datei")
        end

        playerStats = deserialized

        for playerName, stats in pairs(playerStats) do
            if type(stats) == "table" then
                playerStats[playerName] = sanitizeStats(stats)
            else
                print("[WARNUNG] Ungültige Stats für Spieler: "..tostring(playerName))
                playerStats[playerName] = nil
            end
        end
    end)

    if not success then
        print("[FEHLER] loadPlayerStats: "..tostring(err))

        if fs.exists(STATS_FILE) then
            local backupFile = STATS_FILE .. ".backup." .. os.epoch("utc")
            local backupSuccess, backupErr = pcall(function()
                fs.copy(STATS_FILE, backupFile)
                print("[INFO] Korrupte Datei gesichert als: " .. backupFile)
            end)
            if not backupSuccess then
                print("[WARNUNG] Konnte Backup nicht erstellen: " .. tostring(backupErr))
            end
        end

        print("[INFO] Erstelle neue leere Statistik-Datei")
        playerStats = {}
        safeSavePlayerStats("loadPlayerStats")
    end
end

local function savePlayerStats()
    local file = fs.open(STATS_FILE, "w")
    if not file then
        error("Konnte Datei nicht öffnen: "..STATS_FILE)
    end
    file.write(textutils.serialize(playerStats))
    file.close()
end

local function safeSavePlayerStats(context)
    local ok, err = pcall(savePlayerStats)
    if not ok then
        print("[FEHLER] " .. (context or "safeSavePlayerStats") .. ": Konnte Stats nicht speichern: " .. tostring(err))
    end
end

local function getOrCreatePlayerStats(playerName)
    if not playerStats[playerName] then
        playerStats[playerName] = {
            name = playerName,
            firstSeen = os.epoch("utc"),
            lastSeen = os.epoch("utc"),
            totalVisits = 0,
            totalTimeSpent = 0,
            gamesPlayed = 0,
            totalWagered = 0,
            totalWon = 0,
            totalLost = 0,
            biggestWin = 0,
            biggestLoss = 0,
            currentStreak = 0,
            longestWinStreak = 0,
            longestLoseStreak = 0
        }
    else
        playerStats[playerName] = sanitizeStats(playerStats[playerName])
    end
    return playerStats[playerName]
end

-- FIXED: Proper player detection with error handling
-- Returns {players = {...}, names = {...}}
-- Based on reference code from rs_display.lua
local function getPlayersFromDetector()
    if not player_detector then
        return {players = {}, names = {}}
    end

    -- Use pcall to safely call getPlayersInRange
    local ok, playersInRange = pcall(player_detector.getPlayersInRange, PLAYER_DETECTION_RANGE)
    
    if not ok then
        print("[PLAYER DETECTOR] Fehler beim Abrufen: "..tostring(playersInRange))
        return {players = {}, names = {}}
    end
    
    if not playersInRange or type(playersInRange) ~= "table" then
        return {players = {}, names = {}}
    end

    -- Extract player names - handle both string and table formats
    local names = {}
    for _, p in ipairs(playersInRange) do
        if type(p) == "string" then
            -- Direct string format
            table.insert(names, p)
        elseif type(p) == "table" then
            -- Table format - check for name or username field
            if p.name then
                table.insert(names, p.name)
            elseif p.username then
                table.insert(names, p.username)
            end
        end
    end

    if #names > 0 then
        print("[PLAYER DETECTOR] "..#names.." Spieler erkannt: "..table.concat(names, ", "))
    end

    return {players = playersInRange, names = names}
end

-- Hole aktuell erkannte Spielernamen
local function getCurrentPlayers()
    return getPlayersFromDetector().names
end

-- FIXED: Improved nearest player detection
local function getNearestPlayer(detected)
    if not detected or not detected.players or #detected.players == 0 then
        return nil
    end

    local nearestPlayer = nil
    local minDistanceSq = math.huge

    for _, player in ipairs(detected.players) do
        local playerName = nil
        
        -- Extract player name based on type
        if type(player) == "string" then
            playerName = player
        elseif type(player) == "table" then
            playerName = player.name or player.username
        end
        
        if playerName then
            -- Check if we have coordinate data (only for table format)
            if type(player) == "table" and player.x and player.y and player.z then
                local distanceSq = player.x^2 + player.y^2 + player.z^2
                local distance = math.sqrt(distanceSq)
                print("[NEAREST PLAYER] "..playerName.." - Distanz: "..string.format("%.2f", distance).." Bloecke")
                
                if distanceSq < minDistanceSq then
                    minDistanceSq = distanceSq
                    nearestPlayer = playerName
                end
            else
                -- No coordinates available - just take first player
                if not nearestPlayer then
                    nearestPlayer = playerName
                    print("[NEAREST PLAYER] "..playerName.." - Keine Koordinaten, nehme ersten Spieler")
                end
            end
        end
    end

    if nearestPlayer then
        print("[NEAREST PLAYER] Ausgewaehlt: "..nearestPlayer)
    end

    return nearestPlayer
end

-- Spieler erfassen und tracken
local function trackPlayers()
    local detected = getPlayersFromDetector()

    -- Fallback to Guest if no players detected
    if #detected.names == 0 then
        if not currentPlayer then
            currentPlayer = "Guest"
            if not playerStats["Guest"] then
                playerStats["Guest"] = {
                    name = "Guest",
                    firstSeen = os.epoch("utc"),
                    lastSeen = os.epoch("utc"),
                    totalVisits = 0,
                    totalTimeSpent = 0,
                    gamesPlayed = 0,
                    totalWagered = 0,
                    totalWon = 0,
                    totalLost = 0,
                    biggestWin = 0,
                    biggestLoss = 0,
                    currentStreak = 0,
                    longestWinStreak = 0,
                    longestLoseStreak = 0
                }
                safeSavePlayerStats("trackPlayers - Guest created")
            end
        end
        return
    end

    local currentTime = os.epoch("utc")
    local newSeenPlayers = {}

    for _, playerName in ipairs(detected.names) do
        newSeenPlayers[playerName] = true

        local stats = getOrCreatePlayerStats(playerName)
        stats.lastSeen = currentTime

        if not lastSeenPlayers[playerName] then
            stats.totalVisits = stats.totalVisits + 1
            print("[TRACKING] Neuer Besuch von: "..playerName.." (Besuch #"..stats.totalVisits..")")
        end
    end

    for playerName, _ in pairs(lastSeenPlayers) do
        if not newSeenPlayers[playerName] then
            print("[TRACKING] Spieler hat Range verlassen: "..playerName)
        end
    end

    for playerName, _ in pairs(newSeenPlayers) do
        if lastSeenPlayers[playerName] then
            local stats = playerStats[playerName]
            if stats then
                stats.totalTimeSpent = stats.totalTimeSpent + 1000
            end
        end
    end

    lastSeenPlayers = newSeenPlayers

    safeSavePlayerStats("trackPlayers")

    local nearestPlayer = getNearestPlayer(detected)
    if nearestPlayer and not gameInProgress then
        if currentPlayer ~= nearestPlayer then
            print("[TRACKING] Neuer naechster Spieler: "..nearestPlayer.." (vorher: "..(currentPlayer or "keiner")..")")
        end
        currentPlayer = nearestPlayer
    elseif nearestPlayer and gameInProgress then
        print("[TRACKING] Spiel laeuft - behalte aktuellen Spieler: "..(currentPlayer or "Guest"))
    end
end

-- Spiel-Statistik aktualisieren
local function updateGameStats(playerName, wager, won, payout)
    if not playerName or type(playerName) ~= "string" or playerName == "" then
        print("[FEHLER] updateGameStats: Ungültiger Spielername")
        return
    end

    wager = tonumber(wager) or 0
    payout = tonumber(payout) or 0

    if wager < 0 then
        print("[FEHLER] updateGameStats: Negativer Einsatz: "..wager)
        wager = 0
    end

    if payout < 0 then
        print("[FEHLER] updateGameStats: Negativer Payout: "..payout)
        payout = 0
    end

    local stats = getOrCreatePlayerStats(playerName)
    stats.gamesPlayed = stats.gamesPlayed + 1
    stats.totalWagered = stats.totalWagered + wager

    if won then
        local profit = payout - wager
        stats.totalWon = stats.totalWon + profit
        if profit > stats.biggestWin then
            stats.biggestWin = profit
        end

        if stats.currentStreak >= 0 then
            stats.currentStreak = stats.currentStreak + 1
        else
            stats.currentStreak = 1
        end

        if stats.currentStreak > stats.longestWinStreak then
            stats.longestWinStreak = stats.currentStreak
        end
    else
        stats.totalLost = stats.totalLost + wager
        if wager > stats.biggestLoss then
            stats.biggestLoss = wager
        end

        if stats.currentStreak <= 0 then
            stats.currentStreak = stats.currentStreak - 1
        else
            stats.currentStreak = -1
        end

        if math.abs(stats.currentStreak) > stats.longestLoseStreak then
            stats.longestLoseStreak = math.abs(stats.currentStreak)
        end
    end

    safeSavePlayerStats("updateGameStats")
end

-- Formatiere Zeit
local function formatTime(milliseconds)
    local seconds = math.floor(milliseconds / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, minutes % 60)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds % 60)
    else
        return string.format("%ds", seconds)
    end
end

loadPlayerStats()

if not playerStats["Guest"] then
    playerStats["Guest"] = {
        name = "Guest",
        firstSeen = os.epoch("utc"),
        lastSeen = os.epoch("utc"),
        totalVisits = 0,
        totalTimeSpent = 0,
        gamesPlayed = 0,
        totalWagered = 0,
        totalWon = 0,
        totalLost = 0,
        biggestWin = 0,
        biggestLoss = 0,
        currentStreak = 0,
        longestWinStreak = 0,
        longestLoseStreak = 0
    }
    safeSavePlayerStats("Guest initialization at startup")
end

----------- INVENTAR / STORAGE ------------

local function getItemCountInNet(name)
    if not bridge then
        error("[FEHLER] getItemCountInNet: Bridge nicht verfügbar! Hardware-Problem!")
    end

    local ok, res = pcall(bridge.getItem, { name = name })
    if not ok then
        print("[FEHLER] getItemCountInNet pcall fehlgeschlagen: "..tostring(res))
        return 0
    end

    if not res then
        print("[INFO] getItemCountInNet: Item nicht im System gefunden")
        return 0
    end

    return res.amount or res.count or 0
end

local function getPlayerBalance()
    local chest = peripheral.wrap(IO_CHEST_DIR)
    if not chest or not chest.list then
        error("[FEHLER] getPlayerBalance: Keine Chest auf '"..IO_CHEST_DIR.."' gefunden! Hardware-Problem!")
    end

    local total = 0
    local ok, list = pcall(chest.list)
    if ok and type(list) == "table" then
        for _, stack in pairs(list) do
            if stack and stack.name == DIAMOND_ID then
                total = total + (stack.count or 0)
            end
        end
    else
        print("[WARNUNG] getPlayerBalance chest.list() Fehler: "..tostring(list))
        print("[INFO] Returniere 0 bei list() Fehler")
        return 0
    end

    return total
end

local function takeStake(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    if not bridge then
        print("[FEHLER] takeStake: Bridge nicht verfügbar!")
        return 0
    end

    print(("[EINSATZ] Nehme %d Diamanten aus IO-Chest '%s'"):format(amount, IO_CHEST_DIR))

    local ok, imported = pcall(bridge.importItem,
        { name = DIAMOND_ID, count = amount },
        IO_CHEST_DIR
    )

    if not ok then
        print("[FEHLER] importItem:", imported)
        return 0
    end

    local result = imported or 0
    print("[EINSATZ] Genommen:", result)

    if result > 0 and result < amount then
        print("[WARNUNG] Partial import detected! Nehme "..result.." statt "..amount)
        print("[REFUND] Erstatte partial stake von "..result.." Diamanten zurueck")
        rawExportDiamonds(result)
        return 0
    end

    return result
end

------------- PENDING PAYOUT --------------

local pendingPayout = 0
local payoutBlocked = false
local payoutInProgress = false

local MAX_EXPORT_CHUNK = 4096

local function rawExportDiamonds(amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    if not bridge then
        print("[FEHLER] rawExportDiamonds: Bridge nicht verfügbar!")
        return 0
    end

    print(("[GEWINN-RAW] Versuche %d Diamanten nach '%s' zu exportieren"):format(amount, IO_CHEST_DIR))

    local ok, exported = pcall(bridge.exportItem,
        { name = DIAMOND_ID, count = amount },
        IO_CHEST_DIR
    )

    if not ok then
        print("[FEHLER] exportItem:", exported)
        return 0
    end

    exported = exported or 0
    print("[GEWINN-RAW] Tatsächlich exportiert:", exported)
    return exported
end

local function flushPendingPayoutIfPossible()
    pendingPayout = tonumber(pendingPayout) or 0
    if pendingPayout <= 0 then
        payoutBlocked = false
        return
    end

    local inBank = getItemCountInNet(DIAMOND_ID)
    if inBank <= 0 then
        print("[WARNUNG] Bank hat keine Diamanten, offen bleiben: "..pendingPayout)
        payoutBlocked = true
        return
    end

    local toTry = math.min(pendingPayout, inBank, MAX_EXPORT_CHUNK)

    print(("[INFO] Versuche offenen Gewinn auszuzahlen: %d | Versuche: %d"):format(pendingPayout, toTry))

    local exported = rawExportDiamonds(toTry)

    if exported <= 0 then
        payoutBlocked = true
        print("[WARNUNG] Kiste vermutlich voll oder Bridge-Fehler, weiterhin offen: "..pendingPayout)
        return
    end

    pendingPayout = pendingPayout - exported
    if pendingPayout <= 0 then
        pendingPayout = 0
        payoutBlocked = false
        print("[INFO] Ausstehender Gewinn vollständig ausgezahlt.")
    else
        payoutBlocked = true
        print("[WARNUNG] Nur teilweise nachgezahlt, Rest: "..pendingPayout)
    end
end

local function payPayout(amount)
    amount = math.floor(tonumber(amount) or 0)

    flushPendingPayoutIfPossible()

    if amount <= 0 then
        return 0
    end

    print(("[GEWINN] Zahle %d Diamanten aus in IO-Chest '%s'"):format(amount, IO_CHEST_DIR))

    local exported = rawExportDiamonds(amount)

    if exported < amount then
        local notPaid = amount - exported
        pendingPayout = pendingPayout + notPaid
        payoutBlocked = true
        print("[WARNUNG] Nicht alles passte in die Kiste. Offen dazu: "..notPaid.." | Gesamt offen: "..pendingPayout)
    else
        print("[GEWINN] Ausgezahlt:", exported)
    end

    return exported
end

------------- GLOBAL STATE -------------

local mode = "menu"
local currentPlayer = nil
local gameInProgress = false

local AdminState = {
    PIN = "1234",
    panelOpen = false,
    pinInput = "",
    currentStatsOffset = 0
}

-- Game State Variables
local r_state, r_betType, r_choice, r_stake = "type", nil, nil, 0
local r_lastResult, r_lastColor, r_lastHit, r_lastPayout, r_lastMult = nil, nil, nil, nil, nil
local r_player = nil

local c_state, c_stake, c_choice = "stake", 0, nil
local c_lastWin, c_lastPayout, c_lastSide = false, 0, nil
local c_player = nil

local h_state, h_stake = "stake", 0
local h_startNum, h_nextNum, h_choice = nil, nil, nil
local h_lastWin, h_lastPayout, h_lastPush = false, 0, false
local h_player = nil

local bj_state, bj_stake = "stake", 0
local bj_playerHand, bj_dealerHand, bj_deck = {}, {}, {}
local bj_lastWin, bj_lastPayout, bj_lastResult = false, 0, ""
local bj_player = nil

local s_state, s_bet = "setup", 1
local s_grid = {{},{},{}}
local s_lastWin, s_lastMult, s_lastPayout = false, 0, 0
local s_freeSpins, s_totalWin, s_winLines = 0, 0, {}
local s_freeSpinBet = 0
local s_player = nil

local slotSymbols = {
    {sym="7",   weight=1,  name="Lucky 7"},
    {sym="BAR", weight=2,  name="Bar"},
    {sym="DIA", weight=3,  name="Diamant"},
    {sym="$",   weight=4,  name="Dollar"},
    {sym="CHR", weight=5,  name="Cherry"},
    {sym="STR", weight=5,  name="Stern"},
    {sym="BEL", weight=6,  name="Glocke"},
    {sym="FS",  weight=1,  name="Free Spin"},
}

local winLines = {
    {name="Linie 1", path={{1,1},{1,2},{1,3}}},
    {name="Linie 2", path={{2,1},{2,2},{2,3}}},
    {name="Linie 3", path={{3,1},{3,2},{3,3}}},
    {name="Diag 1",  path={{1,1},{2,2},{3,3}}},
    {name="Diag 2",  path={{3,1},{2,2},{1,3}}},
}

----------- PENDING PAYOUT SCREEN ------------

local function drawPendingPayoutScreen()
    clearButtons()
    drawChrome("CASINO LOUNGE","Auszahlung ausstehend")

    local x1, y1, x2, y2 = 4, 5, mw-3, mh-5
    drawBox(x1,y1,x2,y2,COLOR_PANEL_DARK)
    drawBorder(x1,y1,x2,y2,COLOR_WARNING)

    mcenter(y1+1,"AUSZAHLUNG AUSSTEHEND!",COLOR_WARNING,COLOR_PANEL_DARK)
    mcenter(y1+3,"Es sind noch Gewinne offen:",COLOR_INFO,COLOR_PANEL_DARK)
    mcenter(y1+4,tostring(pendingPayout).." Diamanten",COLOR_GOLD,COLOR_PANEL_DARK)
    mcenter(y1+6,"Bitte leere die Chest vor dir",colors.white,COLOR_PANEL_DARK)
    mcenter(y1+7,"und druecke 'Erneut pruefen'.",colors.white,COLOR_PANEL_DARK)

    if payoutBlocked then
        mcenter(y1+9,"(Kiste war zuvor voll)",colors.lightGray,COLOR_PANEL_DARK)
    end

    local btnY = mh-3
    addButton("pending_check",4,btnY,mw-3,btnY+1,"Erneut pruefen",colors.black,COLOR_HIGHLIGHT)
    addButton("admin_panel",mw-6,2,mw-2,3,"[A]",colors.gray,COLOR_BG)
end

local function checkPayoutLock()
    pendingPayout = tonumber(pendingPayout) or 0
    if pendingPayout > 0 then
        mode = "payout"
        drawPendingPayoutScreen()
        return true
    end
    return false
end

----------- MAIN MENU ------------------

local function drawMainMenu()
    gameInProgress = false

    flushPendingPayoutIfPossible()
    if (pendingPayout or 0) > 0 then
        mode = "payout"
        drawPendingPayoutScreen()
        return
    end

    clearButtons()
    drawChrome("CASINO LOUNGE","Waehle dein Gluecksspiel")

    local playerDia = getPlayerBalance()
    local bankDia = getItemCountInNet(DIAMOND_ID)

    local cardY = 4
    local cardW = math.floor(mw * 0.6)
    local cardX1 = math.floor((mw - cardW) / 2)
    local cardX2 = cardX1 + cardW

    drawBox(cardX1, cardY, cardX2, cardY + 4, COLORS.CARD_BG)
    drawBorder(cardX1, cardY, cardX2, cardY + 4, COLORS.CARD_BORDER)

    mcenter(cardY + 1, "GUTHABEN", COLORS.GOLD, COLORS.CARD_BG)
    mcenter(cardY + 2, playerDia.." Diamanten", COLOR_SUCCESS, COLORS.CARD_BG)

    if playerDia == 0 then
        mcenter(cardY + 3, "Lege Diamanten ein!", colors.white, COLORS.CARD_BG)
    else
        mcenter(cardY + 3, "Viel Glueck!", colors.lightGray, COLORS.CARD_BG)
    end

    if bankDia < 100 then
        mcenter(cardY + 5, "[WARNUNG] Casino-Bank: "..bankDia, COLOR_WARNING)
    end

    local btnH = 4
    local gap = 2
    local colW = math.floor((mw - 6) / 2) - 1
    local col1X = 3
    local col2X = col1X + colW + 3
    local startY = cardY + 7

    local function drawGameCard(config, x1, y1, x2, y2, enabled)
        if enabled then
            drawBox(x1, y1, x2, y2, config.enabledColor)
            drawBorder(x1, y1, x2, y2, colors.white)

            table.insert(buttons,{
                id=config.mainButtonId,
                x1=x1, y1=y1, x2=x2, y2=y2,
                label="", fg=config.enabledFg, bg=config.enabledColor
            })

            local cardWidth = x2 - x1 + 1
            local iconY = y1 + 1
            local iconX = x1 + math.floor((cardWidth - #config.icon) / 2)
            mwrite(iconX, iconY, config.icon, config.enabledFg, config.enabledColor)

            local labelY = iconY + 1
            local labelX = x1 + math.floor((cardWidth - #config.label) / 2)
            mwrite(labelX, labelY, config.label, config.enabledFg, config.enabledColor)
        else
            drawDisabledGameButton(x1, y1, x2, y2, config.label)
        end
    end

    drawGameCard(GAME_CONFIG.roulette, col1X, startY, col1X + colW, startY + btnH, gameStatus.roulette)
    drawGameCard(GAME_CONFIG.slots, col2X, startY, col2X + colW, startY + btnH, gameStatus.slots)

    startY = startY + btnH + gap

    drawGameCard(GAME_CONFIG.coinflip, col1X, startY, col1X + colW, startY + btnH, gameStatus.coinflip)
    drawGameCard(GAME_CONFIG.hilo, col2X, startY, col2X + colW, startY + btnH, gameStatus.hilo)

    startY = startY + btnH + gap

    drawGameCard(GAME_CONFIG.blackjack, col1X, startY, col2X + colW, startY + btnH, gameStatus.blackjack)

    local btnY = mh - 2
    addButton("player_stats", 3, btnY, math.floor(mw/2)-1, btnY, "STATS", colors.white, COLORS.INFO)
    addButton("admin_panel", math.floor(mw/2)+1, btnY, mw-2, btnY, "ADMIN", colors.white, COLORS.ADMIN_BG)
end

-- [... Rest of the code continues with Admin Panel, Games, etc. - truncated for length ...]
-- The fixes are primarily in the player detection functions above
-- All game logic remains unchanged

------------- ERROR HANDLER -------------

local function safeMain()
    local trackingTimer = nil

    local success, err = pcall(function()
        mode="menu"
        drawMainMenu()

        trackingTimer = os.startTimer(2)

        local monitorName = monitor and peripheral.getName(monitor) or nil
        local bridgeName = bridge and peripheral.getName(bridge) or nil

        while true do
            local e, param1, x, y = os.pullEvent()

            if e == "monitor_touch" then
                local side = param1
                if monitorName and (not monitor or not peripheral.isPresent(monitorName)) then
                    error("Monitor wurde entfernt!")
                end
                if monitorName and side == monitorName then
                    local id = hitButton(x,y)
                    if id then handleButton(id) end
                end
            elseif e == "timer" and param1 == trackingTimer then
                trackPlayers()
                trackingTimer = os.startTimer(2)
            elseif e == "peripheral_detach" then
                if monitorName and param1 == monitorName then
                    error("Monitor wurde entfernt!")
                elseif bridgeName and param1 == bridgeName then
                    error("Bridge wurde entfernt!")
                end
            end
        end
    end)

    if not success then
        print("[ERROR] Kritischer Fehler aufgetreten: "..tostring(err))

        gameInProgress = false

        if trackingTimer then
            pcall(os.cancelTimer, trackingTimer)
        end

        pcall(safeSavePlayerStats, "Error cleanup")

        local displaySuccess, displayErr = pcall(function()
            local monName = monitor and peripheral.getName(monitor) or nil
            if monName and peripheral.isPresent(monName) then
                mclearRaw()
                mcenter(math.floor(mh/2),"FEHLER: "..tostring(err),COLOR_WARNING)
                mcenter(math.floor(mh/2)+2,"Neustart in 5 Sekunden...",colors.white)
            end
        end)

        if not displaySuccess then
            print("Kritischer Fehler: "..tostring(err))
            print("Display-Fehler: "..tostring(displayErr))
        end

        sleep(5)
        os.reboot()
    end
end

-- Note: The complete game logic (Roulette, Coinflip, Hilo, Blackjack, Slots, Admin Panel, Stats)
-- has been omitted here for brevity but remains unchanged in the full file.
-- The key fixes are in the player detection functions which now properly handle
-- both string and table formats from the player_detector peripheral.

safeMain()
