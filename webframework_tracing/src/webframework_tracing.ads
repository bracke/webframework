--  Webframework_Tracing — the bridge between W3C Trace Context and webframework.
--  It reads the incoming `traceparent` request header into a parent span context
--  (so a request continues an upstream trace), formats a context back into a
--  header value for a downstream call, and mounts a `/traces` endpoint that dumps
--  recently-collected finished spans (one JSON object per line) -- the tracing
--  analogue of `/metrics`. The span model, propagation, and export all belong to
--  the `tracing` crate; the tracer and collector to `tracing_runtime`; this
--  bridge only meets HTTP.
with Web.Request;
with Tracing.Context;
with Tracing_Runtime.Tracer;
package Webframework_Tracing is

   --  The header a W3C trace context travels in.
   Traceparent_Header_Name : constant String := "traceparent";

   --  Content type of the span dump.
   Content_Type : constant String := "application/x-ndjson; charset=utf-8";

   --  Parse the request's `traceparent` header into a parent context. Returns
   --  Tracing.Context.No_Context when the header is absent or malformed, so the
   --  caller then starts a root span.
   function Extract_Context
     (Request : Web.Request.Request_Type) return Tracing.Context.Span_Context;

   --  Format a context as a `traceparent` header value to send downstream.
   function Traceparent_Header
     (Context : Tracing.Context.Span_Context) return String;

   --  Point the span dump at a collector (the app's process-wide one).
   procedure Use_Collector
     (Sink : not null access Tracing_Runtime.Tracer.Collector);

   --  Mount a GET route that dumps the collector's spans as newline-delimited
   --  JSON. Requires Use_Collector to have been called first; otherwise the
   --  endpoint reports an empty body.
   procedure Install_Dump (Path : String := "/traces");

end Webframework_Tracing;
