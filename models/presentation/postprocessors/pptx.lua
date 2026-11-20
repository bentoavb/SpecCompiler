---PPTX postprocessor for the presentation model.
---Keeps mixed text-and-visual slides in a single vertical column by measuring
---text in the body placeholder and placing following tables/images below it.

local archive = require("infra.format.pptx.postprocessor")
local preset_loader = require("infra.format.pptx.preset_loader")
local xml = require("infra.format.xml")
local pandoc_cli = require("infra.process.pandoc_cli")
local slide_numbers = require("models.presentation.postprocessors.slide_numbers")
local slide_types = require("models.presentation.postprocessors.slide_types")
local footer = require("models.presentation.postprocessors.footer")
local pptx_pdf = require("models.presentation.postprocessors.pptx_pdf")
local figure_size = require("models.presentation.shared.figure_size")

local M = {}

local function placeholder(shape)
    local non_visual = xml.find_child(shape, "p:nvSpPr")
        or xml.find_child(shape, "p:nvGraphicFramePr")
    local properties = non_visual and xml.find_child(non_visual, "p:nvPr")
    return properties and xml.find_child(properties, "p:ph") or nil
end

local function text_content(node, result)
    result = result or {}
    if node.type == "text" then
        result[#result + 1] = node.value or ""
    else
        for _, child in ipairs(node.kids or {}) do
            text_content(child, result)
        end
    end
    return result
end

local function estimate_lines(body_shape, characters_per_line)
    local tx_body = xml.find_child(body_shape, "p:txBody")
    if not tx_body then return 0 end
    local line_count = 0
    for _, paragraph in ipairs(xml.find_children(tx_body, "a:p")) do
        local text = table.concat(text_content(paragraph))
        if text:match("%S") then
            line_count = line_count + math.max(1, math.ceil(#text / characters_per_line))
        end
    end
    return line_count
end

local function shape_properties(shape)
    return xml.find_child(shape, "p:spPr")
end

local function get_transform(shape, kind)
    local parent = kind == "graphicFrame" and shape or shape_properties(shape)
    return parent and xml.find_child(parent, kind == "graphicFrame" and "p:xfrm" or "a:xfrm")
end

local function set_transform(shape, kind, rect)
    local parent = kind == "graphicFrame" and shape or shape_properties(shape)
    if not parent then
        parent = xml.node("p:spPr")
        xml.add_child(shape, parent)
    end
    local transform = get_transform(shape, kind)
    if not transform then
        transform = xml.node(kind == "graphicFrame" and "p:xfrm" or "a:xfrm")
        xml.add_child(parent, transform)
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

local function shape_visual(shape)
    if shape.name == "pic" then return "pic" end
    if shape.name == "graphicFrame" then return "graphicFrame" end
    return nil
end

local function requested_size(shape, width_reference, height_reference)
    local properties = xml.find_child(shape, "p:nvPicPr")
    local non_visual = properties and xml.find_child(properties, "p:cNvPr")
    local description = non_visual and xml.get_attr(non_visual, "descr")
    if not description then return nil, nil end
    local width, height = description:match("%[%[speccompiler%-size:([^,]+),([^%]]+)%]%]")
    if not width then return nil, nil end
    xml.set_attr(non_visual, "descr",
        description:gsub("%[%[speccompiler%-size:[^%]]+%]%]%s*", "", 1))
    return figure_size.to_emu(width, width_reference), figure_size.to_emu(height, height_reference)
end

local function fit_dimensions(old_cx, old_cy, max_cx, max_cy, width, height)
    local scale = math.min(max_cx / old_cx, max_cy / old_cy)
    if width then scale = math.min(scale, width / old_cx) end
    if height then scale = math.min(scale, height / old_cy) end
    return math.max(1, math.floor(old_cx * scale)), math.max(1, math.floor(old_cy * scale))
end

local function fit_picture(shape, old_cx, old_cy, max_cx, max_cy, width_reference, height_reference)
    local width, height = requested_size(shape, width_reference, height_reference)
    return fit_dimensions(old_cx, old_cy, max_cx, max_cy, width, height)
end

local function ensure_child(parent, name, position)
    local child = xml.find_child(parent, name)
    if child then return child end
    child = xml.node(name)
    if position then xml.insert_child(parent, child, position) else xml.add_child(parent, child) end
    return child
end

local function style_title(shape, rect, style)
    set_transform(shape, "shape", rect)
    local tx_body = xml.find_child(shape, "p:txBody")
    if not tx_body then return end
    local body_properties = ensure_child(tx_body, "a:bodyPr", 1)
    xml.set_attr(body_properties, "anchor", "ctr")
    xml.set_attr(body_properties, "tIns", "0")
    xml.set_attr(body_properties, "bIns", "0")
    for _, paragraph in ipairs(xml.find_children(tx_body, "a:p")) do
        local ppr = ensure_child(paragraph, "a:pPr", 1)
        xml.set_attr(ppr, "algn", style.alignment or "ctr")
        for _, run in ipairs(xml.find_children(paragraph, "a:r")) do
            local rpr = ensure_child(run, "a:rPr", 1)
            xml.set_attr(rpr, "sz", tostring(style.font_size or 3000))
            if style.bold then
                xml.set_attr(rpr, "b", "1")
            end
            local fill = ensure_child(rpr, "a:solidFill")
            local color = ensure_child(fill, "a:srgbClr")
            xml.set_attr(color, "val", style.color or "000080")
        end
        local end_props = xml.find_child(paragraph, "a:endParaRPr")
        if end_props then xml.set_attr(end_props, "sz", tostring(style.font_size or 3000)) end
    end
end

local function style_cover_slide(shape, title_style, cover_style)
    local tx_body = xml.find_child(shape, "p:txBody")
    if not tx_body then return end
    local geometry = cover_style.geometry or {x = 760000, y = 1100000, cx = 7624000, cy = 2900000}
    set_transform(shape, "shape", geometry)

    for index, paragraph in ipairs(xml.find_children(tx_body, "a:p")) do
        local ppr = ensure_child(paragraph, "a:pPr", 1)
        xml.set_attr(ppr, "algn", "ctr")
        local is_title = index == 1
        if is_title then
            local spacing_after = ensure_child(ppr, "a:spcAft")
            xml.replace_child(spacing_after, "a:spcPts", xml.node("a:spcPts", {
                val = tostring(title_style.title_slide_gap_after or 3000),
            }))
        end
        for _, run in ipairs(xml.find_children(paragraph, "a:r")) do
            local rpr = ensure_child(run, "a:rPr", 1)
            local font_size = is_title and (cover_style.title_font_size or 4200)
                or (index == 2 and (cover_style.subtitle_font_size or 2100)
                    or (cover_style.metadata_font_size or 1500))
            xml.set_attr(rpr, "sz", tostring(font_size))
            if is_title then xml.set_attr(rpr, "b", "1") end
            if index == 2 then xml.set_attr(rpr, "i", "1") end
            local fill = ensure_child(rpr, "a:solidFill")
            local color = ensure_child(fill, "a:srgbClr")
            local hex = is_title and (cover_style.title_color or title_style.color or "000080")
                or (index == 2 and (cover_style.subtitle_color or "334155")
                    or (cover_style.metadata_color or "475569"))
            xml.set_attr(color, "val", hex)
        end
    end
end

local function style_body_text(shape, body_style)
    local tx_body = xml.find_child(shape, "p:txBody")
    if not tx_body then return end
    local font_size = body_style.font_size or 1900
    for _, paragraph in ipairs(xml.find_children(tx_body, "a:p")) do
        for _, run in ipairs(xml.find_children(paragraph, "a:r")) do
            local run_props = ensure_child(run, "a:rPr", 1)
            xml.set_attr(run_props, "sz", tostring(font_size))
            if body_style.color then
                local fill = ensure_child(run_props, "a:solidFill")
                local color = ensure_child(fill, "a:srgbClr")
                xml.set_attr(color, "val", body_style.color)
            end
        end
    end
end

local function shape_title(shape)
    local ph = placeholder(shape)
    local kind = ph and xml.get_attr(ph, "type")
    return kind == "title" or kind == "ctrTitle"
end

local function get_preset(config)
    local pptx_config = config.pptx or {}
    local preset_name = pptx_config.preset
    if not preset_name then return {} end
    local home = pandoc_cli.get_speccompiler_home()
    local preset = preset_loader.load_with_extends(home, config.template or "default", preset_name)
    return preset or {}
end

function M.process_slide(content, config, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end
    local tree = xml.find_by_name(doc.root, "p:spTree")[1]
    if not tree then return content end

    local preset = get_preset(config)
    local pptx = preset.pptx or {}
    local layout = pptx.content_layout or {}
    local body_style = pptx.body or {}
    local title_style = pptx.title or {}
    local cover_style = pptx.cover_slide or {}
    local body_shape
    local title_shape
    local title_slide_heading
    local visuals = {}

    for _, shape in ipairs(tree.kids or {}) do
        if shape.type == "element" then
            if shape.name == "sp" then
                local ph = placeholder(shape)
                if ph and xml.get_attr(ph, "type") == "body" then body_shape = shape end
                if shape_title(shape) then title_shape = shape end
                if ph and xml.get_attr(ph, "idx") == "1"
                    and not shape_title(shape)
                    and #xml.find_children(xml.find_child(shape, "p:txBody") or {}, "a:p") > 1 then
                    title_slide_heading = shape
                end
            end
            local visual_kind = shape_visual(shape)
            if visual_kind then visuals[#visuals + 1] = {shape = shape, kind = visual_kind} end
        end
    end

    if title_shape then
        style_title(title_shape, layout.title or {
            x = 457200, y = 205979, cx = 8229600, cy = 857250,
        }, title_style)
    end
    -- The opening title slide has no dedicated title placeholder; its title is
    -- the first paragraph in idx=1. Content slides have an explicit title
    -- shape and may also have an idx=1 body placeholder with several list
    -- paragraphs, so never style that body text as the slide title.
    if not title_shape and title_slide_heading then
        style_cover_slide(title_slide_heading, title_style, cover_style)
    end

    if body_shape then style_body_text(body_shape, body_style) end
    if #visuals == 0 then return xml.serialize(doc) end

    local body_x = (layout.body and layout.body.x) or 457200
    local body_y = (layout.body and layout.body.y) or 1076326
    local body_cx = (layout.body and layout.body.cx) or 8229600
    local slide_bottom = (layout.slide_height or 5143500) - (layout.bottom_margin or 200000)

    -- Figure-only slides have no body placeholder for the normal mixed-content
    -- placement pass. Fit their single visual into the content area while
    -- preserving its aspect ratio; this is especially important for standalone
    -- PlantUML diagrams and evidence screenshots.
    if not body_shape then
        if #visuals == 1 then
            local visual = visuals[1]
            local transform = get_transform(visual.shape, visual.kind)
            local extent = transform and xml.find_child(transform, "a:ext")
            local old_cx = extent and tonumber(xml.get_attr(extent, "cx")) or 0
            local old_cy = extent and tonumber(xml.get_attr(extent, "cy")) or 0
            local available_cy = math.max(100000, slide_bottom - body_y)
            if old_cx > 0 and old_cy > 0 then
                local cx, cy
                if visual.kind == "pic" then
                    cx, cy = fit_picture(visual.shape, old_cx, old_cy,
                        body_cx, available_cy, body_cx, available_cy)
                else
                    local scale = math.min(body_cx / old_cx, available_cy / old_cy)
                    cx, cy = math.floor(old_cx * scale), math.floor(old_cy * scale)
                end
                set_transform(visual.shape, visual.kind, {
                    x = body_x + math.floor((body_cx - cx) / 2),
                    y = body_y + math.floor((available_cy - cy) / 2),
                    cx = cx,
                    cy = cy,
                })
            elseif visual.kind == "pic" then
                local width, height = requested_size(visual.shape, body_cx, available_cy)
                if log and (width or height) then
                    log.warn("[PPTX-POST] Cannot size a picture with missing or invalid dimensions")
                end
            end
        else
            for _, visual in ipairs(visuals) do
                if visual.kind == "pic" then
                    local transform = get_transform(visual.shape, visual.kind)
                    local offset = transform and xml.find_child(transform, "a:off")
                    local extent = transform and xml.find_child(transform, "a:ext")
                    local old_cx = extent and tonumber(xml.get_attr(extent, "cx")) or 0
                    local old_cy = extent and tonumber(xml.get_attr(extent, "cy")) or 0
                    local available_cy = math.max(100000, slide_bottom - body_y)
                    local width, height = requested_size(visual.shape, body_cx, available_cy)
                    if (width or height) and old_cx > 0 and old_cy > 0 and offset then
                        local cx, cy = fit_dimensions(old_cx, old_cy,
                            body_cx, available_cy, width, height)
                        local x = tonumber(xml.get_attr(offset, "x")) or body_x
                        local y = tonumber(xml.get_attr(offset, "y")) or body_y
                        set_transform(visual.shape, visual.kind, {
                            x = math.max(body_x, math.min(body_x + body_cx - cx,
                                x + math.floor((old_cx - cx) / 2))),
                            y = math.max(body_y, math.min(slide_bottom - cy,
                                y + math.floor((old_cy - cy) / 2))),
                            cx = cx, cy = cy,
                        })
                    elseif log and (width or height) then
                        log.warn("[PPTX-POST] Cannot size a picture with missing or invalid geometry")
                    end
                end
            end
        end
        return xml.serialize(doc)
    end

    local characters_per_line = body_style.max_chars_per_line or 68
    local font_size = body_style.font_size or 1900
    local line_height = (font_size / 100) * 12700 * (body_style.line_height or 1.15)
    local lines = estimate_lines(body_shape, characters_per_line)
    local gap = layout.visual_gap or 180000
    local visual_y = body_y + math.ceil(lines * line_height) + gap

    for _, visual in ipairs(visuals) do
        local transform = get_transform(visual.shape, visual.kind)
        local extent = transform and xml.find_child(transform, "a:ext")
        local old_cx = extent and tonumber(xml.get_attr(extent, "cx")) or body_cx
        local old_cy = extent and tonumber(xml.get_attr(extent, "cy")) or 1200000
        local cx = body_cx
        local cy
        local available = math.max(0, slide_bottom - visual_y)
        local x = body_x
        if visual.kind == "graphicFrame" then
            local rows = #xml.find_by_name(visual.shape, "a:tr")
            cy = math.max(500000, rows * 260000)
            if available > 0 and cy > available then cy = available end
        elseif old_cx > 0 and old_cy > 0 and available > 0 then
            cx, cy = fit_picture(visual.shape, old_cx, old_cy, body_cx, available,
                body_cx, math.max(100000, slide_bottom - body_y))
            x = body_x + math.floor((body_cx - cx) / 2)
        else
            if visual.kind == "pic" then
                requested_size(visual.shape, body_cx, math.max(100000, slide_bottom - body_y))
            end
            cy = old_cx > 0 and math.floor(old_cy * body_cx / old_cx) or old_cy
            if log then
                if available == 0 then
                    log.warn("[PPTX-POST] No space remains for a visual below the slide text")
                else
                    log.warn("[PPTX-POST] Cannot size a picture with missing or invalid dimensions")
                end
            end
        end
        set_transform(visual.shape, visual.kind, {x = x, y = visual_y, cx = cx, cy = cy})
        visual_y = visual_y + cy + gap
    end

    -- Text ends at the first visual, not at the last one.
    local first_transform = get_transform(visuals[1].shape, visuals[1].kind)
    local first_offset = first_transform and xml.find_child(first_transform, "a:off")
    local first_y = first_offset and tonumber(xml.get_attr(first_offset, "y")) or visual_y
    set_transform(body_shape, "shape", {
        x = body_x, y = body_y, cx = body_cx, cy = math.max(100000, first_y - body_y - gap),
    })

    if log then
        log.debug("[PPTX-POST] Positioned %d visual(s) after %d estimated body line(s)", #visuals, lines)
    end
    return xml.serialize(doc)
end

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

local function slide_has_visual(tree)
    for _, name in ipairs({"p:pic", "p:graphicFrame"}) do
        if #xml.find_children(tree, name) > 0 then return true end
    end
    return false
end

local function get_slide_tree(doc)
    return xml.find_by_name(doc.root, "p:spTree")[1]
end

local function remove_placeholder(shape)
    local non_visual = xml.find_child(shape, "p:nvSpPr")
    local properties = non_visual and xml.find_child(non_visual, "p:nvPr")
    local ph = properties and xml.find_child(properties, "p:ph")
    if ph then xml.remove_child(properties, ph) end
end

local function append_continuation(parent_doc, continuation_doc, layout, body_style)
    local parent_tree = get_slide_tree(parent_doc)
    local continuation_tree = get_slide_tree(continuation_doc)
    if not parent_tree or not continuation_tree or not slide_has_visual(parent_tree) then
        return false
    end
    local text_shapes = {}
    for _, shape in ipairs(xml.find_children(continuation_tree, "p:sp")) do
        local ph = placeholder(shape)
        if ph and not shape_title(shape) and xml.find_child(shape, "p:txBody") then
            text_shapes[#text_shapes + 1] = shape
        elseif shape_title(shape) then
            return false
        end
    end
    if #text_shapes == 0 or #xml.find_children(continuation_tree, "p:pic") > 0
        or #xml.find_children(continuation_tree, "p:graphicFrame") > 0 then
        return false
    end

    local layout = layout or {}
    local body = layout.body or {x = 457200, y = 1076326, cx = 8229600}
    local y = body.y
    for _, name in ipairs({"p:pic", "p:graphicFrame"}) do
        for _, visual in ipairs(xml.find_children(parent_tree, name)) do
            local transform = get_transform(visual, name == "p:pic" and "pic" or "graphicFrame")
            local offset = transform and xml.find_child(transform, "a:off")
            local extent = transform and xml.find_child(transform, "a:ext")
            if offset and extent then
                y = math.max(y, (tonumber(xml.get_attr(offset, "y")) or 0)
                    + (tonumber(xml.get_attr(extent, "cy")) or 0)
                    + (layout.visual_gap or 120000))
            end
        end
    end

    local font_size = body_style.font_size or 1800
    local line_height = math.floor((font_size / 100) * 12700 * (body_style.line_height or 1.15))
    for _, original in ipairs(text_shapes) do
        local shape = xml.clone(original)
        remove_placeholder(shape)
        local tx_body = xml.find_child(shape, "p:txBody")
        local paragraphs = tx_body and xml.find_children(tx_body, "a:p") or {}
        local lines = math.max(1, #paragraphs)
        for _, paragraph in ipairs(paragraphs) do
            local paragraph_props = ensure_child(paragraph, "a:pPr", 1)
            local no_bullet = xml.find_child(paragraph_props, "a:buNone")
            if no_bullet then xml.remove_child(paragraph_props, no_bullet) end
            if not xml.find_child(paragraph_props, "a:buAutoNum")
                and not xml.find_child(paragraph_props, "a:buChar") then
                xml.add_child(paragraph_props, xml.node("a:buChar", {char = "•"}))
            end
            if xml.find_child(paragraph_props, "a:buChar") then
                xml.set_attr(paragraph_props, "marL", "342900")
                xml.set_attr(paragraph_props, "indent", "-228600")
            end
            for _, run in ipairs(xml.find_children(paragraph, "a:r")) do
                local run_props = ensure_child(run, "a:rPr", 1)
                xml.set_attr(run_props, "sz", tostring(font_size))
            end
        end
        set_transform(shape, "shape", {
            x = body.x, y = y, cx = body.cx,
            cy = lines * line_height + (layout.visual_gap or 120000),
        })
        xml.add_child(parent_tree, shape)
        y = y + lines * line_height + (layout.visual_gap or 120000)
    end
    return true
end

function M.process_package(extract_dir, config, log)
    local pptx = get_preset(config).pptx or {}
    local layout = pptx.content_layout or {}
    local presentation_path = extract_dir .. "/ppt/presentation.xml"
    local rels_path = extract_dir .. "/ppt/_rels/presentation.xml.rels"
    local presentation_doc = xml.parse(read_file(presentation_path) or "")
    local rels_doc = xml.parse(read_file(rels_path) or "")
    if not presentation_doc or not presentation_doc.root or not rels_doc or not rels_doc.root then
        return true
    end

    local targets = {}
    for _, relation in ipairs(xml.find_children(rels_doc.root, "Relationship")) do
        local kind = xml.get_attr(relation, "Type") or ""
        if kind:match("/slide$") then
            targets[xml.get_attr(relation, "Id")] = (xml.get_attr(relation, "Target") or ""):gsub("^slides/", "")
        end
    end
    local list = xml.find_by_name(presentation_doc.root, "p:sldIdLst")[1]
    if not list then return true end
    local slide_ids = xml.find_children(list, "p:sldId")
    local removed = 0
    local removed_parts = {}
    local index = 1
    while index < #slide_ids do
        local current_id = slide_ids[index]
        local next_id = slide_ids[index + 1]
        local current_target = targets[xml.get_attr(current_id, "r:id")]
        local next_target = targets[xml.get_attr(next_id, "r:id")]
        if current_target and next_target then
            local current_path = extract_dir .. "/ppt/slides/" .. current_target
            local next_path = extract_dir .. "/ppt/slides/" .. next_target
            local parent_doc = xml.parse(read_file(current_path) or "")
            local continuation_doc = xml.parse(read_file(next_path) or "")
            if parent_doc and continuation_doc
                and append_continuation(parent_doc, continuation_doc, layout, pptx.body) then
                write_file(current_path, xml.serialize(parent_doc))
                xml.remove_child(list, next_id)
                local next_rid = xml.get_attr(next_id, "r:id")
                for _, relation in ipairs(xml.find_children(rels_doc.root, "Relationship")) do
                    if xml.get_attr(relation, "Id") == next_rid then
                        xml.remove_child(rels_doc.root, relation)
                        break
                    end
                end
                removed_parts[#removed_parts + 1] = next_target
                removed = removed + 1
                slide_ids = xml.find_children(list, "p:sldId")
                if log then log.debug("[PPTX-POST] Merged overflow slide %s into %s", next_target, current_target) end
            else
                index = index + 1
            end
        else
            index = index + 1
        end
    end
    if removed > 0 then
        write_file(presentation_path, xml.serialize(presentation_doc))
        write_file(rels_path, xml.serialize(rels_doc))
        local content_types_path = extract_dir .. "/[Content_Types].xml"
        local content_types_doc = xml.parse(read_file(content_types_path) or "")
        if content_types_doc and content_types_doc.root then
            for _, target in ipairs(removed_parts) do
                local name = "/ppt/slides/" .. target
                for _, override in ipairs(xml.find_children(content_types_doc.root, "Override")) do
                    if xml.get_attr(override, "PartName") == name then
                        xml.remove_child(content_types_doc.root, override)
                        break
                    end
                end
                os.remove(extract_dir .. "/ppt/slides/" .. target)
                os.remove(extract_dir .. "/ppt/slides/_rels/" .. target .. ".rels")
            end
            write_file(content_types_path, xml.serialize(content_types_doc))
        end
    end

    local number_style = pptx.slide_numbers or {}
    local ordered_targets = {}
    slide_ids = xml.find_children(list, "p:sldId")
    for _, slide_id in ipairs(slide_ids) do
        local target = targets[xml.get_attr(slide_id, "r:id")]
        if target then ordered_targets[#ordered_targets + 1] = target end
    end

    local typed_ok, typed_err = slide_types.apply(
        extract_dir, ordered_targets, config.db_path, pptx, log)
    if not typed_ok then
        return false, typed_err or "Failed to apply type-specific PPTX slide layouts"
    end

    local footer_config = config.pptx and config.pptx.footer
    if footer_config and (footer_config.text or footer_config.date) then
        local footer_ok, footer_err = footer.apply(
            extract_dir, ordered_targets, footer_config, pptx.footer_style or {})
        if not footer_ok then return false, footer_err or "Failed to add PPTX footer" end
    end

    if number_style.enabled ~= false then
        local numbered, number_err = slide_numbers.apply(extract_dir, ordered_targets, number_style)
        if not numbered then
            return false, number_err or "Failed to add PPTX slide numbers"
        end
    end
    return true
end

function M.finalize(paths, config, log)
    archive.finalize(paths, config, log, M)
    pptx_pdf.finalize(paths, config, log)
end

return M
