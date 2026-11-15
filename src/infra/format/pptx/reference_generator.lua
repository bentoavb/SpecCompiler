---Generate a Pandoc reference.pptx from a model-owned reference and style preset.
---PPTX customization is expressed as theme and slide-layout data; the reference
---deck remains the source of masters/layouts rather than being patched by a
---standalone, manually-run script.
---@module infra.format.pptx.reference_generator

local preset_loader = require("infra.format.pptx.preset_loader")
local zip_utils = require("infra.format.zip_utils")
local xml = require("infra.format.xml")
local uv = require("luv")

local M = {}

local function read_file(path, mode)
    local file = io.open(path, mode or "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content, mode)
    local file = io.open(path, mode or "wb")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

local function set_transform(shape, rect)
    if not rect then return end
    local properties = xml.find_child(shape, "p:spPr")
    if not properties then
        properties = xml.node("p:spPr")
        xml.add_child(shape, properties)
    end
    local transform = xml.find_child(properties, "a:xfrm")
    if not transform then
        transform = xml.node("a:xfrm")
        xml.add_child(properties, transform)
    end
    local offset = xml.find_child(transform, "a:off")
    if not offset then
        offset = xml.node("a:off")
        xml.add_child(transform, offset)
    end
    local extent = xml.find_child(transform, "a:ext")
    if not extent then
        extent = xml.node("a:ext")
        xml.add_child(transform, extent)
    end
    for key, value in pairs({x = rect.x, y = rect.y}) do
        if value ~= nil then xml.set_attr(offset, key, tostring(value)) end
    end
    for key, value in pairs({cx = rect.cx, cy = rect.cy}) do
        if value ~= nil then xml.set_attr(extent, key, tostring(value)) end
    end
end

local function get_placeholder(shape)
    local non_visual = xml.find_child(shape, "p:nvSpPr")
    local properties = non_visual and xml.find_child(non_visual, "p:nvPr")
    return properties and xml.find_child(properties, "p:ph") or nil
end

local function patch_body_text_style(shape, body_style)
    local tx_body = xml.find_child(shape, "p:txBody")
    local list_style = tx_body and xml.find_child(tx_body, "a:lstStyle")
    if not list_style then return end

    local bullet_chars = {"•", "–", "•", "–", "»", "•", "•", "•", "•"}
    for _, level in ipairs(list_style.kids or {}) do
        local number = level.type == "element" and tonumber(level.name:match("^lvl(%d+)pPr$"))
        if number then
            -- Place the glyph in the hanging indent and start text farther
            -- right. The Pandoc two-column layout sets both values to zero,
            -- which makes the bullet touch the first character.
            xml.set_attr(level, "marL", tostring(number * 342900))
            xml.set_attr(level, "indent", "-228600")
            local no_bullet = xml.find_child(level, "a:buNone")
            if no_bullet then xml.remove_child(level, no_bullet) end
            if not xml.find_child(level, "a:buChar") and not xml.find_child(level, "a:buAutoNum") then
                local def = xml.find_child(level, "a:defRPr")
                local bullet = xml.node("a:buChar", {char = bullet_chars[number] or "•"})
                if def then
                    local position = #level.kids
                    for i, child in ipairs(level.kids) do
                        if child == def then position = i; break end
                    end
                    xml.insert_child(level, bullet, position)
                else
                    xml.add_child(level, bullet)
                end
            end
            local run_style = xml.find_child(level, "a:defRPr")
            if run_style and body_style and body_style.font_size then
                xml.set_attr(run_style, "sz", tostring(body_style.font_size))
            end
        end
    end
end

local function patch_content_layout(layout_path, layout, body_style, log)
    if not layout then return false end
    local content = read_file(layout_path)
    if not content then return false end
    local doc = xml.parse(content)
    if not doc or not doc.root then return false end
    local tree = xml.find_by_name(doc.root, "p:spTree")[1]
    if not tree then return false end

    local found = {title = false, body = false, visual = false}
    for _, shape in ipairs(xml.find_children(tree, "p:sp")) do
        local placeholder = get_placeholder(shape)
        if placeholder then
            local kind = xml.get_attr(placeholder, "type")
            local index = xml.get_attr(placeholder, "idx")
            if kind == "title" and layout.title then
                set_transform(shape, layout.title)
                found.title = true
            elseif kind == "body" and index == tostring(layout.body_index or 2) and layout.body then
                set_transform(shape, layout.body)
                patch_body_text_style(shape, body_style)
                found.body = true
            elseif index == tostring(layout.visual_index or 1) and layout.visual then
                set_transform(shape, layout.visual)
                found.visual = true
            end
        end
    end

    if not found.title or not found.body or not found.visual then
        return false
    end
    local file_ok = write_file(layout_path, xml.serialize(doc))
    if file_ok and log then
        log(string.format("  Applied content layout overrides to %s", layout_path))
    end
    return file_ok
end

local function patch_theme(theme_path, theme, log)
    if not theme then return true end
    local content = read_file(theme_path)
    if not content then return true end
    local doc = xml.parse(content)
    if not doc or not doc.root then return false end
    local elements = xml.find_by_name(doc.root, "a:themeElements")[1]
    if not elements then return false end

    for slot, hex in pairs(theme.colors or {}) do
        local scheme = xml.find_child(elements, "a:clrScheme")
        local color = scheme and xml.find_child(scheme, "a:" .. slot)
        if color then
            color.kids = {}
            xml.add_child(color, xml.node("a:srgbClr", {val = hex}))
        end
    end

    local scheme = xml.find_child(elements, "a:fontScheme")
    for slot, font in pairs(theme.fonts or {}) do
        local font_group = scheme and xml.find_child(scheme, "a:" .. slot)
        local latin = font_group and xml.find_child(font_group, "a:latin")
        if latin then xml.set_attr(latin, "typeface", font) end
    end

    local ok = write_file(theme_path, xml.serialize(doc))
    if ok and log then log(string.format("  Applied theme overrides to %s", theme_path)) end
    return ok
end

local function patch_master(master_path, body, log)
    if not body then return true end
    local content = read_file(master_path)
    if not content then return true end
    local doc = xml.parse(content)
    if not doc or not doc.root then return false end
    local body_style = xml.find_by_name(doc.root, "p:bodyStyle")[1]
    if not body_style then return true end

    for _, level in ipairs(xml.find_by_name(body_style, "a:lvl1pPr")) do
        -- The body style must keep the authored bullet definition while using
        -- compact paragraph spacing appropriate for presentation slides.
        local before = xml.find_child(level, "a:spcBef")
        if before and body.space_before_pct ~= nil then
            xml.remove_child(level, before)
        end
        local run_style = xml.find_child(level, "a:defRPr")
        if run_style and body.font_size then
            xml.set_attr(run_style, "sz", tostring(body.font_size))
        end
    end

    local ok = write_file(master_path, xml.serialize(doc))
    if ok and log then log("  Applied body text style overrides to slide master") end
    return ok
end

local function apply_preset(extract_dir, preset, log)
    local pptx = preset.pptx or {}
    local theme_dir = extract_dir .. "/ppt/theme"
    local request = uv.fs_scandir(theme_dir)
    if request then
        while true do
            local name, kind = uv.fs_scandir_next(request)
            if not name then break end
            if kind == "file" and name:match("^theme%d+%.xml$") then
                local ok = patch_theme(theme_dir .. "/" .. name, pptx.theme, log)
                if not ok then return false, "Failed to update PPTX theme: " .. name end
            end
        end
    end

    local master_path = extract_dir .. "/ppt/slideMasters/slideMaster1.xml"
    local master_ok = patch_master(master_path, pptx.body, log)
    if not master_ok then return false, "Failed to update PPTX slide master" end

    local layout = pptx.content_layout
    if layout then
        local layout_dir = extract_dir .. "/ppt/slideLayouts"
        local layouts = uv.fs_scandir(layout_dir)
        local patched = false
        if layouts then
            while true do
                local name, kind = uv.fs_scandir_next(layouts)
                if not name then break end
                if kind == "file" and name:match("^slideLayout%d+%.xml$") then
                    if patch_content_layout(layout_dir .. "/" .. name, layout, pptx.body, log) then
                        patched = true
                    end
                end
            end
        end
        if not patched then
            return false, "No PPTX layout with title, body, and visual placeholders matched the preset"
        end
    end
    return true
end

local function resolve_base_reference(speccompiler_home, template, preset)
    local declared = preset.reference_doc
    if not declared then return nil end
    if declared:match("^/") then return declared end
    local path = string.format("%s/models/%s/%s", speccompiler_home, template, declared)
    local file = io.open(path, "rb")
    if file then
        file:close()
        return path
    end
    return nil
end

---Generate a reference deck using a resolved PPTX preset.
---@param options table {speccompiler_home, template, preset_name, output_path, log}
---@return boolean success
---@return string|nil error
function M.generate(options)
    local preset, preset_err = preset_loader.load_with_extends(
        options.speccompiler_home, options.template, options.preset_name)
    if not preset then return false, preset_err end

    local base_path = resolve_base_reference(options.speccompiler_home, options.template, preset)
    local temp_dir = zip_utils.temp_path("_pptx_ref")
    local source_path = base_path
    if not source_path then
        local ok, data = pcall(pandoc.pipe, "pandoc", {"--print-default-data-file", "reference.pptx"}, "")
        if not ok or not data or #data == 0 then
            return false, "Could not get Pandoc's default reference.pptx"
        end
        source_path = temp_dir .. "/pandoc-reference.pptx"
        local mkdir_ok, mkdir_err = zip_utils.mkdir_p(temp_dir)
        if not mkdir_ok then return false, mkdir_err end
        if not write_file(source_path, data) then
            zip_utils.rmdir_r(temp_dir)
            return false, "Could not write temporary Pandoc reference.pptx"
        end
    end

    local extract_dir = temp_dir .. "/reference"
    local extract_ok, extract_err = zip_utils.extract(source_path, extract_dir)
    if not extract_ok then
        zip_utils.rmdir_r(temp_dir)
        return false, "Could not extract reference.pptx: " .. tostring(extract_err)
    end

    local apply_ok, apply_err = apply_preset(extract_dir, preset, options.log)
    if not apply_ok then
        zip_utils.rmdir_r(temp_dir)
        return false, apply_err
    end

    local output_dir = options.output_path:match("^(.+)/[^/]+$")
    if output_dir then
        local mkdir_ok, mkdir_err = zip_utils.mkdir_p(output_dir)
        if not mkdir_ok then
            zip_utils.rmdir_r(temp_dir)
            return false, mkdir_err
        end
    end

    local cwd = zip_utils.cwd() or "."
    local output_path = options.output_path
    if output_path:sub(1, 1) ~= "/" then output_path = cwd .. "/" .. output_path end
    local create_ok, create_err = zip_utils.create(extract_dir, output_path)
    zip_utils.rmdir_r(temp_dir)
    if not create_ok then return false, "Could not write reference.pptx: " .. tostring(create_err) end
    return true
end

return M
