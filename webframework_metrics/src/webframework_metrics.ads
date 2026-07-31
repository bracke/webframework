--  Webframework_Metrics — the bridge that serves a metrics registry over HTTP.
--  It mounts a GET route (default "/metrics") whose handler scrapes a live
--  registry and returns the text exposition with the matching content type. The
--  metrics data model, bounds, and rendering all belong to the `metrics` crate;
--  concurrency to `metrics_runtime`; this bridge only wires a scrape onto a
--  webframework route.
--
--  Register your metric families and record observations through the same
--  Metrics_Runtime.Live registry the endpoint reads (the process-wide
--  Metrics_Runtime.Live.Default unless you point it elsewhere with Use_Registry).
--
--  Serve the OpenMetrics dialect (Dialect => Metrics.Exposition.Open_Metrics) to
--  expose trace exemplars on histogram buckets; the Prometheus dialect omits
--  them.
with Metrics.Exposition;
with Metrics_Runtime.Live;
package Webframework_Metrics is

   --  The content type a scraper expects for a given exposition dialect.
   function Content_Type
     (Dialect : Metrics.Exposition.Format := Metrics.Exposition.Prometheus)
      return String
   is (case Dialect is
          when Metrics.Exposition.Prometheus =>
             "text/plain; version=0.0.4; charset=utf-8",
          when Metrics.Exposition.Open_Metrics =>
             "application/openmetrics-text; version=1.0.0; charset=utf-8");

   --  Serve the scrape at Path (default "/metrics") in the given dialect. Call
   --  once, before the server starts, alongside the app's other route
   --  registrations.
   procedure Install
     (Path    : String := "/metrics";
      Dialect : Metrics.Exposition.Format := Metrics.Exposition.Prometheus);

   --  Point the endpoint at a specific live registry. Without this the
   --  process-wide Metrics_Runtime.Live.Default is served.
   procedure Use_Registry
     (Registry : not null access Metrics_Runtime.Live.Live_Registry);

end Webframework_Metrics;
