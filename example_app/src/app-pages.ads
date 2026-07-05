with Web.Request;
with Web.Response;

package App.Pages is
   --  Render the home route.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type;
end App.Pages;
