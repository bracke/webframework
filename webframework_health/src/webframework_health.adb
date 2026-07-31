with Web.Server;
with Web.Request;
with Web.Context;
with Web.Response;
with Health;
with Health.Report;
with Health.Rendering;
package body Webframework_Health is

   use type Health.Health_Status;
   package Chk renames Health_Runtime.Checker;

   --  The checker the endpoints snapshot; null selects the process-wide default.
   Target : access Chk.Checker := null;

   function Checker_Ref return not null access Chk.Checker is
     (if Target = null then Chk.Default else Target);

   --  Snapshot the checker for a kind, render the JSON, and map the aggregate to
   --  a status code: Unhealthy -> 503 (take me out of rotation / restart me),
   --  otherwise 200 (healthy, or degraded but still serving).
   function Probe_Response
     (For_Kind : Health.Probe_Kind) return Web.Response.Response_Type
   is
      Report : constant Health.Report.Health_Report :=
        Chk.Snapshot (Checker_Ref.all, For_Kind);
      Body_Text : constant String :=
        Health.Rendering.Render (Report, For_Kind, Health.Rendering.Json);
      Code : constant Natural :=
        (if Health.Report.Overall (Report, For_Kind) = Health.Unhealthy
         then 503 else 200);
   begin
      return Web.Response.Create (Code, Body_Text, Content_Type);
   end Probe_Response;

   function Liveness_Handler
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request, Context);
   begin
      return Probe_Response (Health.Liveness);
   end Liveness_Handler;

   function Readiness_Handler
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request, Context);
   begin
      return Probe_Response (Health.Readiness);
   end Readiness_Handler;

   procedure Install_Liveness
     (Path  : String := "/healthz";
      Guard : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Get (Path, Liveness_Handler'Access, Guard);
   end Install_Liveness;

   procedure Install_Readiness
     (Path  : String := "/readyz";
      Guard : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Get (Path, Readiness_Handler'Access, Guard);
   end Install_Readiness;

   procedure Use_Checker
     (Checker : not null access Health_Runtime.Checker.Checker) is
   begin
      Target := Checker;
   end Use_Checker;

end Webframework_Health;
