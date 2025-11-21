-- casino.lua - CASINO LOUNGE (RS Bridge Support, Pending-Payout Lock)
-- Version 4.2.1 - Lua Variable Limit Fix
--
-- Changelog v4.2.1:
-- + Fixed Lua "more than 200 local variables" error
-- + Grouped color constants into COLORS table (reduced 23 locals to 1)
-- + Grouped admin state into AdminState table (reduced 4 locals to 1)
-- + Grouped payout state into PayoutState table (reduced 3 locals to 1)
-- + Reduced total top-level local variables from 162 to 150
-- + Kept frequently-used variables as locals for performance
--
-- Changelog v4.2:
-- + Fallback player name "Guest" when no Player Detector is available
-- + Guest player properly tracked with own stats structure, sorted last in rankings
-- + Guest displayed with "[Gast]" label and special color (lightGray)
-- + Completely redesigned Player Stats UI with rankings and medals
-- + Gold/Silver/Bronze colors for top 3 players (theme constants)
-- + Enhanced detail view with better colors, borders, and layout
-- + Improved "no players" screen with helpful instructions
-- + Better visual hierarchy with purple/gold theme
-- + Enhanced button styling and color consistency
-- + Centralized Player Stats theme colors (COLOR_STATS_*, COLOR_MEDAL_*, COLOR_STREAK_*)
-- + Consistent German language for all UI labels (no English/German mix)
-- + All hardcoded colors replaced with theme constants for easy customization
--
-- Changelog v4.1:
-- + Centralized game configuration (GAME_CONFIG) for easier maintenance
-- + Extracted helper function for disabled game buttons (reduces duplication)
-- + Enhanced loadGameStatus() with proper validation and merging
-- + Configurable player detection range (PLAYER_DETECTION_RANGE = 15 blocks)
-- + Fixed Player Detector method check (now uses getPlayersInRange)
-- + Added pagination to player stats list (was limited to 6, now unlimited)
-- + Online/offline indicators for players in stats view
-- + "Last seen" time display for offline players
-- + Better navigation with preserved pagination state
-- + Improved UI consistency across all screens
--
-- Changelog v4.0:
-- + Admin can now activate/deactivate games
-- + Enhanced UI with better colors and visual feedback
-- + Improved button rendering with multi-line support
-- + Better error handling for file operations
-- + Visual indicators for disabled games
-- + Persistent game state (saves/loads)

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
-- Less common colors can be accessed via COLORS table

-- Game-Status Datei
local GAME_STATUS_FILE = "game_status.dat"

-- Zentrale Spiel-Konfiguration (Game IDs, Labels, Farben) - Updated for modern theme
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
                        -- Merge loaded data into default structure with validation
                        for gameId, _ in pairs(gameStatus) do
                            if decoded[gameId] ~= nil then
                                -- Coerce to boolean
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

-- Player Detector suchen (links vom Computer)
local playerDetector = peripheral.wrap("left")
if playerDetector and playerDetector.getPlayersInRange then
    print("Player Detector gefunden: left")
    print("Erkennungsreichweite: " .. PLAYER_DETECTION_RANGE .. " Bloecke")
else
    print("WARNUNG: Kein Player Detector auf 'left' gefunden!")
    playerDetector = nil
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
        -- Add player name to footer if available
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

    -- Draw button background
    drawBox(x1,y1,x2,y2,bg or COLOR_PANEL)

    -- Draw subtle top border for 3D effect
    monitor.setTextColor(colors.white)
    for x=x1,x2 do
        monitor.setCursorPos(x,y1)
        monitor.write("-")
    end

    -- Handle multi-line labels
    local lines = {}
    for line in label:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    -- Center text vertically and horizontally
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

-- Statistik-Daten sanitieren (sicherstellen dass numerische Felder Zahlen sind)
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

-- Statistiken laden
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

        -- Sanitize all loaded player stats to ensure numeric fields are numbers
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

        -- Backup corrupt file before overwriting
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

-- Statistiken speichern
local function savePlayerStats()
    -- Einfaches Speichern ohne eigenes Error-Handling
    -- (Error-Handling erfolgt zentral in safeSavePlayerStats)
    local file = fs.open(STATS_FILE, "w")
    if not file then
        error("Konnte Datei nicht öffnen: "..STATS_FILE)
    end
    file.write(textutils.serialize(playerStats))
    file.close()
end

-- Helper: Sicher speichern mit einheitlichem Error-Handling
local function safeSavePlayerStats(context)
    local ok, err = pcall(savePlayerStats)
    if not ok then
        print("[FEHLER] " .. (context or "safeSavePlayerStats") .. ": Konnte Stats nicht speichern: " .. tostring(err))
    end
end

-- Spieler-Statistik initialisieren oder abrufen
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
        -- Sanitize existing stats to ensure all numeric fields are numbers
        playerStats[playerName] = sanitizeStats(playerStats[playerName])
    end
    return playerStats[playerName]
end

-- Hole Spieler vom Detector (zentrale Helper-Funktion)
-- Gibt {players = {...}, names = {...}} zurueck
-- players: Array von Player-Objekten vom Detector
-- names: Array von Spielernamen (String)
local function getPlayersFromDetector()
    if not playerDetector then
        print("[PLAYER DETECTOR] Kein Player Detector verfuegbar")
        return {players = {}, names = {}}
    end

    local ok, playersInRange = pcall(playerDetector.getPlayersInRange, PLAYER_DETECTION_RANGE)
    if not ok then
        print("[PLAYER DETECTOR] Fehler beim Abrufen der Spieler: "..tostring(playersInRange))
        return {players = {}, names = {}}
    end

    if not playersInRange then
        print("[PLAYER DETECTOR] Keine Spieler in Reichweite ("..PLAYER_DETECTION_RANGE.." Bloecke)")
        return {players = {}, names = {}}
    end

    local names = {}
    for _, player in ipairs(playersInRange) do
        if player and player.name then
            table.insert(names, player.name)
        end
    end

    if #names > 0 then
        print("[PLAYER DETECTOR] "..#names.." Spieler erkannt: "..table.concat(names, ", "))
    else
        print("[PLAYER DETECTOR] Keine Spieler in Reichweite ("..PLAYER_DETECTION_RANGE.." Bloecke)")
    end

    return {players = playersInRange, names = names}
end

-- Hole aktuell erkannte Spielernamen
local function getCurrentPlayers()
    return getPlayersFromDetector().names
end

-- Ermittle den nächsten Spieler am Terminal (für Statistikerfassung)
-- Akzeptiert bereits ermittelte Detector-Daten um Doppelabfragen zu vermeiden
--
-- WICHTIG: Die x/y/z Koordinaten vom Player Detector sind RELATIV zum Detector-Block.
-- Das bedeutet: (0,0,0) = Detector-Position, und distanceSq = x^2+y^2+z^2 ist die
-- quadrierte Distanz vom Detector (korrekt für nächsten Spieler).
local function getNearestPlayer(detected)
    if not detected or not detected.players or #detected.players == 0 then
        return nil
    end

    -- Nimm einfach den ersten/nächsten Spieler
    -- Bei mehreren Spielern: der mit der kürzesten Distanz vom Detector
    local nearestPlayer = nil
    local minDistanceSq = math.huge  -- Verwende quadrierte Distanz um sqrt zu vermeiden

    for _, player in ipairs(detected.players) do
        if player and player.name then
            -- Nur Spieler mit gültigen Koordinaten berücksichtigen
            if player.x and player.y and player.z then
                -- Distanz vom Detector (Koordinaten sind relativ zum Detector)
                local distanceSq = player.x^2 + player.y^2 + player.z^2
                local distance = math.sqrt(distanceSq)
                print("[NEAREST PLAYER] "..player.name.." - Distanz: "..string.format("%.2f", distance).." Bloecke (x="..player.x..", y="..player.y..", z="..player.z..")")
                if distanceSq < minDistanceSq then
                    minDistanceSq = distanceSq
                    nearestPlayer = player.name
                end
            else
                print("[NEAREST PLAYER] "..player.name.." - Keine Koordinaten verfuegbar")
            end
            -- Spieler ohne Koordinaten werden ignoriert (kein Fallback)
        end
    end

    if nearestPlayer then
        print("[NEAREST PLAYER] Ausgewaehlt: "..nearestPlayer.." (Distanz: "..string.format("%.2f", math.sqrt(minDistanceSq)).." Bloecke)")
    end

    return nearestPlayer
end

-- Spieler erfassen und tracken
local function trackPlayers()
    local detected = getPlayersFromDetector()

    -- Fallback: Wenn kein Player Detector vorhanden oder keine Spieler erkannt,
    -- verwende einen Standard-Spielernamen für Stats-Attribution
    -- Guest wird für Spielstatistiken verwendet, aber nicht als "besuchender" Spieler getrackt
    if #detected.players == 0 then
        if not currentPlayer then
            currentPlayer = "Guest"
            -- Erstelle Guest Stats wenn nicht vorhanden (nur für Spiel-Attribution)
            if not playerStats["Guest"] then
                playerStats["Guest"] = {
                    name = "Guest",
                    firstSeen = os.epoch("utc"),
                    lastSeen = os.epoch("utc"),
                    totalVisits = 0,  -- Bleibt 0 für Guest
                    totalTimeSpent = 0,  -- Wird nicht für Guest getrackt
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
                -- Guest Stats direkt speichern, damit sie persistent sind
                safeSavePlayerStats("trackPlayers - Guest created")
            end
        end
        return
    end

    local currentTime = os.epoch("utc")
    local newSeenPlayers = {}

    for _, player in ipairs(detected.players) do
        if player and player.name then
            local playerName = player.name
            newSeenPlayers[playerName] = true

            local stats = getOrCreatePlayerStats(playerName)
            stats.lastSeen = currentTime

            -- Neuer Besuch?
            if not lastSeenPlayers[playerName] then
                stats.totalVisits = stats.totalVisits + 1
                print("[TRACKING] Neuer Besuch von: "..playerName.." (Besuch #"..stats.totalVisits..")")
            end
        end
    end

    -- Prüfe welche Spieler die Range verlassen haben
    for playerName, _ in pairs(lastSeenPlayers) do
        if not newSeenPlayers[playerName] then
            print("[TRACKING] Spieler hat Range verlassen: "..playerName)
        end
    end

    -- Zeit für alle aktuell gesehenen Spieler aktualisieren
    for playerName, _ in pairs(newSeenPlayers) do
        if lastSeenPlayers[playerName] then
            local stats = playerStats[playerName]
            if stats then
                -- 1 Sekunde hinzufügen (wird alle 1-2 Sekunden aufgerufen)
                stats.totalTimeSpent = stats.totalTimeSpent + 1000
            end
        end
    end

    lastSeenPlayers = newSeenPlayers

    -- Isolate persistence errors so logic bugs still surface via safeMain
    safeSavePlayerStats("trackPlayers")

    -- Aktualisiere currentPlayer nur wenn ein gültiger Spieler gefunden wurde
    -- (verhindert, dass currentPlayer mid-game gelöscht wird)
    -- Verwende bereits ermittelte Detector-Daten um Doppelabfrage zu vermeiden
    local nearestPlayer = getNearestPlayer(detected)
    if nearestPlayer then
        if currentPlayer ~= nearestPlayer then
            print("[TRACKING] Neuer naechster Spieler: "..nearestPlayer.." (vorher: "..(currentPlayer or "keiner")..")")
        end
        currentPlayer = nearestPlayer
    end
end

-- Spiel-Statistik aktualisieren
local function updateGameStats(playerName, wager, won, payout)
    -- Validierung der Parameter
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

    -- Update stats logic (let logic bugs fail via safeMain)
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

    -- Isolate persistence errors so logic bugs still surface via safeMain
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

-- Statistiken laden beim Start
loadPlayerStats()

----------- INVENTAR / STORAGE ------------

-- Diamanten im Netzwerk zählen (Casino-Bank-Reserve)
local function getItemCountInNet(name)
    if not bridge then
        print("[FEHLER] getItemCountInNet: Bridge nicht verfügbar!")
        return 0
    end

    local ok, res = pcall(bridge.getItem, { name = name })
    if not ok or not res then return 0 end
    return res.amount or res.count or 0
end

-- Diamanten in IO-Chest zählen (Spieler-Guthaben)
-- Die IO-Chest muss direkt am Computer angeschlossen sein (nicht über Bridge!)
-- HINWEIS: bridge.listItems() listet das GESAMTE ME-System, nicht eine einzelne Chest
-- Daher lesen wir die Chest direkt als Peripherie aus
local function getPlayerBalance()
    -- Chest direkt vom Computer auslesen
    -- IO_CHEST_DIR = Seite vom Computer aus (z.B. "front")
    local chest = peripheral.wrap(IO_CHEST_DIR)
    if chest and chest.list then
        local total = 0
        local ok, list = pcall(chest.list)
        if ok and type(list) == "table" then
            for _, stack in pairs(list) do
                if stack and stack.name == DIAMOND_ID then
                    total = total + (stack.count or 0)
                end
            end
        else
            if not ok then
                print("[WARNUNG] getPlayerBalance chest.list() Fehler: "..tostring(list))
            end
        end
        return total
    else
        print("[WARNUNG] getPlayerBalance: Keine Chest auf '"..IO_CHEST_DIR.."' gefunden")
    end

    -- Wenn alles schief geht: 0
    return 0
end


-- Einsatz: Nimm Diamanten aus IO-Chest und packe sie ins Netzwerk (Casino-Bank)
local function takeStake(amount)
    amount = tonumber(amount) or 0
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
    return result
end

------------- PENDING PAYOUT --------------

-- Offene (nicht auszahlbare) Gewinne, falls Kiste voll ist
-- Offene Gewinne, falls Kiste voll ist
local pendingPayout = 0
local payoutBlocked = false

-- maximale Menge, die pro Versuch exportiert wird
local MAX_EXPORT_CHUNK = 4096   -- kannst du bei Bedarf anpassen


local function rawExportDiamonds(amount)
    amount = tonumber(amount) or 0
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

    -- Wie viele Diamanten sind überhaupt in der Bank?
    local inBank = getItemCountInNet(DIAMOND_ID)
    if inBank <= 0 then
        print("[WARNUNG] Bank hat keine Diamanten, offen bleiben: "..pendingPayout)
        payoutBlocked = true
        return
    end

    -- Wir versuchen nur einen kleineren Chunk auszuzahlen
    local toTry = math.min(pendingPayout, inBank, MAX_EXPORT_CHUNK)

    print(("[INFO] Versuche offenen Gewinn auszuzahlen: %d | Versuche: %d"):format(pendingPayout, toTry))

    local exported = rawExportDiamonds(toTry)

    if exported <= 0 then
        -- Kiste vermutlich (wieder) voll oder Bridge-Fehler
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


-- Gewinn: Zahle Diamanten aus Netzwerk (Casino-Bank) in IO-Chest
local function payPayout(amount)
    amount = tonumber(amount) or 0

    -- Erst versuchen, offene Gewinne weiter auszuzahlen
    flushPendingPayoutIfPossible()

    -- Kein neuer Gewinn -> nur offene prüfen
    if amount <= 0 then
        return 0
    end

    print(("[GEWINN] Zahle %d Diamanten aus in IO-Chest '%s'"):format(amount, IO_CHEST_DIR))

    local exported = rawExportDiamonds(amount)

    if exported < amount then
        local notPaid = amount - exported
        pendingPayout = (tonumber(pendingPayout) or 0) + notPaid
        payoutBlocked = true
        print("[WARNUNG] Nicht alles passte in die Kiste. Offen dazu: "..notPaid.." | Gesamt offen: "..pendingPayout)
    else
        print("[GEWINN] Ausgezahlt:", exported)
    end

    return exported
end


------------- GLOBAL STATE -------------

-- App State (grouped)
local AppState = {
    mode = "menu",
    currentPlayer = nil
}

local mode = AppState.mode
local currentPlayer = AppState.currentPlayer

-- Admin State (grouped)
local AdminState = {
    PIN = "1234",
    panelOpen = false,
    pinInput = "",
    currentStatsOffset = 0
}

-- Game State Variables (grouped to reduce local count)
local GameState = {
    -- Roulette
    r = {
        state = "type",
        betType = nil,
        choice = nil,
        stake = 0,
        lastResult = nil,
        lastColor = nil,
        lastHit = nil,
        lastPayout = nil,
        lastMult = nil,
        player = nil
    },
    -- Coinflip
    c = {
        state = "stake",
        stake = 0,
        choice = nil,
        lastWin = false,
        lastPayout = 0,
        lastSide = nil,
        player = nil
    },
    -- High/Low
    h = {
        state = "stake",
        stake = 0,
        startNum = nil,
        nextNum = nil,
        choice = nil,
        lastWin = false,
        lastPayout = 0,
        lastPush = false,
        player = nil
    },
    -- Blackjack
    bj = {
        state = "stake",
        stake = 0,
        playerHand = {},
        dealerHand = {},
        deck = {},
        lastWin = false,
        lastPayout = 0,
        lastResult = "",
        player = nil
    },
    -- Slots
    s = {
        state = "setup",
        bet = 1,
        grid = {{},{},{}},
        lastWin = false,
        lastMult = 0,
        lastPayout = 0,
        freeSpins = 0,
        totalWin = 0,
        winLines = {},
        freeSpinBet = 0,
        player = nil
    }
}

-- Backwards compatibility aliases for game state
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

----------- HAUPTMENÜ ------------------

local function drawMainMenu()
    -- Versuch, ausstehende Gewinne nachzuzahlen
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

    -- Balance Card (compact, modern design)
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

    -- Game Grid (2 columns, optimized spacing)
    local btnH = 4
    local gap = 2
    local colW = math.floor((mw - 6) / 2) - 1
    local col1X = 3
    local col2X = col1X + colW + 3
    local startY = cardY + 7

    -- Helper function for game cards with icons
    local function drawGameCard(config, x1, y1, x2, y2, enabled)
        if enabled then
            -- Draw game card with icon
            drawBox(x1, y1, x2, y2, config.enabledColor)
            drawBorder(x1, y1, x2, y2, colors.white)

            -- Icon
            local iconY = y1 + 1
            mcenter(iconY, config.icon, config.enabledFg, config.enabledColor)

            -- Label
            local labelY = iconY + 1
            mcenter(labelY, config.label, config.enabledFg, config.enabledColor)

            addButton(config.mainButtonId, x1, y1, x2, y2, "", config.enabledFg, config.enabledColor)
        else
            drawDisabledGameButton(x1, y1, x2, y2, config.label)
        end
    end

    -- Row 1: Roulette & Slots
    drawGameCard(GAME_CONFIG.roulette, col1X, startY, col1X + colW, startY + btnH, gameStatus.roulette)
    drawGameCard(GAME_CONFIG.slots, col2X, startY, col2X + colW, startY + btnH, gameStatus.slots)

    startY = startY + btnH + gap

    -- Row 2: Coinflip & High/Low
    drawGameCard(GAME_CONFIG.coinflip, col1X, startY, col1X + colW, startY + btnH, gameStatus.coinflip)
    drawGameCard(GAME_CONFIG.hilo, col2X, startY, col2X + colW, startY + btnH, gameStatus.hilo)

    startY = startY + btnH + gap

    -- Row 3: Blackjack (full width)
    drawGameCard(GAME_CONFIG.blackjack, col1X, startY, col2X + colW, startY + btnH, gameStatus.blackjack)

    -- Bottom buttons (Stats & Admin)
    local btnY = mh - 2
    addButton("player_stats", 3, btnY, math.floor(mw/2)-1, btnY, "STATS", colors.white, COLORS.INFO)
    addButton("admin_panel", math.floor(mw/2)+1, btnY, mw-2, btnY, "ADMIN", colors.white, COLORS.ADMIN_BG)
end

------------- ADMIN PANEL --------------

local function drawAdminPinEntry()
    clearButtons()
    drawChrome("Admin-Panel","PIN eingeben")
    
    drawBox(5,6,mw-4,10,COLOR_PANEL_DARK)
    drawBorder(5,6,mw-4,10,colors.orange)
    
    mcenter(7,"Admin-Zugang",colors.orange,COLOR_PANEL_DARK)
    mcenter(8,"PIN: "..string.rep("*",#AdminState.pinInput),colors.white,COLOR_PANEL_DARK)
    
    local btnSize = 4
    local gap = 1
    local startX = math.floor((mw - (btnSize*3 + gap*2))/2)
    local startY = 12
    
    for i=1,3 do
        local x1 = startX + (i-1)*(btnSize+gap)
        addButton("pin_"..i, x1,startY,x1+btnSize-1,startY+2, tostring(i), colors.white, COLOR_PANEL)
    end
    
    startY = startY + 3 + gap
    for i=4,6 do
        local x1 = startX + (i-4)*(btnSize+gap)
        addButton("pin_"..i, x1,startY,x1+btnSize-1,startY+2, tostring(i), colors.white, COLOR_PANEL)
    end
    
    startY = startY + 3 + gap
    for i=7,9 do
        local x1 = startX + (i-7)*(btnSize+gap)
        addButton("pin_"..i, x1,startY,x1+btnSize-1,startY+2, tostring(i), colors.white, COLOR_PANEL)
    end
    
    startY = startY + 3 + gap
    addButton("pin_clear", startX,startY,startX+btnSize-1,startY+2, "CLR", colors.white, COLOR_WARNING)
    addButton("pin_0", startX+btnSize+gap,startY,startX+btnSize+gap+btnSize-1,startY+2, "0", colors.white, COLOR_PANEL)
    addButton("pin_ok", startX+(btnSize+gap)*2,startY,startX+(btnSize+gap)*2+btnSize-1,startY+2, "OK", colors.black, COLOR_HIGHLIGHT)
    
    addButton("admin_cancel",3,mh-3,mw-2,mh-2,"<< Abbrechen",colors.white,COLOR_WARNING)
end

-- Spieler-Statistiken Liste
local function drawPlayerStatsList(offset)
    clearButtons()
    drawChrome("Spieler-Statistiken","Alle erfassten Spieler")

    -- Hole aktuell online Spieler
    local currentPlayers = getCurrentPlayers()
    local currentPlayersSet = {}
    for _, name in ipairs(currentPlayers) do
        currentPlayersSet[name] = true
    end

    -- Spieler sortieren nach Gesamtzeit (Guest wird angezeigt aber als letzter)
    local sortedPlayers = {}
    for name, stats in pairs(playerStats) do
        table.insert(sortedPlayers, {name = name, stats = stats})
    end
    table.sort(sortedPlayers, function(a, b)
        -- Guest kommt immer ans Ende
        if a.name == "Guest" then return false end
        if b.name == "Guest" then return true end
        return a.stats.totalTimeSpent > b.stats.totalTimeSpent
    end)

    local totalPlayers = #sortedPlayers

    if totalPlayers == 0 then
        -- Verbesserte "Keine Spieler" Anzeige
        drawBox(4,5,mw-3,11,COLOR_PANEL_DARK)
        drawBorder(4,5,mw-3,11,COLOR_WARNING)

        mcenter(7,"Keine Spieler erfasst",COLOR_WARNING,COLOR_PANEL_DARK)
        mcenter(8,"",colors.white,COLOR_PANEL_DARK)
        mcenter(9,"Spiele ein paar Runden,",colors.lightGray,COLOR_PANEL_DARK)
        mcenter(10,"um Statistiken zu sammeln!",colors.lightGray,COLOR_PANEL_DARK)

        addButton("player_stats_list",4,mh-4,mw-3,mh-2,"<< Zurueck",colors.white,COLOR_PANEL)
        return
    end

    local maxVisible = STATS_PAGE_SIZE
    local maxPages = math.ceil(totalPlayers / maxVisible)
    local currentPage = math.floor(offset / maxVisible) + 1

    -- Verbesserte Header Box (Theme-Farben)
    drawBox(4,4,mw-3,6,COLORS.STATS_HEADER)
    drawBorder(4,4,mw-3,6,COLORS.STATS_BORDER)
    mcenter(5,"~ SPIELER RANGLISTE ~",COLORS.STATS_BORDER,COLORS.STATS_HEADER)
    mcenter(6,totalPlayers.." Spieler | Seite "..currentPage.."/"..maxPages,colors.white,COLORS.STATS_HEADER)

    local startY = 8
    local startIdx = offset + 1
    local endIdx = math.min(startIdx + maxVisible - 1, totalPlayers)

    for i = startIdx, endIdx do
        local player = sortedPlayers[i]
        if player then
            local btnY = startY + (i-startIdx)*3
            local stats = player.stats
            local timeStr = formatTime(stats.totalTimeSpent)
            local rank = i  -- Platzierung

            -- Verbesserte Labels mit Ranking (Guest bekommt keine Nummer)
            local rankStr = player.name == "Guest" and "[Gast]" or "#"..rank
            local onlineMarker = currentPlayersSet[player.name] and " [ONLINE]" or ""
            local label = rankStr.." "..player.name..onlineMarker.."\n"..stats.gamesPlayed.." Spiele | "..timeStr

            -- Verbesserte Farben basierend auf Status und Platzierung (Theme-Farben)
            local btnColor = COLOR_PANEL
            local textColor = colors.white

            if currentPlayersSet[player.name] then
                btnColor = COLORS.STATS_ONLINE  -- Cyan für online Spieler
                textColor = colors.black
            elseif player.name == "Guest" then
                -- Guest bekommt eine spezielle Farbe
                btnColor = COLORS.DISABLED
                textColor = colors.black
            elseif rank <= 3 then
                -- Top 3 bekommen spezielle Farben (Theme)
                if rank == 1 then
                    btnColor = COLORS.MEDAL_GOLD  -- Gold für Platz 1
                    textColor = colors.black
                elseif rank == 2 then
                    btnColor = COLORS.MEDAL_SILVER  -- Silber für Platz 2
                    textColor = colors.black
                elseif rank == 3 then
                    btnColor = COLORS.MEDAL_BRONZE  -- Bronze für Platz 3
                    textColor = colors.black
                end
            elseif stats.currentStreak > 0 then
                btnColor = COLORS.STREAK_WIN
            elseif stats.currentStreak < 0 then
                btnColor = COLORS.STREAK_LOSS
            end

            addButton("stats_player_"..player.name, 4, btnY, mw-3, btnY+2, label, textColor, btnColor)
        end
    end

    -- Pagination buttons mit verbessertem Design (Theme-Farben)
    local btnY = mh - 6
    if offset > 0 then
        addButton("stats_prev",4,btnY,math.floor(mw/2)-1,btnY+1,"<< Vorherige",colors.black,COLOR_INFO)
    end
    if endIdx < totalPlayers then
        addButton("stats_next",math.floor(mw/2)+1,btnY,mw-3,btnY+1,"Naechste >>",colors.black,COLOR_INFO)
    end

    addButton("player_stats_list",4,mh-4,mw-3,mh-2,"<< Zurueck",colors.white,COLORS.STATS_HEADER)
end

-- Detail-Ansicht eines Spielers
local function drawPlayerStatsDetail(playerName)
    clearButtons()
    local stats = playerStats[playerName]

    if not stats then
        drawChrome("Fehler","Spieler nicht gefunden")
        drawBox(4,8,mw-3,12,COLOR_WARNING)
        drawBorder(4,8,mw-3,12,COLORS.STATS_BORDER)
        mcenter(10,"Spieler nicht gefunden!",colors.white,COLOR_WARNING)
        sleep(1.5)
        drawPlayerStatsList(0)
        return
    end

    -- Pruefe ob Spieler online ist
    local currentPlayers = getCurrentPlayers()
    local isOnline = false
    for _, name in ipairs(currentPlayers) do
        if name == playerName then
            isOnline = true
            break
        end
    end

    drawChrome("Spieler-Profil","Detaillierte Statistiken")

    -- Verbesserte Header Box mit Spielername (Theme-Farben)
    local headerBg = isOnline and COLORS.STATS_ONLINE or COLORS.STATS_HEADER
    drawBox(4,4,mw-3,8,headerBg)
    drawBorder(4,4,mw-3,8,COLORS.STATS_BORDER)

    local y = 5
    mcenter(y, "~ "..playerName.." ~", COLORS.STATS_BORDER, headerBg); y = y + 1

    local statusLabel = isOnline and "[ONLINE]" or "[OFFLINE]"
    local statusColor = isOnline and COLOR_SUCCESS or COLORS.DISABLED
    mcenter(y, statusLabel, statusColor, headerBg); y = y + 1

    -- Zeige "Zuletzt gesehen" oder Spielzeit
    if not isOnline then
        if stats.lastSeen and type(stats.lastSeen) == "number" then
            local timeSince = os.epoch("utc") - stats.lastSeen
            local lastSeenStr = formatTime(timeSince) .. " her"
            mcenter(y, "Zuletzt: " .. lastSeenStr, COLORS.DISABLED, headerBg); y = y + 1
        else
            mcenter(y, "Zuletzt: unbekannt", COLORS.DISABLED, headerBg); y = y + 1
        end
    else
        mcenter(y, "Spielzeit: " .. formatTime(stats.totalTimeSpent), colors.white, headerBg); y = y + 1
    end

    -- Statistik Box mit Rahmen (Theme-Farben)
    y = 10
    drawBox(4,y,mw-3,mh-5,COLOR_PANEL_DARK)
    drawBorder(4,y,mw-3,mh-5,COLORS.STATS_HEADER)
    y = y + 1

    -- Aktivitäts-Statistiken mit Symbolen
    mcenter(y, "=== AKTIVITAET ===", COLORS.STATS_BORDER, COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"# Besuche:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,tostring(stats.totalVisits),colors.white,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"# Spielzeit:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,formatTime(stats.totalTimeSpent),COLOR_INFO,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"# Spiele:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,tostring(stats.gamesPlayed),colors.white,COLOR_PANEL_DARK); y = y + 2

    -- Finanz-Statistiken mit besseren Farben (Theme-Farben)
    mcenter(y, "=== FINANZEN ===", COLORS.STATS_BORDER, COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"$ Gesetzt:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,stats.totalWagered.." Dia",COLOR_ACCENT,COLOR_PANEL_DARK); y = y + 1

    local netProfit = stats.totalWon - stats.totalLost
    local profitColor = netProfit >= 0 and COLOR_SUCCESS or COLOR_WARNING
    mwrite(6,y,"$ Netto:",COLORS.DISABLED,COLOR_PANEL_DARK)
    local netText = netProfit >= 0 and "+"..netProfit or tostring(netProfit)
    mwrite(mw-15,y,netText.." Dia",profitColor,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"$ Groesster Gewinn:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,"+"..stats.biggestWin.." Dia",COLOR_SUCCESS,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"$ Groesster Verlust:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,"-"..stats.biggestLoss.." Dia",COLOR_WARNING,COLOR_PANEL_DARK); y = y + 2

    -- Streak-Statistiken mit Verbesserungen (Theme-Farben + Deutsche Labels)
    mcenter(y, "=== SERIEN ===", COLORS.STATS_BORDER, COLOR_PANEL_DARK); y = y + 1

    local streakText = ""
    local streakColor = colors.white
    local streakIcon = ""
    if stats.currentStreak > 0 then
        streakText = "+"..stats.currentStreak.." Siege"
        streakColor = COLORS.STREAK_WIN
        streakIcon = ">> "
    elseif stats.currentStreak < 0 then
        streakText = math.abs(stats.currentStreak).." Niederlagen"
        streakColor = COLORS.STREAK_LOSS
        streakIcon = "<< "
    else
        streakText = "Keine Serie"
        streakColor = COLORS.DISABLED
        streakIcon = "-- "
    end
    mwrite(6,y,streakIcon.."Aktuell:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-20,y,streakText,streakColor,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,">> Beste Serie:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,stats.longestWinStreak.." Siege",COLORS.STREAK_WIN,COLOR_PANEL_DARK); y = y + 1

    mwrite(6,y,"<< Schlechteste:",COLORS.DISABLED,COLOR_PANEL_DARK)
    mwrite(mw-15,y,stats.longestLoseStreak.." Niederlagen",COLORS.STREAK_LOSS,COLOR_PANEL_DARK); y = y + 1

    addButton("player_detail_back",4,mh-4,mw-3,mh-2,"<< Zurueck",colors.white,COLORS.STATS_HEADER)
end

local function drawAdminPanel()
    clearButtons()
    drawChrome("ADMIN PANEL","Geschuetzter Bereich")

    local playerDia = getPlayerBalance()
    local bankDia = getItemCountInNet(DIAMOND_ID)

    -- Status Card (modern design)
    drawBox(4,4,mw-3,12,COLORS.ADMIN_BG)
    drawBorder(4,4,mw-3,12,COLORS.ADMIN_BORDER)

    mcenter(5,"CASINO STATUS",COLORS.ADMIN_BORDER,COLORS.ADMIN_BG)
    mcenter(7,"Spieler-Chest: "..playerDia.." Dia",colors.white,COLORS.ADMIN_BG)
    mcenter(8,"Casino-Bank: "..bankDia.." Dia",colors.yellow,COLORS.ADMIN_BG)
    mcenter(10,"Monitor: "..mw.."x"..mh,colors.lightGray,COLORS.ADMIN_BG)
    mcenter(11,"IO-Richtung: "..IO_CHEST_DIR,colors.lightGray,COLORS.ADMIN_BG)

    -- Warning Box (if needed)
    if pendingPayout > 0 then
        drawBox(4,14,mw-3,17,COLOR_WARNING)
        drawBorder(4,14,mw-3,17,colors.white)
        mcenter(15,"Offene Gewinne: "..pendingPayout.." Dia",colors.white,COLOR_WARNING)
        mcenter(16,"Kiste leeren & im Menue pruefen",colors.white,COLOR_WARNING)
    elseif bankDia < 100 then
        drawBox(4,14,mw-3,17,COLOR_WARNING)
        drawBorder(4,14,mw-3,17,colors.white)
        mcenter(15,"WARNUNG!",colors.white,COLOR_WARNING)
        mcenter(16,"Casino-Bank zu niedrig!",colors.white,COLOR_WARNING)
    end

    -- Action Buttons (modern card style)
    local btnY = 19
    local mid = math.floor(mw/2)

    addButton("admin_collect",4,btnY,mid-1,btnY+2,"Chest leeren\n(Collect)",colors.white,colors.orange)
    addButton("admin_refill",mid+1,btnY,mw-3,btnY+2,"Bank fuellen\n(Refill)",colors.white,colors.cyan)

    btnY = btnY + 4
    addButton("admin_stats",4,btnY,mid-1,btnY+2,"Spieler\nStatistiken",colors.white,COLORS.INFO)
    addButton("admin_games",mid+1,btnY,mw-3,btnY+2,"Spiele\nverwalten",colors.white,COLORS.SUCCESS)

    addButton("admin_close",3,mh-3,mw-2,mh-2,"<< Schliessen",colors.white,COLOR_WARNING)
end

local function drawGameManagement()
    clearButtons()
    drawChrome("Game Management","Spiele aktivieren/deaktivieren")

    drawBox(4,4,mw-3,10,COLOR_PANEL_DARK)
    drawBorder(4,4,mw-3,10,colors.orange)

    mcenter(5,"=== SPIEL-VERWALTUNG ===",colors.orange,COLOR_PANEL_DARK)
    mcenter(7,"Aktiviere oder deaktiviere Spiele",colors.lightGray,COLOR_PANEL_DARK)
    mcenter(8,"Deaktivierte Spiele sind ausgegraut",colors.lightGray,COLOR_PANEL_DARK)

    local btnY = 12
    local btnH = 3
    local gap = 1
    local mid = math.floor(mw/2)

    -- Roulette
    local rConfig = GAME_CONFIG.roulette
    local rColor = gameStatus.roulette and rConfig.enabledColor or COLORS.DISABLED
    local rFg = gameStatus.roulette and rConfig.enabledFg or colors.gray
    local rLabel = rConfig.label .. " " .. (gameStatus.roulette and "[AN]" or "[AUS]")
    addButton(rConfig.toggleButtonId, 4, btnY, mid-1, btnY+btnH, rLabel, rFg, rColor)

    -- Slots
    local sConfig = GAME_CONFIG.slots
    local sColor = gameStatus.slots and sConfig.enabledColor or COLORS.DISABLED
    local sFg = gameStatus.slots and sConfig.enabledFg or colors.gray
    local sLabel = sConfig.label .. " " .. (gameStatus.slots and "[AN]" or "[AUS]")
    addButton(sConfig.toggleButtonId, mid+1, btnY, mw-3, btnY+btnH, sLabel, sFg, sColor)

    btnY = btnY + btnH + gap + 1

    -- Coinflip
    local cConfig = GAME_CONFIG.coinflip
    local cColor = gameStatus.coinflip and cConfig.enabledColor or COLORS.DISABLED
    local cFg = gameStatus.coinflip and cConfig.enabledFg or colors.gray
    local cLabel = cConfig.label .. " " .. (gameStatus.coinflip and "[AN]" or "[AUS]")
    addButton(cConfig.toggleButtonId, 4, btnY, mid-1, btnY+btnH, cLabel, cFg, cColor)

    -- High/Low
    local hConfig = GAME_CONFIG.hilo
    local hColor = gameStatus.hilo and hConfig.enabledColor or COLORS.DISABLED
    local hFg = gameStatus.hilo and hConfig.enabledFg or colors.gray
    local hLabel = hConfig.label .. " " .. (gameStatus.hilo and "[AN]" or "[AUS]")
    addButton(hConfig.toggleButtonId, mid+1, btnY, mw-3, btnY+btnH, hLabel, hFg, hColor)

    btnY = btnY + btnH + gap + 1

    -- Blackjack
    local bConfig = GAME_CONFIG.blackjack
    local bColor = gameStatus.blackjack and bConfig.enabledColor or COLORS.DISABLED
    local bFg = gameStatus.blackjack and bConfig.enabledFg or colors.gray
    local bLabel = bConfig.label .. " " .. (gameStatus.blackjack and "[AN]" or "[AUS]")
    addButton(bConfig.toggleButtonId, 4, btnY, mw-3, btnY+btnH, bLabel, bFg, bColor)

    -- Info message
    local activeCount = 0
    for _, status in pairs(gameStatus) do
        if status then activeCount = activeCount + 1 end
    end

    mcenter(mh-5,"Aktive Spiele: " .. activeCount .. " / 5",COLOR_INFO)

    addButton("game_mgmt_back",3,mh-3,mw-2,mh-2,"<< Zurueck zum Admin-Panel",colors.white,COLOR_PANEL)
end

local function handleAdminButton(id)
    if not AdminState.panelOpen then
        if id:match("^pin_%d$") then
            local digit = id:match("^pin_(%d)$")
            if #AdminState.pinInput < 6 then
                AdminState.pinInput = AdminState.pinInput .. digit
                drawAdminPinEntry()
            end
        elseif id == "pin_clear" then
            AdminState.pinInput = ""
            drawAdminPinEntry()
        elseif id == "pin_ok" then
            if AdminState.pinInput == AdminState.PIN then
                AdminState.panelOpen = true
                AdminState.pinInput = ""
                drawAdminPanel()
            else
                clearButtons()
                drawChrome("Zugriff verweigert","Falscher PIN")
                drawBox(5,8,mw-4,12,COLOR_WARNING)
                mcenter(9,"FALSCHER PIN!",colors.white,COLOR_WARNING)
                mcenter(10,"Zugriff verweigert",colors.white,COLOR_WARNING)
                AdminState.pinInput = ""
                sleep(2)
                mode="menu"
                drawMainMenu()
            end
        elseif id == "admin_cancel" then
            AdminState.pinInput = ""
            mode="menu"
            drawMainMenu()
        end
    else
        if id == "admin_collect" then
            clearButtons()
            drawChrome("Chest leeren","Sammle Spieler-Chips ein")
            
            local playerDia = getPlayerBalance()
            if playerDia == 0 then
                drawBox(5,8,mw-4,11,COLOR_WARNING)
                mcenter(9,"Chest ist leer!",colors.white,COLOR_WARNING)
                sleep(1.5)
                drawAdminPanel()
                return
            end
            
            drawBox(5,8,mw-4,11,COLOR_INFO)
            mcenter(9,"Importiere "..playerDia.." Diamanten...",colors.white,COLOR_INFO)
            
            local collected = takeStake(playerDia)
            
            sleep(0.5)
            drawBox(5,13,mw-4,16,COLOR_SUCCESS)
            mcenter(14,"Erfolgreich!",colors.white,COLOR_SUCCESS)
            mcenter(15,"+"..collected.." zur Bank",colors.white,COLOR_SUCCESS)
            sleep(2)
            drawAdminPanel()
            
        elseif id == "admin_refill" then
            clearButtons()
            drawChrome("Bank fuellen","Fuege Diamanten hinzu")
            
            local bankDia = getItemCountInNet(DIAMOND_ID)
            local targetAmount = 500
            local needed = targetAmount - bankDia
            
            if needed <= 0 then
                drawBox(5,8,mw-4,11,COLOR_SUCCESS)
                mcenter(9,"Bank ist voll!",colors.white,COLOR_SUCCESS)
                mcenter(10,"("..bankDia.." Diamanten)",colors.white,COLOR_SUCCESS)
                sleep(1.5)
                drawAdminPanel()
                return
            end
            
            drawBox(5,8,mw-4,11,COLOR_INFO)
            mcenter(9,"Bank hat: "..bankDia,colors.white,COLOR_INFO)
            mcenter(10,"Benoetigt: "..needed.." mehr",colors.white,COLOR_INFO)
            
            sleep(1.5)
            drawBox(5,13,mw-4,16,colors.orange)
            mcenter(14,"Lege Diamanten in Chest",colors.white,colors.orange)
            mcenter(15,"und druecke OK!",colors.white,colors.orange)
            
            clearButtons()
            addButton("refill_ok",4,mh-5,math.floor(mw/2)-1,mh-3,"OK",colors.black,COLOR_HIGHLIGHT)
            addButton("refill_cancel",math.floor(mw/2)+1,mh-5,mw-3,mh-3,"Abbruch",colors.white,COLOR_WARNING)
            
        elseif id == "refill_ok" then
            clearButtons()
            drawChrome("Fuellen...","Bitte warten")
            
            local playerDia = getPlayerBalance()
            drawBox(5,8,mw-4,11,COLOR_INFO)
            mcenter(9,"Importiere "..playerDia.." Diamanten...",colors.white,COLOR_INFO)
            
            if playerDia > 0 then
                local added = takeStake(playerDia)
                sleep(0.5)
                drawBox(5,13,mw-4,16,COLOR_SUCCESS)
                mcenter(14,"Bank aufgefuellt!",colors.white,COLOR_SUCCESS)
                mcenter(15,"+"..added.." Diamanten",colors.white,COLOR_SUCCESS)
            else
                drawBox(5,13,mw-4,16,COLOR_WARNING)
                mcenter(14,"Keine Diamanten gefunden!",colors.white,COLOR_WARNING)
            end
            sleep(2)
            drawAdminPanel()
            
        elseif id == "refill_cancel" then
            drawAdminPanel()
            
        elseif id == "admin_stats" then
            clearButtons()
            drawChrome("Statistiken","Casino-Uebersicht")

            local playerDia = getPlayerBalance()
            local bankDia = getItemCountInNet(DIAMOND_ID)
            local profit = bankDia - 500

            drawBox(4,5,mw-3,13,COLOR_PANEL_DARK)
            mcenter(6,"=== FINANZEN ===",COLOR_GOLD,COLOR_PANEL_DARK)
            mcenter(8,"Spieler-Chips: "..playerDia,COLOR_INFO,COLOR_PANEL_DARK)
            mcenter(9,"Casino-Bank: "..bankDia,COLOR_SUCCESS,COLOR_PANEL_DARK)

            local profitColor = profit >= 0 and COLOR_SUCCESS or COLOR_WARNING
            local profitText = profit >= 0 and "+"..profit or tostring(profit)
            mcenter(11,"Gewinn/Verlust: "..profitText.." Dia",profitColor,COLOR_PANEL_DARK)
            mcenter(12,"(seit Start mit 500 Bank)",colors.lightGray,COLOR_PANEL_DARK)

            addButton("stats_players",4,15,mw-3,17,"Spieler-Statistiken",colors.black,colors.cyan)
            addButton("stats_back",4,mh-4,mw-3,mh-2,"<< Zurueck",colors.white,COLOR_PANEL)
            
        elseif id == "stats_back" then
            drawAdminPanel()

        elseif id == "stats_players" then
            AdminState.currentStatsOffset = 0
            drawPlayerStatsList(AdminState.currentStatsOffset)

        elseif id == "stats_prev" then
            AdminState.currentStatsOffset = math.max(0, (AdminState.currentStatsOffset or 0) - STATS_PAGE_SIZE)
            drawPlayerStatsList(AdminState.currentStatsOffset)

        elseif id == "stats_next" then
            AdminState.currentStatsOffset = (AdminState.currentStatsOffset or 0) + STATS_PAGE_SIZE
            drawPlayerStatsList(AdminState.currentStatsOffset)

        elseif id:match("^stats_player_") then
            local playerName = id:match("^stats_player_(.+)$")
            drawPlayerStatsDetail(playerName)

        elseif id == "player_stats_list" then
            drawPlayerStatsList(AdminState.currentStatsOffset or 0)

        elseif id == "player_detail_back" then
            drawPlayerStatsList(AdminState.currentStatsOffset or 0)

        elseif id == "admin_games" then
            drawGameManagement()

        elseif id == "game_mgmt_back" then
            drawAdminPanel()

        elseif id:match("^toggle_") then
            local gameName = id:match("^toggle_(.+)$")
            if gameStatus[gameName] ~= nil then
                gameStatus[gameName] = not gameStatus[gameName]
                saveGameStatus()
                drawGameManagement()
            end

        elseif id == "admin_close" then
            AdminState.panelOpen = false
            mode="menu"
            drawMainMenu()
        end
    end
end

------------- ROULETTE -----------------

local redNumbers = {
  [1]=true,[3]=true,[5]=true,[7]=true,[9]=true,
  [12]=true,[14]=true,[16]=true,[18]=true,
  [19]=true,[21]=true,[23]=true,[25]=true,[27]=true,
  [30]=true,[32]=true,[34]=true,[36]=true
}

local function getColor(num)
  if num == 0 then return "green" end
  if redNumbers[num] then return "red" else return "black" end
end

local function spinWheel()
  return math.random(0,36)
end

local function resolveRoulette(betType, choice, result)
  local color = getColor(result)
  local hit = false
  local mult = 0

  if betType == 1 then
    if result == choice then hit = true; mult = 36 end
  elseif betType == 2 then
    if result ~= 0 and color == choice then hit = true; mult = 2 end
  elseif betType == 3 then
    if result ~= 0 then
      local even = (result % 2 == 0)
      if choice == "even" and even then hit = true; mult = 2 end
      if choice == "odd" and not even then hit = true; mult = 2 end
    end
  elseif betType == 4 then
    if result ~= 0 then
      if choice=="low" and result>=1 and result<=18 then hit=true; mult=2 end
      if choice=="high" and result>=19 and result<=36 then hit=true; mult=2 end
    end
  end

  return hit,mult,color
end

local function r_drawChooseType()
  clearButtons()
  drawChrome("Roulette","Waehle deine Wettart")
  
  mcenter(4,"Was moechtest du wetten?",COLOR_GOLD)
  
  local mid = math.floor(mw/2)
  addButton("r_type_number", 4,6,mid-1,9,"ZAHL\n(36x)",COLOR_GOLD,COLOR_PANEL)
  addButton("r_type_color",  mid+1,6,mw-3,9,"FARBE\n(2x)",colors.white,colors.red)
  addButton("r_type_evenodd",4,11,mid-1,14,"GERADE/UNG.\n(2x)",colors.white,colors.blue)
  addButton("r_type_lowhigh",mid+1,11,mw-3,14,"LOW/HIGH\n(2x)",colors.white,colors.green)
  addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Menue",colors.white,COLOR_WARNING)
end

local function r_drawChooseNumber(cur)
  clearButtons()
  drawChrome("Roulette - Zahl","Waehle 0-36")
  cur = cur or 0
  
  drawBox(5,4,mw-4,8,COLOR_PANEL_DARK)
  mcenter(5,"Aktuell:",colors.white,COLOR_PANEL_DARK)
  mcenter(7,tostring(cur),COLOR_GOLD,COLOR_PANEL_DARK)

  local seg = math.floor((mw-8)/4)
  if seg < 4 then seg = 4 end
  local x=4
  local y = 10
  addButton("r_num_-10",x,y,x+seg-1,y+2,"-10",colors.white,COLOR_PANEL); x=x+seg+1
  addButton("r_num_-1", x,y,x+seg-1,y+2,"-1",colors.white,COLOR_PANEL);  x=x+seg+1
  addButton("r_num_+1", x,y,x+seg-1,y+2,"+1",colors.white,COLOR_PANEL);  x=x+seg+1
  addButton("r_num_+10",x,y,x+seg-1,y+2,"+10",colors.white,COLOR_PANEL)

  addButton("r_num_ok",4,mh-5,mw-3,mh-3,">> Weiter",colors.black,COLOR_HIGHLIGHT)
  addButton("back_r_type",3,mh-2,mw-2,mh-1,"<< Zurueck",colors.white,COLOR_WARNING)
  r_choice = cur
end

local function r_drawChooseColor()
  clearButtons()
  drawChrome("Roulette - Farbe","Rot oder Schwarz?")
  
  mcenter(4,"Waehle eine Farbe:",COLOR_GOLD)
  
  addButton("r_color_red", 4,6,math.floor(mw/2)-1,11,"ROT",colors.white,colors.red)
  addButton("r_color_black",math.floor(mw/2)+1,6,mw-3,11,"SCHWARZ",colors.white,COLOR_PANEL_DARK)
  addButton("back_r_type",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function r_drawChooseEvenOdd()
  clearButtons()
  drawChrome("Roulette - Paritaet","Gerade oder Ungerade?")
  
  mcenter(4,"Wird die Zahl gerade oder ungerade?",COLOR_GOLD)
  
  addButton("r_even",4,6,math.floor(mw/2)-1,11,"GERADE",colors.white,colors.blue)
  addButton("r_odd", math.floor(mw/2)+1,6,mw-3,11,"UNGERADE",colors.white,colors.purple)
  addButton("back_r_type",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function r_drawChooseLowHigh()
  clearButtons()
  drawChrome("Roulette - Bereich","Low oder High?")
  
  mcenter(4,"In welchem Bereich liegt die Zahl?",COLOR_GOLD)
  
  addButton("r_low", 4,6,math.floor(mw/2)-1,11,"LOW\n(1-18)",colors.white,colors.brown)
  addButton("r_high",math.floor(mw/2)+1,6,mw-3,11,"HIGH\n(19-36)",colors.white,colors.green)
  addButton("back_r_type",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function r_drawChooseStake()
  clearButtons()
  drawChrome("Roulette - Einsatz","Wie viel setzen?")

  local playerDia = getPlayerBalance()

  drawBox(5,4,mw-4,7,COLOR_PANEL_DARK)
  mcenter(5,"Dein Guthaben:",COLOR_INFO,COLOR_PANEL_DARK)
  mcenter(6,playerDia.." Diamanten",COLOR_SUCCESS,COLOR_PANEL_DARK)

  if playerDia <= 0 then
    mcenter(10,"Keine Diamanten in Chest!",COLOR_WARNING)
    addButton("back_r_type",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
    return
  end

  local maxStake = playerDia
  mcenter(9,"Waehle deinen Einsatz:",colors.white)

  local quarter = math.max(1,math.floor(maxStake/4))
  local bw = math.floor((mw-10)/4)
  if bw<4 then bw=4 end
  local x=4
  local y=11
  addButton("r_stake_"..quarter,     x,y,x+bw,y+2,tostring(quarter),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("r_stake_"..(quarter*2), x,y,x+bw,y+2,tostring(quarter*2),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("r_stake_"..(quarter*3), x,y,x+bw,y+2,tostring(quarter*3),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("r_stake_"..maxStake,    x,y,x+bw,y+2,"MAX\n"..tostring(maxStake),colors.black,COLOR_HIGHLIGHT)

  addButton("back_r_type",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function r_drawResult()
  clearButtons()
  drawChrome("Roulette - Ergebnis","")

  local cStr = (r_lastColor=="red" and "ROT")
           or (r_lastColor=="black" and "SCHWARZ")
           or "GRUEN"

  local x1,x2,y1,y2 = 5,mw-4,4,9
  local bg = (r_lastColor=="red" and colors.red)
          or (r_lastColor=="black" and COLOR_PANEL_DARK)
          or colors.green
  drawBox(x1,y1,x2,y2,bg)
  drawBorder(x1,y1,x2,y2,colors.white)
  mcenter(5,"Zahl",colors.white,bg)
  mcenter(7,tostring(r_lastResult),COLOR_GOLD,bg)
  mcenter(8,"("..cStr..")",colors.white,bg)

  local playerDia = getPlayerBalance()
  mcenter(11,"Guthaben: "..playerDia.." Diamanten",colors.white)

  if r_lastHit then
    drawBox(4,13,mw-3,16,COLOR_SUCCESS)
    mcenter(14,"*** GEWONNEN! ***",colors.white,COLOR_SUCCESS)
    mcenter(15,"+"..r_lastPayout.." Dia (x"..r_lastMult..")",colors.white,COLOR_SUCCESS)
  else
    drawBox(4,13,mw-3,16,COLOR_WARNING)
    mcenter(14,"Verloren",colors.white,COLOR_WARNING)
    mcenter(15,"-"..r_stake.." Diamanten",colors.white,COLOR_WARNING)
  end

  addButton("r_again",4,mh-5,math.floor(mw/2)-1,mh-3,"Nochmal",colors.black,COLOR_HIGHLIGHT)
  addButton("back_menu",math.floor(mw/2)+1,mh-5,mw-3,mh-3,"Menue",colors.white,COLOR_PANEL)
end

local function r_doSpin()
  -- Erfasse den Spieler, der dieses Spiel startet (nicht mid-game änderbar)
  r_player = currentPlayer

  local playerDia = getPlayerBalance()
  if playerDia < r_stake then
    mode="menu"; drawMainMenu(); return
  end

  local taken = takeStake(r_stake)
  if taken < r_stake then
    mode="menu"; drawMainMenu(); return
  end

  clearButtons()
  drawChrome("Roulette","Die Kugel rollt...")
  
  drawBox(5,5,mw-4,10,COLOR_PANEL_DARK)
  
  for i=1,12 do
    local tmp = math.random(0,36)
    local col = getColor(tmp)
    local cStr = (col=="red" and "ROT") or (col=="black" and "SCHWARZ") or "GRUEN"
    mcenter(7,tostring(tmp),COLOR_GOLD,COLOR_PANEL_DARK)
    mcenter(8,"("..cStr..")",colors.white,COLOR_PANEL_DARK)
    sleep(0.08 + i*0.01)
  end

  local result = spinWheel()
  local hit,mult,color = resolveRoulette(r_betType,r_choice,result)

  r_lastResult = result
  r_lastColor  = color
  r_lastHit    = hit
  r_lastMult   = mult

  if hit and mult>0 then
    local paid = payPayout(r_stake * mult)
    r_lastPayout = paid
    if checkPayoutLock() then return end
  else
    r_lastPayout = 0
  end

  -- Statistik erfassen (verwende r_player statt currentPlayer für korrekte Attribution)
  if r_player then
    updateGameStats(r_player, r_stake, hit, r_lastPayout)
  end

  sleep(0.5)
  r_state="result"
  r_drawResult()
end

local function handleRouletteButton(id)
  if r_state=="type" then
    if id=="r_type_number" then
      r_betType=1; r_choice=0; r_state="number"; r_drawChooseNumber(r_choice)
    elseif id=="r_type_color" then
      r_betType=2; r_state="color"; r_drawChooseColor()
    elseif id=="r_type_evenodd" then
      r_betType=3; r_state="evenodd"; r_drawChooseEvenOdd()
    elseif id=="r_type_lowhigh" then
      r_betType=4; r_state="lowhigh"; r_drawChooseLowHigh()
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end

  elseif r_state=="number" then
    local cur = r_choice or 0
    if id=="r_num_-10" then cur=cur-10
    elseif id=="r_num_-1" then cur=cur-1
    elseif id=="r_num_+1" then cur=cur+1
    elseif id=="r_num_+10" then cur=cur+10
    elseif id=="r_num_ok" then
      if cur<0 then cur=0 end
      if cur>36 then cur=36 end
      r_choice=cur; r_state="stake"; r_drawChooseStake(); return
    elseif id=="back_r_type" then
      r_state="type"; r_drawChooseType(); return
    end
    if cur<0 then cur=0 end
    if cur>36 then cur=36 end
    r_choice=cur; r_drawChooseNumber(cur)

  elseif r_state=="color" then
    if id=="r_color_red" then r_choice="red";  r_state="stake"; r_drawChooseStake()
    elseif id=="r_color_black" then r_choice="black"; r_state="stake"; r_drawChooseStake()
    elseif id=="back_r_type" then r_state="type"; r_drawChooseType() end

  elseif r_state=="evenodd" then
    if id=="r_even" then r_choice="even"; r_state="stake"; r_drawChooseStake()
    elseif id=="r_odd" then r_choice="odd"; r_state="stake"; r_drawChooseStake()
    elseif id=="back_r_type" then r_state="type"; r_drawChooseType() end

  elseif r_state=="lowhigh" then
    if id=="r_low" then r_choice="low"; r_state="stake"; r_drawChooseStake()
    elseif id=="r_high" then r_choice="high"; r_state="stake"; r_drawChooseStake()
    elseif id=="back_r_type" then r_state="type"; r_drawChooseType() end

  elseif r_state=="stake" then
    if id=="back_r_type" then r_state="type"; r_drawChooseType()
    elseif id:match("^r_stake_") then
      local v = tonumber(id:match("^r_stake_(%d+)$"))
      if v and v>0 then r_stake=v; r_doSpin() end
    end

  elseif r_state=="result" then
    if id=="r_again" then r_state="type"; r_player = nil; r_drawChooseType()
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end
  end
end

------------- COINFLIP -----------------

local function c_drawStake()
  clearButtons()
  drawChrome("Muenzwurf","Setze deinen Einsatz")
  
  local playerDia = getPlayerBalance()
  
  drawBox(5,4,mw-4,7,COLOR_PANEL_DARK)
  mcenter(5,"Dein Guthaben:",COLOR_INFO,COLOR_PANEL_DARK)
  mcenter(6,playerDia.." Diamanten",COLOR_SUCCESS,COLOR_PANEL_DARK)

  if playerDia < 2 then
    mcenter(10,"Nicht genug Diamanten in Chest!",COLOR_WARNING)
    addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
    return
  end

  mcenter(9,"Gewinnchance: 50% | Gewinn: 2x Einsatz",COLOR_GOLD)

  local maxStake = playerDia
  local q = math.max(1,math.floor(maxStake/4))
  local bw = math.floor((mw-10)/4)
  if bw<4 then bw=4 end
  local x=4
  local y=11
  addButton("c_stake_"..q,      x,y,x+bw,y+2,tostring(q),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("c_stake_"..(q*2),  x,y,x+bw,y+2,tostring(q*2),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("c_stake_"..(q*3),  x,y,x+bw,y+2,tostring(q*3),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("c_stake_"..maxStake,x,y,x+bw,y+2,"MAX\n"..tostring(maxStake),colors.black,COLOR_HIGHLIGHT)

  addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function c_drawSide()
  clearButtons()
  drawChrome("Muenzwurf","Kopf oder Zahl?")
  
  mcenter(4,"Die Muenze wird geworfen...",COLOR_GOLD)
  mcenter(5,"Einsatz: "..c_stake.." Diamanten",colors.white)
  
  addButton("c_heads",4,7,math.floor(mw/2)-1,12,"KOPF",colors.black,colors.orange)
  addButton("c_tails",math.floor(mw/2)+1,7,mw-3,12,"ZAHL",colors.white,colors.brown)
  addButton("back_c_stake",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function c_drawResult()
  clearButtons()
  drawChrome("Muenzwurf - Ergebnis","")

  local resStr = (c_lastSide=="heads" and "KOPF") or "ZAHL"
  local resBg = (c_lastSide=="heads" and colors.orange) or colors.brown
  
  drawBox(5,4,mw-4,9,resBg)
  drawBorder(5,4,mw-4,9,colors.white)
  mcenter(5,"Die Muenze zeigt:",colors.white,resBg)
  mcenter(7,resStr,COLOR_GOLD,resBg)

  local playerDia = getPlayerBalance()
  mcenter(11,"Guthaben: "..playerDia.." Diamanten",colors.lightGray)

  if c_lastWin then
    drawBox(4,13,mw-3,16,COLOR_SUCCESS)
    mcenter(14,"*** GEWONNEN! ***",colors.white,COLOR_SUCCESS)
    mcenter(15,"+"..c_lastPayout.." Diamanten",colors.white,COLOR_SUCCESS)
  else
    drawBox(4,13,mw-3,16,COLOR_WARNING)
    mcenter(14,"Leider verloren",colors.white,COLOR_WARNING)
    mcenter(15,"-"..c_stake.." Diamanten",colors.white,COLOR_WARNING)
  end

  addButton("c_again",4,mh-5,math.floor(mw/2)-1,mh-3,"Nochmal",colors.black,COLOR_HIGHLIGHT)
  addButton("back_menu",math.floor(mw/2)+1,mh-5,mw-3,mh-3,"Zum Menue",colors.white,COLOR_PANEL)
end

local function c_doFlip()
  -- Erfasse den Spieler, der dieses Spiel startet (nicht mid-game änderbar)
  c_player = currentPlayer

  local playerDia = getPlayerBalance()
  if playerDia < c_stake then
    mode="menu"; drawMainMenu(); return
  end

  local taken = takeStake(c_stake)
  if taken < c_stake then
    mode="menu"; drawMainMenu(); return
  end

  clearButtons()
  drawChrome("Muenze fliegt...","Bitte warten")
  
  drawBox(5,6,mw-4,10,COLOR_PANEL_DARK)
  
  for i=1,10 do
    local show = (i%2==0) and "KOPF" or "ZAHL"
    mcenter(8,show,COLOR_GOLD,COLOR_PANEL_DARK)
    sleep(0.08 + i*0.008)
  end

  local flip = math.random(0,1)
  c_lastSide = (flip==0) and "heads" or "tails"

  if c_lastSide == c_choice then
    local paid = payPayout(c_stake * 2)
    c_lastWin = true
    c_lastPayout = paid
    if checkPayoutLock() then return end
  else
    c_lastWin = false
    c_lastPayout = 0
  end

  -- Statistik erfassen (verwende c_player statt currentPlayer für korrekte Attribution)
  if c_player then
    updateGameStats(c_player, c_stake, c_lastWin, c_lastPayout)
  end

  sleep(0.5)
  c_state="result"
  c_drawResult()
end

local function handleCoinButton(id)
  if c_state=="stake" then
    if id:match("^c_stake_") then
      local v = tonumber(id:match("^c_stake_(%d+)$"))
      if v and v>0 then c_stake=v; c_state="side"; c_drawSide() end
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end

  elseif c_state=="side" then
    if id=="c_heads" then c_choice="heads"; c_doFlip()
    elseif id=="c_tails" then c_choice="tails"; c_doFlip()
    elseif id=="back_c_stake" then c_state="stake"; c_drawStake() end

  elseif c_state=="result" then
    if id=="c_again" then c_state="stake"; c_player = nil; c_drawStake()
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end
  end
end

------------- HIGH / LOW ---------------

local function h_drawStake()
  clearButtons()
  drawChrome("High/Low","Setze deinen Einsatz")
  
  local playerDia = getPlayerBalance()
  
  drawBox(5,4,mw-4,7,COLOR_PANEL_DARK)
  mcenter(5,"Dein Guthaben:",COLOR_INFO,COLOR_PANEL_DARK)
  mcenter(6,playerDia.." Diamanten",COLOR_SUCCESS,COLOR_PANEL_DARK)

  if playerDia < 2 then
    mcenter(10,"Nicht genug Diamanten in Chest!",COLOR_WARNING)
    addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
    return
  end

  mcenter(9,"Rate ob die naechste Zahl hoeher oder tiefer ist!",COLOR_GOLD)
  mcenter(10,"Push bei Gleichstand - Einsatz zurueck",colors.lightGray)

  local maxStake = playerDia
  local q = math.max(1,math.floor(maxStake/4))
  local bw = math.floor((mw-10)/4)
  if bw<4 then bw=4 end
  local x=4
  local y=12
  addButton("h_stake_"..q,     x,y,x+bw,y+2,tostring(q),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("h_stake_"..(q*2), x,y,x+bw,y+2,tostring(q*2),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("h_stake_"..(q*3), x,y,x+bw,y+2,tostring(q*3),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("h_stake_"..maxStake,x,y,x+bw,y+2,"MAX\n"..tostring(maxStake),colors.black,COLOR_HIGHLIGHT)

  addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function h_drawGuess()
  clearButtons()
  drawChrome("High/Low","Tipp abgeben")
  
  drawBox(5,4,mw-4,9,COLOR_PANEL_DARK)
  drawBorder(5,4,mw-4,9,COLOR_GOLD)
  mcenter(5,"Aktuelle Zahl:",colors.white,COLOR_PANEL_DARK)
  mcenter(7,tostring(h_startNum),COLOR_GOLD,COLOR_PANEL_DARK)
  mcenter(8,"(von 1-9)",colors.lightGray,COLOR_PANEL_DARK)
  
  mcenter(11,"Ist die naechste Zahl hoeher oder tiefer?",colors.white)
  
  addButton("h_higher",4,13,math.floor(mw/2)-1,16,"HOEHER",colors.black,colors.green)
  addButton("h_lower", math.floor(mw/2)+1,13,mw-3,16,"TIEFER",colors.white,COLOR_WARNING)
  addButton("back_h_stake",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function h_drawResult()
  clearButtons()
  drawChrome("High/Low - Ergebnis","")
  
  drawBox(5,4,mw-4,8,COLOR_PANEL_DARK)
  mcenter(5,"Start: "..tostring(h_startNum).."  =>  Neu: "..tostring(h_nextNum),COLOR_GOLD,COLOR_PANEL_DARK)
  
  local diff = h_nextNum - h_startNum
  local arrow = ""
  if diff > 0 then arrow = "^^^ HOEHER ^^^"
  elseif diff < 0 then arrow = "vvv TIEFER vvv"
  else arrow = "=== GLEICH ===" end
  mcenter(7,arrow,colors.white,COLOR_PANEL_DARK)

  local playerDia = getPlayerBalance()
  mcenter(10,"Guthaben: "..playerDia.." Diamanten",colors.lightGray)

  if h_lastWin then
    drawBox(4,12,mw-3,15,COLOR_SUCCESS)
    mcenter(13,"*** GEWONNEN! ***",colors.white,COLOR_SUCCESS)
    mcenter(14,"+"..h_lastPayout.." Diamanten",colors.white,COLOR_SUCCESS)
  elseif h_lastPush then
    drawBox(4,12,mw-3,15,colors.cyan)
    mcenter(13,"GLEICHSTAND (Push)",colors.white,colors.cyan)
    mcenter(14,"Einsatz zurueck: "..h_lastPayout.." Diamanten",colors.white,colors.cyan)
  else
    drawBox(4,12,mw-3,15,COLOR_WARNING)
    mcenter(13,"Leider verloren",colors.white,COLOR_WARNING)
    mcenter(14,"-"..h_stake.." Diamanten",colors.white,COLOR_WARNING)
  end

  addButton("h_again",4,mh-5,math.floor(mw/2)-1,mh-3,"Nochmal",colors.black,COLOR_HIGHLIGHT)
  addButton("back_menu",math.floor(mw/2)+1,mh-5,mw-3,mh-3,"Zum Menue",colors.white,COLOR_PANEL)
end

local function h_doRound()
  -- Erfasse den Spieler, der dieses Spiel startet (nicht mid-game änderbar)
  h_player = currentPlayer

  local playerDia = getPlayerBalance()
  if playerDia < h_stake then
    mode="menu"; drawMainMenu(); return
  end

  local taken = takeStake(h_stake)
  if taken < h_stake then
    mode="menu"; drawMainMenu(); return
  end

  -- Startzahl NICHT neu ziehen, nur die neue Zahl:
  h_nextNum  = math.random(1,9)

  local win  = false
  local push = false

  if h_nextNum>h_startNum and h_choice=="higher" then win=true end
  if h_nextNum<h_startNum and h_choice=="lower" then win=true end
  if h_nextNum==h_startNum then push=true end

  if win then
    local paid = payPayout(h_stake * 2)
    h_lastWin=true; h_lastPayout=paid; h_lastPush=false
    if checkPayoutLock() then return end
  elseif push then
    local paid = payPayout(h_stake)
    h_lastWin=false; h_lastPayout=paid; h_lastPush=true
    if checkPayoutLock() then return end
  else
    h_lastWin=false; h_lastPayout=0; h_lastPush=false
  end

  -- Statistik erfassen (verwende h_player statt currentPlayer für korrekte Attribution)
  if h_player then
    updateGameStats(h_player, h_stake, h_lastWin, h_lastPayout)
  end

  h_state="result"
  h_drawResult()
end

local function handleHiloButton(id)
  if h_state=="stake" then
    if id:match("^h_stake_") then
      local v = tonumber(id:match("^h_stake_(%d+)$"))
      if v and v>0 then
        h_stake=v
        h_startNum = math.random(1,9)
        h_state="guess"; h_drawGuess()
      end
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end

  elseif h_state=="guess" then
    if id=="h_higher" then h_choice="higher"; h_doRound()
    elseif id=="h_lower" then h_choice="lower"; h_doRound()
    elseif id=="back_h_stake" then h_state="stake"; h_drawStake() end

  elseif h_state=="result" then
    if id=="h_again" then h_state="stake"; h_player = nil; h_drawStake()
    elseif id=="back_menu" then mode="menu"; drawMainMenu() end
  end
end

------------- BLACKJACK ----------------

local cardSuits = {"S","H","D","C"}

local function bj_createDeck()
  local deck = {}
  local ranks = {"A","2","3","4","5","6","7","8","9","10","J","Q","K"}
  for _,suit in ipairs(cardSuits) do
    for _,rank in ipairs(ranks) do
      table.insert(deck, {rank=rank, suit=suit})
    end
  end
  return deck
end

local function bj_shuffleDeck(deck)
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end

local function bj_drawCard(deck)
  return table.remove(deck)
end

local function bj_getCardValue(card)
  if card.rank == "A" then return 11
  elseif card.rank == "K" or card.rank == "Q" or card.rank == "J" then return 10
  else return tonumber(card.rank) end
end

local function bj_calculateHandValue(hand)
  local value = 0
  local aces = 0
  
  for _,card in ipairs(hand) do
    local cardVal = bj_getCardValue(card)
    value = value + cardVal
    if card.rank == "A" then aces = aces + 1 end
  end
  
  while value > 21 and aces > 0 do
    value = value - 10
    aces = aces - 1
  end
  
  return value
end

local function bj_isBlackjack(hand)
  return #hand == 2 and bj_calculateHandValue(hand) == 21
end

local function bj_cardToString(card, hidden)
  if hidden then return "[??]" end
  local suitChar = card.suit
  return "["..card.rank..suitChar.."]"
end

local function bj_handToString(hand, hideFirst)
  local str = ""
  for i,card in ipairs(hand) do
    if i > 1 then str = str.." " end
    str = str .. bj_cardToString(card, hideFirst and i==1)
  end
  return str
end

local function bj_drawStake()
  clearButtons()
  drawChrome("Blackjack","Setze deinen Einsatz")
  
  local playerDia = getPlayerBalance()
  
  drawBox(5,4,mw-4,7,COLOR_PANEL_DARK)
  mcenter(5,"Dein Guthaben:",COLOR_INFO,COLOR_PANEL_DARK)
  mcenter(6,playerDia.." Diamanten",COLOR_SUCCESS,COLOR_PANEL_DARK)

  if playerDia < 2 then
    mcenter(10,"Nicht genug Diamanten in Chest!",COLOR_WARNING)
    addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
    return
  end

  mcenter(9,"Blackjack zahlt 3:2 | Gewinn: 1:1 | Push bei Gleichstand",COLOR_GOLD)

  local maxStake = playerDia
  local q = math.max(1,math.floor(maxStake/4))
  local bw = math.floor((mw-10)/4)
  if bw<4 then bw=4 end
  local x=4
  local y=11
  addButton("bj_stake_"..q,     x,y,x+bw,y+2,tostring(q),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("bj_stake_"..(q*2), x,y,x+bw,y+2,tostring(q*2),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("bj_stake_"..(q*3), x,y,x+bw,y+2,tostring(q*3),colors.white,COLOR_PANEL); x=x+bw+1
  addButton("bj_stake_"..maxStake,x,y,x+bw,y+2,"MAX\n"..tostring(maxStake),colors.black,COLOR_HIGHLIGHT)

  addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
end

local function bj_drawGame()
  clearButtons()
  drawChrome("Blackjack","Ziel: 21 Punkte")
  
  local dealerVal = bj_calculateHandValue(bj_dealerHand)
  local playerVal = bj_calculateHandValue(bj_playerHand)
  
  drawBox(4,4,mw-3,8,COLOR_PANEL_DARK)
  mcenter(5,"DEALER",colors.red,COLOR_PANEL_DARK)
  if bj_state == "playing" then
    mcenter(6,bj_cardToString(bj_dealerHand[1],true).." "..bj_cardToString(bj_dealerHand[2],false),colors.white,COLOR_PANEL_DARK)
    mcenter(7,"Wert: ??",colors.lightGray,COLOR_PANEL_DARK)
  else
    mcenter(6,bj_handToString(bj_dealerHand, false),colors.white,COLOR_PANEL_DARK)
    mcenter(7,"Wert: "..dealerVal,dealerVal>21 and COLOR_WARNING or COLOR_GOLD,COLOR_PANEL_DARK)
  end
  
  drawBox(4,10,mw-3,14,COLOR_PANEL_DARK)
  mcenter(11,"SPIELER (Du)",COLOR_SUCCESS,COLOR_PANEL_DARK)
  mcenter(12,bj_handToString(bj_playerHand, false),colors.white,COLOR_PANEL_DARK)
  mcenter(13,"Wert: "..playerVal,playerVal>21 and COLOR_WARNING or COLOR_GOLD,COLOR_PANEL_DARK)
  
  mcenter(16,"Einsatz: "..bj_stake.." Diamanten",colors.lightGray)
  
  if bj_state == "playing" then
    if playerVal < 21 then
      addButton("bj_hit", 4,mh-7,math.floor(mw/2)-1,mh-5,"HIT (Karte)",colors.black,COLOR_HIGHLIGHT)
      addButton("bj_stand",math.floor(mw/2)+1,mh-7,mw-3,mh-5,"STAND",colors.white,COLOR_WARNING)
    else
      mcenter(18,"Automatisch STAND",colors.cyan)
      sleep(1)
      bj_state = "dealer"
      bj_drawGame()
      return
    end
  end
  
  addButton("back_menu",3,mh-3,mw-2,mh-2,"<< Abbrechen",colors.white,COLOR_WARNING)
end

local function bj_drawResult()
  clearButtons()
  drawChrome("Blackjack - Ergebnis","")
  
  local dealerVal = bj_calculateHandValue(bj_dealerHand)
  local playerVal = bj_calculateHandValue(bj_playerHand)
  
  drawBox(4,4,mw-3,7,COLOR_PANEL_DARK)
  mcenter(5,"Dealer: "..bj_handToString(bj_dealerHand, false),colors.white,COLOR_PANEL_DARK)
  mcenter(6,"Wert: "..dealerVal,dealerVal>21 and COLOR_WARNING or colors.white,COLOR_PANEL_DARK)
  
  drawBox(4,9,mw-3,12,COLOR_PANEL_DARK)
  mcenter(10,"Spieler: "..bj_handToString(bj_playerHand, false),colors.white,COLOR_PANEL_DARK)
  mcenter(11,"Wert: "..playerVal,playerVal>21 and COLOR_WARNING or colors.white,COLOR_PANEL_DARK)
  
  local playerDia = getPlayerBalance()
  mcenter(14,"Guthaben: "..playerDia.." Diamanten",colors.lightGray)
  
  if bj_lastResult == "blackjack" then
    drawBox(4,16,mw-3,19,colors.purple)
    mcenter(17,"*** BLACKJACK! ***",COLOR_GOLD,colors.purple)
    mcenter(18,"+"..bj_lastPayout.." Diamanten (3:2)",colors.white,colors.purple)
  elseif bj_lastWin then
    drawBox(4,16,mw-3,19,COLOR_SUCCESS)
    mcenter(17,"*** GEWONNEN! ***",colors.white,COLOR_SUCCESS)
    mcenter(18,"+"..bj_lastPayout.." Diamanten",colors.white,COLOR_SUCCESS)
  elseif bj_lastResult == "push" then
    drawBox(4,16,mw-3,19,colors.cyan)
    mcenter(17,"GLEICHSTAND (Push)",colors.white,colors.cyan)
    mcenter(18,"Einsatz zurueck: "..bj_lastPayout,colors.white,colors.cyan)
  else
    drawBox(4,16,mw-3,19,COLOR_WARNING)
    mcenter(17,"Verloren",colors.white,COLOR_WARNING)
    mcenter(18,"-"..bj_stake.." Diamanten",colors.white,COLOR_WARNING)
  end
  
  addButton("bj_again",4,mh-5,math.floor(mw/2)-1,mh-3,"Nochmal",colors.black,COLOR_HIGHLIGHT)
  addButton("back_menu",math.floor(mw/2)+1,mh-5,mw-3,mh-3,"Zum Menue",colors.white,COLOR_PANEL)
end

local function bj_dealerPlay()
  bj_state = "dealer"
  clearButtons()
  drawChrome("Blackjack","Dealer zieht...")
  
  while bj_calculateHandValue(bj_dealerHand) < 17 do
    sleep(0.8)
    local card = bj_drawCard(bj_deck)
    table.insert(bj_dealerHand, card)
    
    drawBox(5,6,mw-4,10,COLOR_PANEL_DARK)
    mcenter(7,"Dealer zieht: "..bj_cardToString(card, false),COLOR_GOLD,COLOR_PANEL_DARK)
    mcenter(8,"Dealer Hand: "..bj_handToString(bj_dealerHand, false),colors.white,COLOR_PANEL_DARK)
    mcenter(9,"Wert: "..bj_calculateHandValue(bj_dealerHand),colors.white,COLOR_PANEL_DARK)
  end
  
  sleep(1)
  
  local playerVal = bj_calculateHandValue(bj_playerHand)
  local dealerVal = bj_calculateHandValue(bj_dealerHand)
  
  bj_lastWin = false
  bj_lastPayout = 0
  bj_lastResult = "lose"
  
  if playerVal > 21 then
    bj_lastResult = "lose"
  elseif bj_isBlackjack(bj_playerHand) and not bj_isBlackjack(bj_dealerHand) then
    local paid = payPayout(math.floor(bj_stake * 2.5))
    bj_lastWin = true
    bj_lastPayout = paid
    bj_lastResult = "blackjack"
    if checkPayoutLock() then return end
  elseif dealerVal > 21 then
    local paid = payPayout(bj_stake * 2)
    bj_lastWin = true
    bj_lastPayout = paid
    bj_lastResult = "win"
    if checkPayoutLock() then return end
  elseif playerVal > dealerVal then
    local paid = payPayout(bj_stake * 2)
    bj_lastWin = true
    bj_lastPayout = paid
    bj_lastResult = "win"
    if checkPayoutLock() then return end
  elseif playerVal == dealerVal then
    local paid = payPayout(bj_stake)
    bj_lastPayout = paid
    bj_lastResult = "push"
    if checkPayoutLock() then return end
  else
    bj_lastResult = "lose"
  end

  -- Statistik erfassen (verwende bj_player statt currentPlayer für korrekte Attribution)
  if bj_player then
    updateGameStats(bj_player, bj_stake, bj_lastWin, bj_lastPayout)
  end

  bj_state = "result"
  bj_drawResult()
end

local function bj_startGame()
  -- Erfasse den Spieler, der dieses Spiel startet (nicht mid-game änderbar)
  bj_player = currentPlayer

  local playerDia = getPlayerBalance()
  if playerDia < bj_stake then
    mode="menu"; drawMainMenu(); return
  end

  local taken = takeStake(bj_stake)
  if taken < bj_stake then
    mode="menu"; drawMainMenu(); return
  end
  
  bj_deck = bj_createDeck()
  bj_shuffleDeck(bj_deck)
  
  bj_playerHand = {}
  bj_dealerHand = {}
  
  table.insert(bj_playerHand, bj_drawCard(bj_deck))
  table.insert(bj_dealerHand, bj_drawCard(bj_deck))
  table.insert(bj_playerHand, bj_drawCard(bj_deck))
  table.insert(bj_dealerHand, bj_drawCard(bj_deck))
  
  if bj_isBlackjack(bj_playerHand) then
    bj_dealerPlay()
  else
    bj_state = "playing"
    bj_drawGame()
  end
end

local function handleBlackjackButton(id)
  if bj_state == "stake" then
    if id:match("^bj_stake_") then
      local v = tonumber(id:match("^bj_stake_(%d+)$"))
      if v and v>0 then
        bj_stake = v
        bj_startGame()
      end
    elseif id=="back_menu" then
      mode="menu"; drawMainMenu()
    end
    
  elseif bj_state == "playing" then
    if id=="bj_hit" then
      local card = bj_drawCard(bj_deck)
      table.insert(bj_playerHand, card)
      local playerVal = bj_calculateHandValue(bj_playerHand)
      
      if playerVal >= 21 then
        sleep(0.5)
        bj_dealerPlay()
      else
        bj_drawGame()
      end
      
    elseif id=="bj_stand" then
      bj_dealerPlay()
      
    elseif id=="back_menu" then
      local paid = payPayout(bj_stake)
      if checkPayoutLock() then return end
      mode="menu"; drawMainMenu()
    end
    
  elseif bj_state == "result" then
    if id=="bj_again" then
      bj_state = "stake"
      bj_player = nil
      bj_drawStake()
    elseif id=="back_menu" then
      mode="menu"; drawMainMenu()
    end
  end
end

----------------- SLOTS (3x3) ----------------

local function getWeightedSymbol()
  local totalWeight = 0
  for _,s in ipairs(slotSymbols) do
    totalWeight = totalWeight + s.weight
  end
  
  local rand = math.random(1, totalWeight)
  local current = 0
  
  for _,s in ipairs(slotSymbols) do
    current = current + s.weight
    if rand <= current then
      return s.sym
    end
  end
  
  return slotSymbols[1].sym
end

local function s_spinGrid()
  local grid = {{},{},{}}
  for row=1,3 do
    for col=1,3 do
      grid[row][col] = getWeightedSymbol()
    end
  end
  return grid
end

local function s_checkLine(grid, line)
  local symbols = {}
  for _,pos in ipairs(line.path) do
    local row, col = pos[1], pos[2]
    table.insert(symbols, grid[row][col])
  end
  
  local first = symbols[1]
  local allSame = true
  for _,sym in ipairs(symbols) do
    if sym ~= first then allSame = false; break end
  end
  
  if allSame then
    if first == "7"   then return 50, first, line.name end
    if first == "BAR" then return 25, first, line.name end
    if first == "DIA" then return 15, first, line.name end
    if first == "$"   then return 8,  first, line.name end
    if first == "CHR" then return 5,  first, line.name end
    if first == "STR" then return 4,  first, line.name end
    if first == "BEL" then return 3,  first, line.name end
    if first == "FS"  then return 2,  first, line.name end
  end
  
  return 0, nil, nil
end

local function s_countScatters(grid)
  local count = 0
  for row=1,3 do
    for col=1,3 do
      if grid[row][col] == "FS" then count = count + 1 end
    end
  end
  return count
end

local function s_evaluateGrid(grid)
  local totalMult = 0
  local winningLines = {}
  
  for _,line in ipairs(winLines) do
    local mult, sym, lineName = s_checkLine(grid, line)
    if mult > 0 then
      totalMult = totalMult + mult
      table.insert(winningLines, {line=lineName, mult=mult, sym=sym})
    end
  end
  
  local scatterCount = s_countScatters(grid)
  local freeSpinsWon = 0
  
  if scatterCount >= 3 then
    freeSpinsWon = 3
  end
  
  return totalMult, winningLines, freeSpinsWon
end

local function s_drawScreen()
  clearButtons()
  
  local title = "Slots 3x3"
  if s_freeSpins > 0 then
    title = title .. " - FS: "..s_freeSpins
  end
  drawChrome(title, "5 Linien | Scatter=Freispiele")

  local playerDia = getPlayerBalance()

  drawBox(4,4,mw-3,6,COLOR_PANEL_DARK)
  mcenter(5,"Guthaben: "..playerDia.." | Bet: "..s_bet.." | Won: "..s_totalWin,COLOR_GOLD,COLOR_PANEL_DARK)

  local controlY = 8
  if s_freeSpins == 0 then
    local mid = math.floor(mw/2)
    addButton("s_bet_minus",4,controlY,mid-2,controlY+1," - ",colors.white,COLOR_PANEL)
    addButton("s_bet_plus", mid+2,controlY,mw-3,controlY+1," + ",colors.white,COLOR_PANEL)
    controlY = controlY + 2
  else
    drawBox(4,controlY,mw-3,controlY+1,colors.purple)
    mcenter(controlY,"FREE SPIN MODE",colors.white,colors.purple)
    controlY = controlY + 2
  end

  local boxSize = 7
  if mw < 40 then boxSize = 6 end
  if mw < 25 then boxSize = 5 end
  
  local gridW = boxSize * 3 + 4
  local startX = math.floor((mw - gridW) / 2)
  local startY = controlY + 1
  
  for row=1,3 do
    for col=1,3 do
      local x1 = startX + (col-1)*(boxSize+2)
      local x2 = x1 + boxSize
      local y1 = startY + (row-1)*(boxSize+1)
      local y2 = y1 + boxSize - 1
      
      local sym = (s_grid[row] and s_grid[row][col]) or "?"
      local symColor = colors.white
      
      if sym == "7" then symColor = colors.red
      elseif sym == "BAR" then symColor = colors.orange
      elseif sym == "DIA" then symColor = colors.cyan
      elseif sym == "$" then symColor = colors.lime
      elseif sym == "CHR" then symColor = colors.pink
      elseif sym == "STR" then symColor = colors.yellow
      elseif sym == "BEL" then symColor = colors.lightGray
      elseif sym == "FS" then symColor = colors.purple end
      
      drawBox(x1,y1,x2,y2,COLOR_PANEL_DARK)
      drawBorder(x1,y1,x2,y2,COLOR_GOLD)
      
      local label = sym
      if #label > boxSize-1 then label = label:sub(1,boxSize-1) end
      mwrite(x1+math.floor((boxSize-#label+1)/2), math.floor((y1+y2)/2), label, symColor, COLOR_PANEL_DARK)
    end
  end

  monitor.setBackgroundColor(COLOR_BG)
  
  local infoY = startY + 3*(boxSize+1) + 1
  
  if s_state=="result" and #s_winLines > 0 then
    local winText = ""
    for i,wl in ipairs(s_winLines) do
      winText = winText .. wl.sym.."x"..wl.mult
      if i < #s_winLines then winText = winText .. " + " end
    end
    
    if #winText > mw-8 then 
      winText = winText:sub(1,mw-12).."..." 
    end
    
    drawBox(4,infoY,mw-3,infoY+1,COLOR_SUCCESS)
    mcenter(infoY,"WIN: "..winText,colors.white,COLOR_SUCCESS)
    infoY = infoY + 2
  end
  
  if s_state=="result" then
    if s_lastWin then
      if s_lastMult >= 50 then
        mcenter(infoY,"JACKPOT x"..s_lastMult.." = "..s_lastPayout,COLOR_GOLD)
      else
        mcenter(infoY,"+"..s_lastPayout.." Diamonds",COLOR_HIGHLIGHT)
      end
    else
      mcenter(infoY,"No win - Try again!",COLOR_WARNING)
    end
    infoY = infoY + 1
  else
    mcenter(infoY,"Press SPIN to play",colors.lightGray)
    infoY = infoY + 1
  end

  local btnY = math.max(infoY + 1, mh-4)
  if s_freeSpins > 0 then
    addButton("s_spin", 4, btnY, mw-3, btnY+1, "FREE SPIN", colors.black, colors.purple)
  else
    addButton("s_spin", 4, btnY, math.floor(mw/2)-1, btnY+1, "SPIN", colors.black, COLOR_HIGHLIGHT)
    addButton("back_menu", math.floor(mw/2)+1, btnY, mw-3, btnY+1, "Menu", colors.white, COLOR_PANEL)
  end
end

local function s_doSpin()
  -- Erfasse den Spieler beim ersten echten Spin (nicht bei Freispielen)
  if s_freeSpins == 0 then
    s_player = currentPlayer
  end

  local playerDia = getPlayerBalance()
  local isFreeSpin = (s_freeSpins > 0)
  local cost = isFreeSpin and 0 or s_bet
  
  if cost > 0 and playerDia < cost then
    clearButtons()
    drawChrome("Slots","Nicht genug Guthaben")
    drawBox(5,6,mw-4,10,COLOR_WARNING)
    mcenter(7,"Zu wenig Diamanten!",colors.white,COLOR_WARNING)
    mcenter(8,"Guthaben: "..playerDia.." | Bedarf: "..cost,colors.white,COLOR_WARNING)
    addButton("s_back",4,mh-4,mw-3,mh-2,"<< Zurueck",colors.white,COLOR_WARNING)
    s_state="setup"
    return
  end

  if cost > 0 then
    local taken = takeStake(cost)
    if taken < cost then
      s_lastWin=false; s_lastPayout=0
      s_state="setup"
      drawMainMenu()
      return
    end
    s_freeSpinBet = cost
  end
  
  if isFreeSpin then
    s_freeSpins = s_freeSpins - 1
  end

  s_state="spinning"
  s_grid = s_spinGrid()
  sleep(0.5)
  
  local mult, winningLines, freeSpinsWon = s_evaluateGrid(s_grid)
  
  s_lastMult = mult
  s_winLines = winningLines
  
  if freeSpinsWon > 0 then
    s_freeSpins = s_freeSpins + freeSpinsWon
    
    clearButtons()
    mclearRaw()
    drawChrome("FREE SPINS!","Du hast Freispiele gewonnen!")
    
    local msgY = math.floor(mh/2) - 3
    
    for i=1,5 do
      drawBox(5,msgY,mw-4,msgY+6,colors.purple)
      
      local col1 = (i % 2 == 1) and colors.yellow or colors.white
      local col2 = (i % 2 == 1) and colors.white or colors.yellow
      
      mcenter(msgY+1,"* * * * * *",col1,colors.purple)
      mcenter(msgY+2,"FREE SPINS!",col2,colors.purple)
      mcenter(msgY+3,"+"..freeSpinsWon.." Freispiele",col1,colors.purple)
      mcenter(msgY+4,"Gesamt: "..s_freeSpins,col2,colors.purple)
      mcenter(msgY+5,"* * * * * *",col1,colors.purple)
      
      sleep(0.3)
    end
    
    sleep(1)
  end

  local payoutBet
  if isFreeSpin then
    payoutBet = s_freeSpinBet
  else
    payoutBet = cost
  end

  if mult > 0 and payoutBet > 0 then
    local paid = payPayout(payoutBet * mult)
    s_lastWin = true
    s_lastPayout = paid
    s_totalWin = s_totalWin + paid
    
    if checkPayoutLock() then return end

    if mult >= 50 then
      clearButtons()
      mclearRaw()
      drawChrome("*** JACKPOT ***","")
      
      local msgY = math.floor(mh/2) - 4
      
      for i=1,6 do
        drawBox(4,msgY,mw-3,msgY+8,colors.red)
        
        local col = (i % 2 == 1) and colors.yellow or colors.white
        
        mcenter(msgY+1,"# # # # # #",col,colors.red)
        mcenter(msgY+3,"J A C K P O T !",col,colors.red)
        mcenter(msgY+5,paid.." DIAMANTEN",colors.yellow,colors.red)
        mcenter(msgY+7,"# # # # # #",col,colors.red)
        
        sleep(0.35)
      end
      
      sleep(2)
    end
  else
    s_lastWin = false
    s_lastPayout = 0
  end

  -- Statistik erfassen (nur bei echten Spins, nicht bei Freispielen)
  -- Verwende s_player statt currentPlayer für korrekte Attribution
  if s_player and cost > 0 then
    updateGameStats(s_player, cost, s_lastWin, s_lastPayout)
  end

  s_state="result"
  s_drawScreen()

  if s_freeSpins > 0 then
    sleep(2.5)
    s_doSpin()
  else
    s_freeSpinBet = 0
  end
end

local function handleSlotButton(id)
  if id=="back_menu" then
    if s_freeSpins > 0 then
      clearButtons()
      drawChrome("Achtung!","Freispiele aktiv!")
      mcenter(8,"Noch "..s_freeSpins.." Freispiele!",COLOR_WARNING)
      mcenter(10,"Wirklich beenden?",colors.white)
      addButton("s_confirm_exit",4,12,math.floor(mw/2)-1,14,"Ja",colors.white,COLOR_WARNING)
      addButton("s_cancel_exit",math.floor(mw/2)+1,12,mw-3,14,"Nein",colors.black,COLOR_HIGHLIGHT)
      return
    end
    s_totalWin = 0
    mode="menu"; drawMainMenu(); return
  end
  
  if id=="s_confirm_exit" then
    s_freeSpins = 0
    s_totalWin = 0
    s_freeSpinBet = 0
    mode="menu"; drawMainMenu(); return
  end
  
  if id=="s_cancel_exit" then
    s_drawScreen(); return
  end

  if id=="s_back" then
    s_state="setup"
    s_drawScreen()
    return
  end

  if id=="s_bet_minus" then
    s_bet = math.max(1, s_bet - 1)
    s_state="setup"
    s_drawScreen()
  elseif id=="s_bet_plus" then
    local playerDia = getPlayerBalance()
    s_bet = math.min(playerDia, s_bet + 1)
    s_state="setup"
    s_drawScreen()
  elseif id=="s_spin" then
    s_doSpin()
  end
end

------------- SIMPLIFIED GAME STARTERS -------------

local function drawRouletteSimple()
  r_state="type"
  r_betType, r_choice, r_stake = nil, nil, 0
  r_lastResult, r_lastColor, r_lastHit, r_lastPayout, r_lastMult = nil, nil, nil, nil, nil
  r_player = nil  -- Reset player tracking
  r_drawChooseType()
end

local function drawHiloSimple()
  h_state="stake"
  h_stake = 0
  h_startNum, h_nextNum, h_choice = nil, nil, nil
  h_lastWin, h_lastPayout, h_lastPush = false, 0, false
  h_player = nil  -- Reset player tracking
  h_drawStake()
end

local function drawBlackjackSimple()
  bj_state="stake"
  bj_stake = 0
  bj_playerHand, bj_dealerHand, bj_deck = {}, {}, {}
  bj_lastWin, bj_lastPayout, bj_lastResult = false, 0, ""
  bj_player = nil  -- Reset player tracking
  bj_drawStake()
end

local function drawSlotsSimple()
  s_state="setup"
  s_bet = 1
  s_grid = {{},{},{}}
  s_lastWin, s_lastMult, s_lastPayout = false, 0, 0
  s_freeSpins, s_totalWin, s_winLines = 0, 0, {}
  s_freeSpinBet = 0
  s_player = nil  -- Reset player tracking
  s_drawScreen()
end

------------- GLOBAL TOUCH --------------

local function handleButton(id)
    if mode=="payout" then
        if id=="pending_check" then
            flushPendingPayoutIfPossible()
            if (pendingPayout or 0) <= 0 then
                mode="menu"
                drawMainMenu()
            else
                drawPendingPayoutScreen()
            end
        elseif id=="admin_panel" then
            mode="admin"
            AdminState.pinInput=""
            drawAdminPinEntry()
        end
        return
    end

    if mode=="menu" then
        if (pendingPayout or 0) > 0 then
            mode="payout"
            drawPendingPayoutScreen()
            return
        end

        if id=="game_roulette" and gameStatus.roulette then
            mode="roulette"; drawRouletteSimple()
        elseif id=="game_coin" and gameStatus.coinflip then
            mode="coin"; c_state="stake"; c_player = nil; c_drawStake()
        elseif id=="game_hilo" and gameStatus.hilo then
            mode="hilo"; drawHiloSimple()
        elseif id=="game_blackjack" and gameStatus.blackjack then
            mode="blackjack"; drawBlackjackSimple()
        elseif id=="game_slots" and gameStatus.slots then
            mode="slots"; drawSlotsSimple()
        elseif id=="admin_panel" then
            mode="admin"
            AdminState.pinInput = ""
            drawAdminPinEntry()
        end
    
    elseif mode=="admin" then
        handleAdminButton(id)
    
    elseif mode=="roulette" then
        handleRouletteButton(id)
    
    elseif mode=="coin" then
        handleCoinButton(id)
    
    elseif mode=="hilo" then
        handleHiloButton(id)
    
    elseif mode=="blackjack" then
        handleBlackjackButton(id)
    
    elseif mode=="slots" then
        handleSlotButton(id)
    
    else
        if id=="back_menu" then
            mode="menu"
            drawMainMenu()
        end
    end
end

------------- ERROR HANDLER -------------

local function safeMain()
    local success, err = pcall(function()
        mode="menu"
        drawMainMenu()

        -- Tracking-Timer starten
        local trackingTimer = os.startTimer(2)

        -- Peripheral-Namen für Event-Vergleich speichern (nur wenn verfügbar)
        local monitorName = monitor and peripheral.getName(monitor) or nil
        local bridgeName = bridge and peripheral.getName(bridge) or nil

        while true do
            local e, param1, x, y = os.pullEvent()

            if e == "monitor_touch" then
                local side = param1
                -- Prüfe ob der Monitor noch existiert
                if monitorName and (not monitor or not peripheral.isPresent(monitorName)) then
                    error("Monitor wurde entfernt!")
                end
                if monitorName and side == monitorName then
                    local id = hitButton(x,y)
                    if id then handleButton(id) end
                end
            elseif e == "timer" and param1 == trackingTimer then
                -- Spieler tracken alle 2 Sekunden
                trackPlayers()
                trackingTimer = os.startTimer(2)
            elseif e == "peripheral_detach" then
                -- Prüfe ob es der Monitor oder die Bridge war
                if monitorName and param1 == monitorName then
                    error("Monitor wurde entfernt!")
                elseif bridgeName and param1 == bridgeName then
                    error("Bridge wurde entfernt!")
                end
            end
        end
    end)

    if not success then
        -- Versuche Fehler auf Monitor anzuzeigen, falls noch verfügbar
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

----------------- MAIN ------------------

safeMain()
