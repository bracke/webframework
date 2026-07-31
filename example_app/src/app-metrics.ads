with Web.Request;
with Web.Context;
with Web.Guard;

--  App.Metrics — the example app's observability wiring. It registers a few
--  metric families in the process-wide live registry, counts every HTTP request
--  through a global guard, and (via App.Setup_Metrics_Endpoint) serves the
--  Prometheus exposition at /metrics through the webframework_metrics bridge.
package App.Metrics is

   --  Register the metric families. Call once at startup, before serving.
   procedure Setup;

   --  A global guard (installed with Use_Guard) that counts each request by
   --  HTTP method and always proceeds -- request counting as middleware.
   function Count_Request
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;

end App.Metrics;
