with Web.Server;

package body Tool_Soak_Handlers is
   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      pragma Unreferenced (Request);
   begin
      return Web.Server.Health_Response;
   end Health;
end Tool_Soak_Handlers;
