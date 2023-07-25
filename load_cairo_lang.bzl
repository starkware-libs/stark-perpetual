# For configs that depend on cairo-lang packages
def load_cairo_lang():
    native.local_repository(
        name = "cairo-lang",
        path = "dependency_configs/cairo",
    )
