with Web.Request;
with Web.Response;

--  App.Trace_Demo — the example app's distributed-tracing demo. A handler starts
--  a server span for the request (continuing an incoming W3C trace when present),
--  records a child client span for a simulated downstream call, logs with the
--  trace id (correlating logs and traces), and finishes the spans into a
--  process-wide collector. The /traces endpoint (mounted by Setup) dumps the
--  collected spans as newline-delimited JSON, the tracing analogue of /metrics.
package App.Trace_Demo is

   --  Mount /traces and point the bridge at the process-wide collector.
   procedure Setup;

   --  GET /trace-demo: a traced request that emits a server span and a child
   --  client span, and returns the trace id and the downstream traceparent.
   function Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

end App.Trace_Demo;
