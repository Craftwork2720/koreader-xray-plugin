-- LookupManager - Core logic for text selection lookups
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local LookupManager = {}

function LookupManager:new(plugin)
    local o = {
        plugin = plugin
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Clean and normalize text for comparison
function LookupManager:normalize(text)
    if type(text) ~= "string" or text == "" then return "" end
    -- Remove non-alphanumeric characters from start/end and lowercase
    local clean = text:gsub("^[^%w]+", ""):gsub("[^%w]+$", ""):lower()
    return clean
end

-- Normalize text by replacing diacritics with base ASCII characters.
-- e.g. "białej" → "bialej", "przystań" → "przystan"
local function strip_diacritics(text)
    if type(text) ~= "string" or text == "" then return "" end
    local result = text
        :gsub("ą", "a"):gsub("ć", "c"):gsub("ę", "e")
        :gsub("ł", "l"):gsub("ń", "n"):gsub("ó", "o")
        :gsub("ś", "s"):gsub("ź", "z"):gsub("ż", "z")
        :gsub("Ą", "A"):gsub("Ć", "C"):gsub("Ę", "E")
        :gsub("Ł", "L"):gsub("Ń", "N"):gsub("Ó", "O")
        :gsub("Ś", "S"):gsub("Ź", "Z"):gsub("Ż", "Z")
    return result
end

-- Check if two tokens (words) are likely the same word with different
-- inflectional endings. Uses prefix overlap ratio.
-- Returns true if the shorter token shares >= 70% of its length as a prefix
-- with the longer token.
local function tokens_fuzzy_match(t1, t2)
    if t1 == t2 then return true end
    local len1, len2 = #t1, #t2
    local shorter, longer = t1, t2
    if len1 > len2 then shorter, longer = t2, t1 end
    if #shorter < 3 then return false end  -- too short to meaningfully compare
    -- Find common prefix length
    local prefix_len = 0
    for i = 1, #shorter do
        if shorter:byte(i) == longer:byte(i) then
            prefix_len = prefix_len + 1
        else
            break
        end
    end
    if prefix_len == 0 then return false end
    -- Require at least 70% of the shorter token to be a prefix of the longer
    return prefix_len >= math.ceil(#shorter * 0.7)
end

-- Fuzzy token-based match: split both the query and the name into
-- space-separated tokens, strip diacritics, and check if every query
-- token has a corresponding matching token in the name.
-- e.g. query "bialej przystani" matches name "biala przystan"
--      because "bialej" ≈ "biala" and "przystani" has "przystan" as prefix
local function token_fuzzy_match(query_no_diac, name_no_diac)
    if not query_no_diac or not name_no_diac then return false end
    if query_no_diac == "" or name_no_diac == "" then return false end
    local q_tokens = {}
    for token in query_no_diac:gmatch("%S+") do
        table.insert(q_tokens, token)
    end
    if #q_tokens == 0 then return false end

    local n_tokens = {}
    for token in name_no_diac:gmatch("%S+") do
        table.insert(n_tokens, token)
    end
    if #n_tokens == 0 then return false end

    -- For each query token, find a matching name token
    for _, qt in ipairs(q_tokens) do
        local matched = false
        for _, nt in ipairs(n_tokens) do
            if tokens_fuzzy_match(qt, nt) then
                matched = true
                break
            end
        end
        if not matched then
            return false  -- a query token has no counterpart in the name
        end
    end
    return true
end

-- Collect all matches from a category list using a test function.
-- Returns a list of {item, type} tables. Skips items already seen (by name).
local function collectMatches(categories, seen, testFn)
    local results = {}
    for _, cat in ipairs(categories) do
        if cat.list then
            for _, item in ipairs(cat.list) do
                if item.name then
                    local norm = item.name:lower()
                    if not seen[norm] and testFn(item.name, cat) then
                        seen[norm] = true
                        table.insert(results, { item = item, item_type = cat.type })
                    end
                end
            end
        end
    end
    return results
end

-- Perform a robust lookup and return ALL matching candidates, prioritised by
-- pass quality (exact → contains query → query contained in name → keyword).
-- Returns a list of {item, item_type}, which may be empty.
function LookupManager:lookupAll(text)
    if not text or text == "" then return {} end
    local query = self:normalize(text)
    if #query < 2 then return {} end

    local categories = {
        { list = self.plugin.characters,        type = "character"  },
        { list = self.plugin.historical_figures, type = "historical" },
        { list = self.plugin.locations,         type = "location"   },
        { list = self.plugin.terms,             type = "term"       },
    }

    local seen = {}  -- tracks already-added names across passes

    -- Pass 1: Exact match (using cached normalized names if available)
    local results = collectMatches(categories, seen, function(name, cat_item)
        local item = cat_item -- the specific item from the list
        -- Note: collectMatches passes (item.name, cat) where cat is {list, type}
        -- Wait, collectMatches implementation is: testFn(item.name, cat)
        -- I need the item itself to check _norm_name.
        -- Let's check collectMatches again.
        return nil -- dummy
    end)
    -- Actually, let's just rewrite the passes for performance
    
    local final_results = {}
    
    -- Prepare diacritic-free versions for fuzzy matching
    local query_no_diac = strip_diacritics(query)
    
    local function addIfMatch(item, item_type, score)
        local n = (item.name or ""):lower()
        if seen[n] then return end
        
        local norm = item._norm_name or self:normalize(item.name)
        
        -- Exact
        if norm == query then
            seen[n] = true
            table.insert(final_results, { item = item, item_type = item_type, score = 100 })
            return
        end
        
        -- Aliases Exact
        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
                if anorm == query then
                    seen[n] = true
                    table.insert(final_results, { item = item, item_type = item_type, score = 95 })
                    return
                end
            end
        end
        
        -- Contains / Contained (Pass 2 & 3 combined)
        local function checkContains(text_norm)
            if not text_norm or #text_norm < 2 then return false end
            return query:find(text_norm, 1, true) or text_norm:find(query, 1, true)
        end

        if checkContains(norm) then
            seen[n] = true
            table.insert(final_results, { item = item, item_type = item_type, score = 50 })
            return
        end

        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
                if checkContains(anorm) then
                    seen[n] = true
                    table.insert(final_results, { item = item, item_type = item_type, score = 40 })
                    return
                end
            end
        end
        
        -- Pass 4: Fuzzy token match (handles inflectional variants, e.g. Polish cases)
        -- Strip diacritics from name and do token-by-token fuzzy comparison
        local name_no_diac = strip_diacritics(norm)
        if token_fuzzy_match(query_no_diac, name_no_diac) then
            seen[n] = true
            table.insert(final_results, { item = item, item_type = item_type, score = 25 })
            return
        end
        
        -- Also check aliases with fuzzy token match
        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
                local alias_no_diac = strip_diacritics(anorm)
                if token_fuzzy_match(query_no_diac, alias_no_diac) then
                    seen[n] = true
                    table.insert(final_results, { item = item, item_type = item_type, score = 20 })
                    return
                end
            end
        end
    end

    for _, cat in ipairs(categories) do
        if cat.list then
            for _, item in ipairs(cat.list) do
                addIfMatch(item, cat.type)
            end
        end
    end
    
    if #final_results > 0 then
        table.sort(final_results, function(a, b) return a.score > b.score end)
    end

    return final_results
end

-- Convenience single-result wrapper used by callers that don't need disambiguation
function LookupManager:lookup(text)
    local all = self:lookupAll(text)
    if #all == 0 then return nil, nil end
    return all[1].item, all[1].item_type
end

-- Dispatch a single result to the appropriate UI handler
function LookupManager:showResult(item, item_type)
    if item_type == "character" then
        self.plugin:showCharacterDetails(item)
    elseif item_type == "historical" or item_type == "historical_figure" then
        self.plugin:showHistoricalFigureDetails(item)
    elseif item_type == "location" then
        self.plugin:showLocationDetails(item)
    elseif item_type == "term" then
        self.plugin:showTermDetails(item)
    end
end

-- Handle the UI part of the lookup, with a disambiguation picker for multiple hits
function LookupManager:handleLookup(text, pos0, pos1)
    logger.info("XRayPlugin: handleLookup called for:", text)
    if type(text) ~= "string" or text == "" then return end

    local all = self:lookupAll(text)

    if #all == 1 then
        -- Unambiguous — show directly
        self:showResult(all[1].item, all[1].item_type)

    elseif #all > 1 then
        -- Multiple candidates — let the user pick
        local ButtonDialog = require("ui/widget/buttondialog")
        local prompt = self.plugin.loc:t("multiple_matches", text:sub(1, 30))
        local buttons = {}
        local dialog

        for _, candidate in ipairs(all) do
            local display_name = candidate.item.name or "???"
            -- Capture loop vars for the closure
            local captured_item = candidate.item
            local captured_type = candidate.item_type
            table.insert(buttons, {
                {
                    text = display_name,
                    callback = function()
                        UIManager:close(dialog)
                        self:showResult(captured_item, captured_type)
                    end,
                }
            })
        end

        -- Cancel row
        table.insert(buttons, {
            {
                text = self.plugin.loc:t("close") or "Close",
                callback = function()
                    UIManager:close(dialog)
                end,
            }
        })

        dialog = ButtonDialog:new{
            title = prompt,
            buttons = buttons,
        }
        UIManager:show(dialog)

    else
        -- No match found
        local ConfirmBox = require("ui/widget/confirmbox")
        local no_data_dialog
        
        local text_to_show = text:sub(1, 30)
        local prompt_text = self.plugin.loc:t("fetch_single_word_prompt", text_to_show)
        if not prompt_text or prompt_text == "fetch_single_word_prompt" then
            prompt_text = string.format("No X-Ray data found for '%s'. Would you like to look it up?", text_to_show)
        end
        
        no_data_dialog = ConfirmBox:new{
            text       = prompt_text,
            ok_text    = self.plugin.loc:t("fetch_button") or "Fetch",
            cancel_text = self.plugin.loc:t("close") or "Close",
            ok_callback = function()
                UIManager:close(no_data_dialog)
                self.plugin:fetchSingleWord(text, pos0, pos1)
            end,
            cancel_callback = function()
                UIManager:close(no_data_dialog)
            end,
        }
        UIManager:show(no_data_dialog)
    end
end

return LookupManager