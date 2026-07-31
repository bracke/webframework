with Metrics.Errors;
with Metrics.Testing;
with Metrics_Runtime.Live;

package body App.Metrics is

   --  Inside package App.Metrics the name "Metrics" denotes this package, so the
   --  top-level metrics crate is reached through Standard.
   package Errs renames Standard.Metrics.Errors;
   package Tst renames Standard.Metrics.Testing;
   package Live renames Metrics_Runtime.Live;

   procedure Setup is
      Cat : Errs.Error_Category;
   begin
      Live.Default.Register_Counter
        ("app_http_requests_total", "HTTP requests handled, by method", "", Cat);
      Live.Default.Register_Gauge
        ("app_build_info", "Build info; value is always 1", "", Cat);
      --  A build-info gauge: the version travels as a label, the value is 1.
      Live.Default.Set
        ("app_build_info", Tst.Make ("version", "0.1.0-dev"), 1.0, Cat);
   end Setup;

   function Count_Request
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome
   is
      pragma Unreferenced (Context);
      Cat : Errs.Error_Category;
   begin
      Live.Default.Inc
        ("app_http_requests_total",
         Tst.Make ("method", Web.Request.Method (Request)), Cat);
      return Web.Guard.Proceed;
   end Count_Request;

end App.Metrics;
