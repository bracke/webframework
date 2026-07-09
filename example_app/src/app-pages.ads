with Web.Request;
with Web.Response;

--  Page rendering API for HTTP routes in the example application.
package App.Pages is
   --  Render the landing page with template fragments.
   --  Render the home route.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Health endpoint for probes and local smoke checks.
   --  Render the health-check route.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Custom 404 error page.
   --  @param Request Parsed request.
   --  @param Status HTTP status code.
   --  @param Detail Implementation detail in development mode.
   --  @return Error response.
   function Error_Not_Found
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type;

   --  Custom 400 error page.
   --  @param Request Parsed request.
   --  @param Status HTTP status code.
   --  @param Detail Implementation detail in development mode.
   --  @return Error response.
   function Error_Bad_Request
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type;

   --  Custom 500 error page.
   --  @param Request Parsed request.
   --  @param Status HTTP status code.
   --  @param Detail Implementation detail in development mode.
   --  @return Error response.
   function Error_Server
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type;

   --  Render the login page.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Handle login API endpoint.
   --  @param Request HTTP request containing username and password.
   --  @return HTTP response.
   function Api_Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Handle logout API endpoint.
   --  @param Request HTTP request.
   --  @return HTTP response.
   function Api_Logout (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Redirect to login page.
   --  @param Request HTTP request.
   --  @param Session_Id Session identifier for cookie.
   --  @return Redirect response.
   function Redirect_To_Login
     (Request : Web.Request.Request_Type; Session_Id : String) return Web.Response.Response_Type;
end App.Pages;
