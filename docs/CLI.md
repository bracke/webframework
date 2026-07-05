# CLI

`webframework_cli` builds the `webframework` executable. It is an optional
tooling crate and is not a runtime dependency of `webframework`.

Commands:

- `webframework new NAME`
- `webframework add page ROOT NAME ROUTE`
- `webframework add feature ROOT NAME`
- `webframework add handler ROOT ACTION`
- `webframework add form ROOT NAME`
- `webframework check [ROOT]`

Generated apps use explicit Ada files, `webframework.toml`, templates, and
static assets. `webframework new` accepts a plain app name, a nested path, or an
absolute destination path; the Ada project name is derived from the final path
component. The generator writes plain files only; there is no hidden code
generation after creation.

`webframework check` validates the app manifest, expected directories, the
browser runtime, dispatcher/live wiring, route registration, action handler
registration, duplicate manifest entries, template/static file presence, and
patch targets where they are visible in source or templates. Apps with no
declared actions yet are valid; action registration is required once actions
appear in the manifest.

A repository root may contain a redirect manifest:

```toml
app_root = "example_app"
```

In that case `webframework check .` validates the app under `example_app/`.
