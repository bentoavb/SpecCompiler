---TITLE object type for numbered presentation section slides.
---Author with an explicit heading prefix: `## TITLE: Presentation Section`.

local spec_object_base = require("pipeline.shared.spec_object_base")

local function title_number(ctx)
    local object = ctx.subject.object or {}
    local rows = ctx.data:query_all([[
        SELECT id
        FROM spec_objects
        WHERE specification_ref = :spec_id
          AND type_ref = 'TITLE'
        ORDER BY file_seq, id
    ]], { spec_id = ctx.spec_id }) or {}

    for number, row in ipairs(rows) do
        if row.id == object.id then return number end
    end
    return 1
end

return {
    kind = "object",
    schema = {
        id = "TITLE",
        long_name = "Title Slide",
        description = "Numbered presentation section slide",
        extends = "SECTION",
        numbered = false,
    },
    hooks = {
        render = function(ctx)
            local object = ctx.subject.object or {}
            local title = object.title_text or "Untitled"
            local header = pandoc.Header(
                math.max((ctx.subject.header_level or 2) - 1, 1),
                {pandoc.Str(('%d. %s'):format(title_number(ctx), title))}
            )
            header.attr = pandoc.Attr(
                object.pid or "",
                {"unnumbered"}
            )

            local blocks = {header}
            for _, block in ipairs(ctx.subject.element or {}) do
                table.insert(blocks, block)
            end

            local attr_div = spec_object_base.render_attributes(
                {attributes = ctx.subject.attributes or {}}, pandoc,
                ctx.subject.type_schema and ctx.subject.type_schema.attr_order)
            if attr_div then table.insert(blocks, attr_div) end
            return blocks
        end,
    },
}
