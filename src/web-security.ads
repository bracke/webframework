with Web.Request;

package Web.Security is
   Max_Request_Size      : constant Natural := 1_048_576;
   Max_WebSocket_Message : constant Natural := 65_536;

   --  Check whether a URL or filesystem-relative path is safe.
   --  @param Path Candidate path.
   --  @return True when no traversal or absolute filesystem escape is present.
   function Is_Safe_Path (Path : String) return Boolean;

   --  Check whether a path is safe after percent decoding.
   --  @param Path Candidate path, possibly containing percent escapes.
   --  @return True when decoded path is valid and has no traversal or escapes.
   function Is_Safe_Decoded_Path (Path : String) return Boolean;

   --  Normalize and validate an HTTP authority.
   --  @param Value Candidate authority from Host or an Origin URL.
   --  @return Lower-case authority, or an empty string when invalid.
   function Normalize_Authority (Value : String) return String;

   --  Normalize and validate an HTTP or HTTPS origin.
   --  @param Value Candidate origin with scheme and authority.
   --  @return Lower-case origin, or an empty string when invalid.
   function Normalize_Origin (Value : String) return String;

   --  Generate a new opaque session id.
   --  @return Random URL-safe session id.
   function New_Session_Id return String;

   --  Check whether a string has the framework session id format.
   --  @param Id Candidate session id.
   --  @return True when the id has the expected length and alphabet.
   function Is_Valid_Session_Id (Id : String) return Boolean;

   --  Validate Origin/Host against an allowed origin.
   --  @param Request HTTP request.
   --  @param Allowed_Origin Expected origin or host.
   --  @return True when the request is allowed.
   function Require_Allowed_Origin
     (Request        : Web.Request.Request_Type;
      Allowed_Origin : String) return Boolean;
end Web.Security;
