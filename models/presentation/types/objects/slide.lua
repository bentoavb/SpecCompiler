---SLIDE object type for regular presentation slides.
---Author with an explicit heading prefix: `## SLIDE: Slide Name`.

return {
    kind = "object",
    schema = {
        id = "SLIDE",
        long_name = "Presentation Slide",
        description = "Regular content slide in a presentation",
        extends = "SECTION",
    },
}
