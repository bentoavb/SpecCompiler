---INDEX object type for presentation contents slides.
---Author with an explicit heading prefix: `## INDEX: Contents`.

return {
    kind = "object",
    schema = {
        id = "INDEX",
        long_name = "Presentation Index",
        description = "Slide listing all TITLE sections in the presentation",
        extends = "SECTION",
        numbered = false,
    },
    hooks = {
        render = function(ctx)
            local obj = ctx.subject.object or {}
            local level = math.max((ctx.subject.header_level or 2) - 1, 1)
            local header = pandoc.Header(level, {
                pandoc.Str(obj.title_text or "Contents"),
            })
            if obj.pid and obj.pid ~= "" then
                header.attr = pandoc.Attr(obj.pid, {"unnumbered"})
            else
                header.attr = pandoc.Attr("", {"unnumbered"})
            end

            local rows = ctx.data:query_all([[
                SELECT id, title_text, label
                FROM spec_objects
                WHERE specification_ref = :spec_id
                  AND type_ref = 'TITLE'
                ORDER BY file_seq
            ]], { spec_id = ctx.spec_id }) or {}

            local items = {}
            for number, row in ipairs(rows) do
                local title = row.title_text or "Untitled"
                local anchor = row.label or row.id
                local display = ("%d. %s"):format(number, title)
                if anchor and anchor ~= "" then
                    local link = pandoc.Link({pandoc.Str(display)}, "#" .. anchor)
                    table.insert(items, {pandoc.Plain({link})})
                else
                    table.insert(items, {pandoc.Plain({pandoc.Str(display)})})
                end
            end

            local blocks = {header}
            if #items > 0 then
                table.insert(blocks, pandoc.BulletList(items))
            else
                table.insert(blocks, pandoc.Para({pandoc.Str("No TITLE sections found.")}))
            end
            return blocks
        end,
    },
}