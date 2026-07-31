# webframework_metrics

Bridge crate: serves a `metrics` registry over HTTP as a webframework route.

- `Webframework_Metrics.Install (Path => "/metrics")` mounts a GET route whose
  handler scrapes a live registry and returns the Prometheus text exposition
  with content type `text/plain; version=0.0.4; charset=utf-8`.
- By default it serves the process-wide `Metrics_Runtime.Live.Default`. Point it
  at another registry with `Use_Registry`.
- Register metric families and record observations through the **same**
  `Metrics_Runtime.Live` registry the endpoint reads.

The metrics data model, bounds, escaping, and rendering live in the `metrics`
crate; concurrency in `metrics_runtime`. This bridge is the only place a scrape
meets HTTP, mirroring how `webframework_logging` bridges the `logging` crate.

See the example_app demo: `App.Metrics` registers families and counts every
request through a global guard, and the main installs `/metrics`.
