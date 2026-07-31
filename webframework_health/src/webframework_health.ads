--  Webframework_Health -- the bridge that serves health checks as HTTP probes.
--  It mounts a liveness route and a readiness route, each of which snapshots a
--  Health_Runtime.Checker, renders the JSON report, and maps the aggregate to a
--  status code: Unhealthy -> 503, otherwise 200. The check model, aggregation,
--  and rendering belong to the `health` crate; probe execution to
--  `health_runtime`; this bridge only wires two routes.
--
--  Liveness reads only liveness checks (a local "am I wedged" answer); readiness
--  reads all checks (dependencies reachable). Register probes through the same
--  Health_Runtime.Checker the endpoints read (the process-wide
--  Health_Runtime.Checker.Default unless pointed elsewhere with Use_Checker).
--
--  Health endpoints are conventionally unauthenticated and reached only from an
--  internal network / the orchestrator; pass a Guard to change that.
with Health_Runtime.Checker;
with Web.Guard;
package Webframework_Health is

   --  The JSON content type a probe response carries.
   Content_Type : constant String := "application/json; charset=utf-8";

   --  Mount the liveness probe at Path (default "/healthz"), optionally behind
   --  Guard (null installs none). 503 when a liveness check is Unhealthy.
   procedure Install_Liveness
     (Path  : String := "/healthz";
      Guard : Web.Guard.Guard_Access := null);

   --  Mount the readiness probe at Path (default "/readyz"). 503 when any
   --  Critical dependency is Unhealthy; 200 (still serving) when only degraded.
   procedure Install_Readiness
     (Path  : String := "/readyz";
      Guard : Web.Guard.Guard_Access := null);

   --  Point both endpoints at a specific checker. Without this the process-wide
   --  Health_Runtime.Checker.Default is served.
   procedure Use_Checker
     (Checker : not null access Health_Runtime.Checker.Checker);

end Webframework_Health;
