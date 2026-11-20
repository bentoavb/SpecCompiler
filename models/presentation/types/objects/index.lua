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
                local content = {pandoc.Str(("%d. "):format(number))}
                if anchor and anchor ~= "" then
                    table.insert(content, pandoc.Link({pandoc.Str(title)}, "#" .. anchor))
                else
                    table.insert(content, pandoc.Str(title))
                end
                table.insert(items, pandoc.Para(content))
            end

            local blocks = {header}
            if #items > 0 then
                for _, item in ipairs(items) do
                    table.insert(blocks, item)
                end
            else
                table.insert(blocks, pandoc.Para({pandoc.Str("No TITLE sections found.")}))
            end
            return blocks
        end,
    },
}