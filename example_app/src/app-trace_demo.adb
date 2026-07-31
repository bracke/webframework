with Tracing;
with Tracing.Context;
with Tracing.Spans;
with Tracing.Sampling;
with Tracing.Attributes;
with Tracing.Correlation;
with Tracing.Errors;
with Tracing_Runtime.Tracer;
with Tracing_Runtime.Clock;
with Metrics;
with Metrics.Errors;
with Metrics.Labels;
with Metrics_Runtime.Live;
with Webframework_Tracing;
with Webframework_Logging;

package body App.Trace_Demo is

   package Ctx   renames Tracing.Context;
   package Tr    renames Tracing_Runtime.Tracer;
   package Corr  renames Tracing.Correlation;
   package Attr  renames Tracing.Attributes;
   package WT    renames Webframework_Tracing;
   package Live  renames Metrics_Runtime.Live;

   use type Tracing.Timestamp;
   use type Metrics.Sample_Value;

   --  The latency histogram the exemplar attaches to: the observation of this
   --  handler's duration carries the request's trace id, so a scrape links a
   --  latency bucket back to a representative trace (visible in OpenMetrics).
   Latency_Metric : constant String := "app_trace_demo_latency_seconds";

   --  Process-wide state: one collector all traced spans flow into, and a
   --  sample-everything sampler for the demo.
   Sink    : aliased Tr.Collector;
   Sampler : constant Tracing.Sampling.Sampler := Tracing.Sampling.Always_On;

   procedure Setup is
      Cat : Metrics.Errors.Error_Category;
   begin
      WT.Use_Collector (Sink'Access);
      WT.Install_Dump ("/traces");
      Live.Default.Register_Histogram
        (Latency_Metric,
         [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0],
         "trace-demo handler latency, in seconds", "seconds", Cat);
   end Setup;

   function Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      --  Continue the incoming trace when the caller sent a traceparent.
      Parent : constant Ctx.Span_Context := WT.Extract_Context (Request);

      Server : Tr.Live_Span :=
        Tr.Start (Sampler, Parent, "GET /trace-demo", Tracing.Spans.Server);
      Ignore : Tracing.Errors.Error_Category;

      Started_At : constant Tracing.Timestamp :=
        Tracing_Runtime.Clock.Now_Unix_Nanos;
   begin
      Tr.Set_Attribute
        (Server, "http.method",
         Attr.Of_String (Web.Request.Method (Request), Ignore));
      Tr.Add_Event (Server, "handler.begin");

      --  Correlate: the log line carries the active trace id (the logging
      --  tie-in); a metric exemplar would carry the same id.
      Webframework_Logging.Info
        ("trace-demo request " & Corr.Trace_Id_Key & "="
         & Corr.Trace_Id_Image (Tr.Context_Of (Server)));

      --  A child client span for a simulated downstream call; its traceparent is
      --  what we would send on the outbound request.
      declare
         Child : Tr.Live_Span :=
           Tr.Start
             (Sampler, Tr.Context_Of (Server), "downstream lookup",
              Tracing.Spans.Client);
         Downstream : constant String :=
           WT.Traceparent_Header (Tr.Context_Of (Child));
      begin
         Tr.Set_Status (Child, Tracing.Spans.Ok);
         Tr.Finish (Child, Sink);

         Tr.Set_Status (Server, Tracing.Spans.Ok);
         Tr.Finish (Server, Sink);

         --  The metrics tie-in: record this handler's latency with an exemplar
         --  carrying the request's trace id (the same id the log line above
         --  logged). It surfaces on the histogram bucket in the OpenMetrics
         --  scrape at /metrics.
         declare
            Ended_At : constant Tracing.Timestamp :=
              Tracing_Runtime.Clock.Now_Unix_Nanos;
            Seconds  : constant Metrics.Sample_Value :=
              Metrics.Sample_Value (Ended_At - Started_At) / 1.0e9;
            Cat      : Metrics.Errors.Error_Category;
         begin
            Live.Default.Observe_With_Exemplar
              (Latency_Metric, Metrics.Labels.Empty, Seconds,
               Trace_Id     => Corr.Exemplar_Trace_Id (Tr.Context_Of (Server)),
               Time_Seconds => Metrics.Sample_Value (Ended_At) / 1.0e9,
               Has_Time     => True,
               Category     => Cat);
         end;

         return Web.Response.Text
           ("traced." & ASCII.LF
            & "trace_id=" & Corr.Trace_Id_Image (Tr.Context_Of (Server))
            & ASCII.LF
            & "downstream traceparent=" & Downstream & ASCII.LF
            & "see /traces for the exported spans");
      end;
   end Handler;

end App.Trace_Demo;
