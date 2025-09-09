-- Configure package.path for requiring Prometheus
local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/%\\])") or "";
end
package.path = script_path() .. "?.lua;" .. package.path;

-- Require Prometheus modules directly
local Prometheus = require("src.prometheus");
local Ast = require("src.prometheus.ast");
local Parser = require("src.prometheus.parser");
local Enums = require("src.prometheus.enums");

-- Extensions pour les archives
local function getFileExtension(filename)
    return filename:match("^.+(%..+)$") or ""
end

-- Fonction pour créer un dossier
local function createDirectory(path)
    local success = os.execute(string.format('mkdir -p "%s"', path))
    return success == 0 or success == true
end

-- Fonction pour supprimer un dossier récursivement
local function removeDirectory(path)
    local success = os.execute(string.format('rm -rf "%s"', path))
    return success == 0 or success == true
end

-- Fonction pour extraire les archives ZIP (version corrigée)
local function extractZip(inputPath, extractPath)
    print("Extraction de:", inputPath, "vers:", extractPath)
    
    -- Créer le dossier de destination
    if not createDirectory(extractPath) then
        print("Erreur: Impossible de créer le dossier de destination")
        return false
    end
    
    -- Vérifier que le fichier source existe
    local file = io.open(inputPath, "r")
    if not file then
        print("Erreur: Le fichier source n'existe pas:", inputPath)
        return false
    end
    file:close()
    
    -- Essayer différentes variantes de la commande unzip
    local commands = {
        string.format('unzip -o -q "%s" -d "%s" 2>/dev/null', inputPath, extractPath),
        string.format('unzip -o "%s" -d "%s" 2>/dev/null', inputPath, extractPath),
        string.format('cd "%s" && unzip -o "%s" 2>/dev/null', extractPath, inputPath),
        string.format('7z x "%s" -o"%s" -y 2>/dev/null', inputPath, extractPath), -- Support 7zip
    }
    
    for i, cmd in ipairs(commands) do
        print("Essai commande " .. i .. ":", cmd)
        local result = os.execute(cmd)
        print("Résultat:", result)
        if result == 0 or result == true then
            -- Vérifier que l'extraction a bien fonctionné
            local checkCmd = string.format('ls "%s" 2>/dev/null | wc -l', extractPath)
            local handle = io.popen(checkCmd)
            local fileCount = tonumber(handle:read("*a"))
            handle:close()
            
            if fileCount and fileCount > 0 then
                print("Extraction réussie, " .. fileCount .. " fichiers extraits")
                return true
            end
        end
    end
    
    print("Erreur: Toutes les méthodes d'extraction ont échoué")
    return false
end

-- Fonction pour créer une archive ZIP (version améliorée)
local function createZip(outputPath, sourceDir)
    print("Création de l'archive:", outputPath, "depuis:", sourceDir)
    
    -- Vérifier que le dossier source existe et contient des fichiers
    local checkCmd = string.format('find "%s" -type f 2>/dev/null | wc -l', sourceDir)
    local handle = io.popen(checkCmd)
    local fileCount = tonumber(handle:read("*a"))
    handle:close()
    
    if not fileCount or fileCount == 0 then
        print("Erreur: Aucun fichier trouvé dans le dossier source")
        return false
    end
    
    print("Fichiers à archiver:", fileCount)
    
    -- Supprimer le fichier de sortie s'il existe déjà
    os.remove(outputPath)
    
    -- Essayer différentes méthodes de création d'archive
    local commands = {
        string.format('cd "%s" && zip -r "%s" . 2>/dev/null', sourceDir, outputPath),
        string.format('cd "%s" && zip -9 -r "%s" * 2>/dev/null', sourceDir, outputPath),
        string.format('7z a "%s" "%s/*" 2>/dev/null', outputPath, sourceDir), -- Support 7zip
    }
    
    for i, cmd in ipairs(commands) do
        print("Essai création archive " .. i .. ":", cmd)
        local result = os.execute(cmd)
        print("Résultat:", result)
        
        if result == 0 or result == true then
            -- Vérifier que l'archive a été créée
            local file = io.open(outputPath, "r")
            if file then
                local size = file:seek("end")
                file:close()
                if size > 0 then
                    print("Archive créée avec succès, taille:", size, "octets")
                    return true
                end
            end
        end
    end
    
    print("Erreur: Toutes les méthodes de création d'archive ont échoué")
    return false
end

-- Fonction pour extraire les archives RAR
local function extractRar(inputPath, extractPath)
    print("Extraction RAR de:", inputPath, "vers:", extractPath)
    
    if not createDirectory(extractPath) then
        print("Erreur: Impossible de créer le dossier de destination")
        return false
    end
    
    local commands = {
        string.format('unrar x "%s" "%s/" 2>/dev/null', inputPath, extractPath),
        string.format('7z x "%s" -o"%s" -y 2>/dev/null', inputPath, extractPath),
    }
    
    for i, cmd in ipairs(commands) do
        print("Essai extraction RAR " .. i .. ":", cmd)
        local result = os.execute(cmd)
        if result == 0 or result == true then
            return true
        end
    end
    
    return false
end

-- Fonction pour créer une archive RAR
local function createRar(outputPath, sourceDir)
    print("Création RAR:", outputPath, "depuis:", sourceDir)
    
    -- Supprimer le fichier de sortie s'il existe déjà
    os.remove(outputPath)
    
    local commands = {
        string.format('cd "%s" && rar a "%s" * 2>/dev/null', sourceDir, outputPath),
        string.format('cd "%s" && rar a -ep1 "%s" * 2>/dev/null', sourceDir, outputPath),
    }
    
    for i, cmd in ipairs(commands) do
        print("Essai création RAR " .. i .. ":", cmd)
        local result = os.execute(cmd)
        if result == 0 or result == true then
            local file = io.open(outputPath, "r")
            if file then
                file:close()
                return true
            end
        end
    end
    
    return false
end

-- Fonction pour lire un fichier
local function readFile(path)
    local file = io.open(path, "r")
    if not file then 
        print("Erreur: Impossible de lire le fichier:", path)
        return nil 
    end
    local content = file:read("*all")
    file:close()
    return content
end

-- Fonction pour écrire un fichier
local function writeFile(path, content)
    -- Créer le dossier parent si nécessaire
    local dir = path:match("(.+)[/\\][^/\\]*$")
    if dir then
        createDirectory(dir)
    end
    
    local file = io.open(path, "w")
    if not file then 
        print("Erreur: Impossible d'écrire le fichier:", path)
        return false 
    end
    file:write(content)
    file:close()
    return true
end

-- Fonction pour parcourir les fichiers d'un dossier
local function walkDirectory(dir, callback)
    local handle = io.popen(string.format('find "%s" -type f 2>/dev/null', dir))
    if not handle then 
        print("Erreur: Impossible de lister les fichiers du dossier:", dir)
        return 
    end
    
    for file in handle:lines() do
        if file and file ~= "" then
            callback(file)
        end
    end
    handle:close()
end

-- Fonction pour parser escrow_ignore du fxmanifest.lua
local function parseEscrowIgnore(manifestContent)
    local escrowIgnore = {}
    local escrowMatch = manifestContent:match("escrow_ignore%s*{([^}]*)}")
    
    if escrowMatch then
        for filename in escrowMatch:gmatch('["\']([^"\']+)["\']') do
            escrowIgnore[filename] = true
        end
        -- Support pour les fichiers sans quotes
        for filename in escrowMatch:gmatch('([%w_%.%-]+)') do
            if not filename:match('["{}\',]') then
                escrowIgnore[filename] = true
            end
        end
    end
    
    return escrowIgnore
end

-- Fonction pour ajouter le watermark automatiquement
local function addWatermark(code)
    local watermark = '--[Obfuscated by FSProtect v1.0 | discord.gg/fsprotect]\n'
    -- Vérifier si le watermark n'est pas déjà présent
    if not code:find('FSProtect v1%.0') then
        return watermark .. code
    end
    return code
end

-- Fonction principale pour traiter les archives
local function processArchive(inputPath, outputPath, preset)
    local extension = getFileExtension(inputPath):lower()
    
    if extension ~= ".zip" and extension ~= ".rar" then
        print("Erreur: Format d'archive non supporté. Utilisez .zip ou .rar")
        return false
    end
    
    -- Créer des dossiers temporaires avec des noms uniques
    local tempExtract = "/tmp/prometheus_extract_" .. os.time() .. "_" .. math.random(1000, 9999)
    local tempOutput = "/tmp/prometheus_output_" .. os.time() .. "_" .. math.random(1000, 9999)
    
    print("Dossier d'extraction temporaire:", tempExtract)
    print("Dossier de sortie temporaire:", tempOutput)
    
    -- Nettoyer les dossiers temporaires s'ils existent déjà
    removeDirectory(tempExtract)
    removeDirectory(tempOutput)
    
    if not createDirectory(tempExtract) then
        print("Erreur: Impossible de créer le dossier d'extraction")
        return false
    end
    
    if not createDirectory(tempOutput) then
        print("Erreur: Impossible de créer le dossier de sortie")
        removeDirectory(tempExtract)
        return false
    end
    
    -- Extraire l'archive
    local extractSuccess = false
    if extension == ".zip" then
        extractSuccess = extractZip(inputPath, tempExtract)
    elseif extension == ".rar" then
        extractSuccess = extractRar(inputPath, tempExtract)
    end
    
    if not extractSuccess then
        print("Erreur: Impossible d'extraire l'archive")
        removeDirectory(tempExtract)
        removeDirectory(tempOutput)
        return false
    end
    
    print("Extraction réussie! Contenu du dossier:")
    os.execute("find " .. tempExtract .. " -type f")
    
    -- Chercher fxmanifest.lua et parser escrow_ignore
    local escrowIgnore = {}
    local manifestPath = nil
    
    walkDirectory(tempExtract, function(file)
        local filename = file:match("([^/]+)$")
        if filename == "fxmanifest.lua" then
            manifestPath = file
            local manifestContent = readFile(file)
            if manifestContent then
                escrowIgnore = parseEscrowIgnore(manifestContent)
                print("Fichiers ignorés trouvés dans fxmanifest.lua:")
                for k, _ in pairs(escrowIgnore) do
                    print("  - " .. k)
                end
            end
        end
    end)
    
    -- Obfusquer les fichiers .lua
    local processedFiles = 0
    walkDirectory(tempExtract, function(file)
        local filename = file:match("([^/]+)$")
        local relativePath = file:gsub(tempExtract .. "/", "")
        local outputFile = tempOutput .. "/" .. relativePath
        
        -- Créer les dossiers de destination
        local outputDir = outputFile:match("(.+)/[^/]+$")
        if outputDir then
            createDirectory(outputDir)
        end
        
        if getFileExtension(filename):lower() == ".lua" then
            -- Ne pas obfusquer fxmanifest.lua et les fichiers dans escrow_ignore
            if filename == "fxmanifest.lua" or escrowIgnore[filename] then
                print("Ignoré: " .. filename)
                -- Copier le fichier sans modification
                local content = readFile(file)
                if content then
                    writeFile(outputFile, content)
                end
            else
                print("Obfuscation: " .. filename)
                -- Obfusquer le fichier
                local content = readFile(file)
                if content then
                    local success, obfuscated = pcall(function()
                        -- Utiliser Prometheus pour obfusquer
                        local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
                        return pipeline:apply(content, filename)
                    end)
                    
                    if success then
                        -- Ajouter le watermark automatiquement
                        obfuscated = addWatermark(obfuscated)
                        if writeFile(outputFile, obfuscated) then
                            processedFiles = processedFiles + 1
                        else
                            print("Erreur: Impossible d'écrire le fichier obfusqué:", outputFile)
                        end
                    else
                        print("Erreur lors de l'obfuscation de " .. filename .. ": " .. tostring(obfuscated))
                        -- Copier le fichier original en cas d'erreur
                        local content = readFile(file)
                        if content then
                            writeFile(outputFile, content)
                        end
                    end
                else
                    print("Erreur: Impossible de lire " .. file)
                end
            end
        else
            -- Copier les autres fichiers sans modification
            print("Copie: " .. filename)
            local content = readFile(file)
            if content then
                writeFile(outputFile, content)
            end
        end
    end)
    
    print("Création de l'archive de sortie...")
    
    -- Créer la nouvelle archive
    local createSuccess = false
    if extension == ".zip" then
        createSuccess = createZip(outputPath, tempOutput)
    elseif extension == ".rar" then
        createSuccess = createRar(outputPath, tempOutput)
    end
    
    -- Nettoyer les dossiers temporaires
    print("Nettoyage des dossiers temporaires...")
    removeDirectory(tempExtract)
    removeDirectory(tempOutput)
    
    if createSuccess then
        print(string.format("Archive traitée avec succès! %d fichiers obfusqués.", processedFiles))
        
        -- Vérification finale que le fichier existe
        local file = io.open(outputPath, "r")
        if file then
            local size = file:seek("end")
            file:close()
            print("Fichier de sortie créé, taille:", size, "octets")
            print("Fichier de sortie:", outputPath)
            return true
        else
            print("Erreur: Le fichier de sortie n'a pas été créé correctement")
            return false
        end
    else
        print("Erreur: Impossible de créer l'archive de sortie")
        return false
    end
end

-- Parser les arguments de ligne de commande pour les archives
local function parseArgs()
    local inputFile = nil
    local outputFile = nil
    local preset = "Strong"
    local isArchive = false
    
    for i = 1, #arg do
        if arg[i] == "--preset" and arg[i + 1] then
            preset = arg[i + 1]
        elseif arg[i] == "--input" and arg[i + 1] then
            inputFile = arg[i + 1]
            local ext = getFileExtension(inputFile):lower()
            if ext == ".zip" or ext == ".rar" then
                isArchive = true
            end
        elseif arg[i] == "--output" and arg[i + 1] then
            outputFile = arg[i + 1]
        elseif not inputFile and arg[i]:match("%.") then
            inputFile = arg[i]
            local ext = getFileExtension(inputFile):lower()
            if ext == ".zip" or ext == ".rar" then
                isArchive = true
            end
        elseif not outputFile and isArchive and arg[i]:match("%.") then
            outputFile = arg[i]
        end
    end
    
    return inputFile, outputFile, preset, isArchive
end

-- Logique principale
local inputFile, outputFile, preset, isArchive = parseArgs()

print("Arguments analysés:")
print("  Input:", inputFile or "non spécifié")
print("  Output:", outputFile or "non spécifié")
print("  Preset:", preset)
print("  Is Archive:", isArchive)

if isArchive and inputFile and outputFile then
    -- Traitement des archives
    print("Mode archive détecté")
    print("Fichier d'entrée: " .. inputFile)
    print("Fichier de sortie: " .. outputFile)
    print("Preset: " .. preset)
    
    local success = processArchive(inputFile, outputFile, preset)
    if not success then
        print("ERREUR: Le traitement de l'archive a échoué")
        os.exit(1)
    else
        print("SUCCESS: Archive traitée avec succès")
    end
else
    -- Traitement normal des fichiers .lua individuels avec watermark automatique
    if inputFile and getFileExtension(inputFile):lower() == ".lua" then
        local content = readFile(inputFile)
        if content then
            local success, obfuscated = pcall(function()
                local pipeline = Prometheus.Pipeline:fromConfig(Prometheus.Presets[preset] or Prometheus.Presets.Strong)
                return pipeline:apply(content, inputFile)
            end)
            
            if success then
                -- Ajouter le watermark automatiquement
                obfuscated = addWatermark(obfuscated)
                
                local outputFileName = outputFile or (inputFile:gsub("%.lua$", "_obfuscated.lua"))
                local writeSuccess = writeFile(outputFileName, obfuscated)
                if writeSuccess then
                    print("Fichier obfusqué: " .. outputFileName)
                else
                    print("Erreur: Impossible d'écrire le fichier de sortie: " .. outputFileName)
                    os.exit(1)
                end
            else
                print("Erreur lors de l'obfuscation: " .. tostring(obfuscated))
                os.exit(1)
            end
        else
            print("Erreur: Impossible de lire le fichier d'entrée: " .. inputFile)
            os.exit(1)
        end
    else
        print("Erreur: Fichier d'entrée non spécifié ou non valide")
        print("Usage: lua prometheus-main.lua <input.lua> [output.lua] [--preset <preset>]")
        print("   ou: lua prometheus-main.lua <input.zip/rar> <output.zip/rar> [--preset <preset>]")
        os.exit(1)
    end
end