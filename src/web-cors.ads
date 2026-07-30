--  Web.CORS — Cross-Origin Resource Sharing response headers. A Policy describes
--  which origins may call the server and what a browser preflight is allowed to
--  do; Apply adds the matching Access-Control-* headers to a response, based on
--  the request's Origin. Configure it once with Web.Server.Set_CORS and the
--  server applies it to every response (including the auto-answered OPTIONS
--  preflight); the framework never sends CORS headers unless a policy is set.
private with Ada.Strings.Unbounded;
with Web.Request;
with Web.Response;
package Web.CORS is

   type Policy is private;

   --  Build a CORS policy.
   --  @param Origins     "*" to allow any origin, or a comma-separated allowlist
   --                     ("https://a.example, https://b.example"). Only an origin
   --                     on the list (or any, for "*") receives CORS headers.
   --  @param Methods     Access-Control-Allow-Methods sent on a preflight.
   --  @param Headers     Access-Control-Allow-Headers sent on a preflight
   --                     ("" omits it).
   --  @param Expose      Access-Control-Expose-Headers on actual responses
   --                     ("" omits it).
   --  @param Credentials whether cookies/credentials are allowed. When True the
   --                     matched origin is echoed (never "*", per the spec).
   --  @param Max_Age     preflight cache lifetime in seconds (0 omits it).
   function Make
     (Origins     : String;
      Methods     : String := "GET, POST, PUT, PATCH, DELETE, OPTIONS";
      Headers     : String := "Content-Type";
      Expose      : String := "";
      Credentials : Boolean := False;
      Max_Age     : Natural := 0) return Policy;

   --  Add the appropriate Access-Control-* headers to Response for Request,
   --  based on its Origin (and, on a preflight OPTIONS, the requested method and
   --  headers). A request with no Origin, or an Origin the policy does not
   --  allow, leaves Response unchanged.
   procedure Apply
     (P        : Policy;
      Request  : Web.Request.Request_Type;
      Response : in out Web.Response.Response_Type);

   --  Whether the policy would allow (send CORS headers for) this origin. The
   --  server uses it to let a CORS-allowed cross-origin request past its
   --  same-origin gate, so a preflight or a cross-origin call is not rejected
   --  before CORS can apply. An empty origin (a same-origin request) is not a
   --  CORS origin and returns False.
   function Allows_Origin (P : Policy; Origin : String) return Boolean;

private

   use Ada.Strings.Unbounded;

   type Policy is record
      Origins     : Unbounded_String;
      Methods     : Unbounded_String;
      Headers     : Unbounded_String;
      Expose      : Unbounded_String;
      Credentials : Boolean := False;
      Max_Age     : Natural := 0;
      Any_Origin  : Boolean := False;
   end record;

end Web.CORS;
