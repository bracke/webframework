with Web.Server;
with Web.Request;
with Web.Response;
package body Webframework_Metrics is

   --  The registry the endpoint scrapes; null selects the process-wide default.
   Target : access Metrics_Runtime.Live.Live_Registry := null;

   --  The dialect Install selected for the mounted route.
   Served_Dialect : Metrics.Exposition.Format := Metrics.Exposition.Prometheus;

   function Scrape_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      Body_Text : constant String :=
        (if Target = null
         then Metrics_Runtime.Live.Default.Scrape (Served_Dialect)
         else Target.Scrape (Served_Dialect));
   begin
      return Web.Response.Create
        (200, Body_Text, Content_Type (Served_Dialect));
   end Scrape_Handler;

   procedure Install
     (Path    : String := "/metrics";
      Dialect : Metrics.Exposition.Format := Metrics.Exposition.Prometheus) is
   begin
      Served_Dialect := Dialect;
      Web.Server.Get (Path, Scrape_Handler'Access);
   end Install;

   procedure Use_Registry
     (Registry : not null access Metrics_Runtime.Live.Live_Registry) is
   begin
      Target := Registry;
   end Use_Registry;

end Webframework_Metrics;
