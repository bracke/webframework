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

   --  Render the projects page.
   --  @param Request HTTP request.
   --  @return HTTP response with projects table.
   function Projects (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Render the todo page.
   --  @param Request HTTP request.
   --  @return HTTP response with todo list.
   function Todo (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  API endpoint to add a new project
   --  @param Request HTTP request with project data in form format
   --  @return HTTP response with status
   function Api_Add_Project (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  API endpoint to delete a project
   --  @param Request HTTP request with project id
   --  @return HTTP response with status
   function Api_Delete_Project (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

end App.Pages;
