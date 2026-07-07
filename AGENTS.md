# Agent instructions

This repository enforces GNAT 15 through Alire with `gnat_native = "=15.2.1"`
in every active manifest. Do not run plain system GNAT, GPRBuild, GNATprove,
GNATdoc, or related `gnat*` tools from `PATH`.

Use Alire-selected tools:

```sh
alr exec -- gnatls --version
alr build
cd tests && alr build
cd example_app && alr build
cd webframework_cli && alr build
cd tools && alr build
```

The compiler version command must report `GNATLS 15.x`.
