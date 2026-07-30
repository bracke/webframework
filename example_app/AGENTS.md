# Agent instructions — example_app

Reference app demonstrating the whole webframework stack. Part of the webframework workspace.

This workspace enforces GNAT 15 through Alire (`gnat_native = "=15.2.1"` in
every manifest). Do not run plain system GNAT / GPRBuild / GNATprove / GNATdoc
from `PATH`; use Alire-selected tools — `alr exec -- gnatls --version` must
report `GNATLS 15.x`.

Build and test this crate:

```sh
alr build
./bin/app_tests
./bin/app_http_tests
./bin/app_attachments_tests
./bin/app_email_tests
```
