with Web.Server;
with Web.Request;
with Web.Response;
package body Webframework_Metrics is

   --  The registry the endpoint scrapes; null selects the process-wide default.
   Target : access Metrics_Runtime.Live.Live_Registry := null;

   function Scrape_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      if Target = null then
         return Web.Response.Create
           (200, Metrics_Runtime.Live.Default.Scrape, Content_Type);
      else
         return Web.Response.Create (200, Target.Scrape, Content_Type);
      end if;
   end Scrape_Handler;

   procedure Install (Path : String := "/metrics") is
   begin
      Web.Server.Get (Path, Scrape_Handler'Access);
   end Install;

   procedure Use_Registry
     (Registry : not null access Metrics_Runtime.Live.Live_Registry) is
   begin
      Target := Registry;
   end Use_Registry;

end Webframework_Metrics;
