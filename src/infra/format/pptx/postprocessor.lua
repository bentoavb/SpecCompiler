---PPTX package postprocessing framework.
---Provides model hooks over slide/master/layout/theme XML parts without
---requiring every model to implement ZIP extraction and repacking.
---@module infra.format.pptx.postprocessor

local zip_utils = require("infra.format.zip_utils")
local uv = require("luv")

local M = {}

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content)
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

local function call_hook(hooks, name, content, config, log, part_path)
    if not hooks or type(hooks[name]) ~= "function" then return content end
    local result = hooks[name](content, config, log, part_path)
    return result or content
end

local function apply_package_hooks(extract_dir, config, log, hooks)
    local ppt_dir = extract_dir .. "/ppt"
    local folders = {
        {name = "slides", hook = "process_slide"},
        {name = "slideLayouts", hook = "process_layout"},
        {name = "slideMasters", hook = "process_master"},
        {name = "theme", hook = "process_theme"},
    }

    for _, folder in ipairs(folders) do
        local dir = ppt_dir .. "/" .. folder.name
        local request = uv.fs_scandir(dir)
        if request then
            while true do
                local name, kind = uv.fs_scandir_next(request)
                if not name then break end
                if kind == "file" and name:match("%.xml$") then
                    local part_path = "ppt/" .. folder.name .. "/" .. name
                    local full_path = dir .. "/" .. name
                    local content = read_file(full_path)
                    if content then
                        content = call_hook(hooks, folder.hook, content, config, log, part_path)
                        content = call_hook(hooks, "process_part", content, config, log, part_path)
                        if not write_file(full_path, content) then
                            return false, "Failed to write PPTX package part: " .. part_path
                        end
                    end
                end
            end
        end
    end

    if hooks and type(hooks.process_package) == "function" then
        local ok, err = hooks.process_package(extract_dir, config, log)
        if ok == false then
            return false, err or "PPTX package hook failed"
        end
    end
    return true
end

---Postprocess one generated PPTX archive with optional model hooks.
---@param path string PPTX output path
---@param config table Project configuration
---@param log table Logger
---@param hooks table|nil Model hooks (process_slide, process_layout, process_master, process_theme, process_part)
---@return boolean success
---@return string|nil error
function M.process(path, config, log, hooks)
    local absolute_path = path
    if path:sub(1, 1) ~= "/" then
        absolute_path = (zip_utils.cwd() or ".") .. "/" .. path
    end
    local temp_dir = zip_utils.temp_path("_pptx_post")
    local extract_ok, extract_err = zip_utils.extract(absolute_path, temp_dir)
    if not extract_ok then
        return false, "Failed to extract PPTX: " .. tostring(extract_err)
    end

    local apply_ok, apply_err = apply_package_hooks(temp_dir, config, log, hooks)
    if not apply_ok then
        zip_utils.rmdir_r(temp_dir)
        return false, apply_err
    end

    local create_ok, create_err = zip_utils.create(temp_dir, absolute_path)
    zip_utils.rmdir_r(temp_dir)
    if not create_ok then
        return false, "Failed to repack PPTX: " .. tostring(create_err)
    end
    return true
end

---Finalize all generated files, matching the DOCX/LaTeX postprocessor contract.
---@param paths string[] Generated PPTX files
---@param config table Project configuration
---@param log table Logger
---@param hooks table|nil Model hooks
function M.finalize(paths, config, log, hooks)
    for _, path in ipairs(paths or {}) do
        local ok, err = M.process(path, config, log, hooks)
        if not ok then error(err or ("PPTX postprocessing failed: " .. path)) end
    end
end

return M
