with Web.Request;
with Web.Response;

package Tool_Soak_Handlers is
   --  Return the health response used by the soak harness server.
   --  @param Request HTTP request.
   --  @return Plain text health response.
   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type;
end Tool_Soak_Handlers;
