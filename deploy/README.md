# Deployment Templates

This directory contains starter assets for running and restarting example-style
webframework deployments on Linux hosts.

- `systemd/example_app.service`: systemd unit with environment file support.
- `supervisord/example_app.conf`: `supervisord` program stanza.
- `env/example_app.env`: sample environment values to keep command lines out of
  service files.
- `scripts/run_example_app.sh`: launcher that reads `env/example_app.env` and
  starts the executable with those arguments.

Copy the files you need into your site-specific locations and replace `EXAMPLE_APP`
paths and values.

