with Web.Response;

package Web.Static is
   --  Return a content type for a static file path.
   --  @param Path File path.
   --  @return HTTP content type.
   function Content_Type (Path : String) return String;

   --  Serve a static file under a URL prefix and filesystem directory.
   --  @param Url_Prefix URL prefix.
   --  @param Directory Filesystem directory.
   --  @param Path Request path.
   --  @return HTTP response.
   function Serve
     (Url_Prefix : String;
      Directory  : String;
      Path       : String) return Web.Response.Response_Type;
end Web.Static;
