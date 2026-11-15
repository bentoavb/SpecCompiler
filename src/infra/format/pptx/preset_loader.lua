---Preset loader for PPTX reference themes.
---Loads model-owned Lua style presets and resolves their extends chains.
---@module infra.format.pptx.preset_loader

local M = {}

local function read_preset(path)
    local chunk, load_err = loadfile(path)
    if not chunk then
        return nil, "Failed to load PPTX preset: " .. (load_err or path)
    end
    local ok, preset = pcall(chunk)
    if not ok then
        return nil, "Failed to execute PPTX preset: " .. tostring(preset)
    end
    if type(preset) ~= "table" then
        return nil, "PPTX preset must return a table: " .. path
    end
    return preset
end

function M.resolve_path(speccompiler_home, template, preset)
    local path = string.format("%s/models/%s/styles/%s/preset.lua",
        speccompiler_home, template, preset)
    local file = io.open(path, "r")
    if file then
        file:close()
        return path
    end
    return nil
end

local function merge(base, override)
    local result = {}
    for key, value in pairs(base or {}) do
        result[key] = type(value) == "table" and merge(value, {}) or value
    end
    for key, value in pairs(override or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = merge(result[key], value)
        else
            result[key] = value
        end
    end
    return result
end

function M.resolve_chain_paths(speccompiler_home, template, preset, visited)
    visited = visited or {}
    local key = template .. "/" .. preset
    if visited[key] then
        return nil, "Circular PPTX preset dependency detected: " .. key
    end
    visited[key] = true

    local path = M.resolve_path(speccompiler_home, template, preset)
    if not path then
        return nil, "PPTX preset not found: " .. key
    end
    local current, err = read_preset(path)
    if not current then
        return nil, err
    end

    local paths = { path }
    if current.extends then
        local base_paths, base_err = M.resolve_chain_paths(
            speccompiler_home,
            current.extends.template or template,
            current.extends.preset,
            visited
        )
        if not base_paths then
            return nil, base_err
        end
        for _, base_path in ipairs(base_paths) do
            paths[#paths + 1] = base_path
        end
    end
    return paths
end

function M.load_with_extends(speccompiler_home, template, preset, visited)
    visited = visited or {}
    local key = template .. "/" .. preset
    if visited[key] then
        return nil, "Circular PPTX preset dependency detected: " .. key
    end
    visited[key] = true

    local path = M.resolve_path(speccompiler_home, template, preset)
    if not path then
        return nil, "PPTX preset not found: " .. key
    end
    local current, err = read_preset(path)
    if not current then
        return nil, err
    end

    if current.extends then
        local base, base_err = M.load_with_extends(
            speccompiler_home,
            current.extends.template or template,
            current.extends.preset,
            visited
        )
        if not base then
            return nil, "Failed to load base PPTX preset: " .. tostring(base_err)
        end
        current = merge(base, current)
    end
    return current
end

return M
