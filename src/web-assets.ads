--  Asset management and versioning for static files.
--
--  This package provides robust cache busting and versioning for CSS, JS,
--  and other static assets through content-based hashing and proper
--  HTTP cache headers.

with Web.Response;

package Web.Assets is
   --  Compute a content hash for a file path.
   --  @param Path Filesystem path to the asset file.
   --  @return Hex-encoded hash string for cache busting.
   function File_Hash (Path : String) return String;

   --  Compute a short version identifier for a file path.
   --  @param Path Filesystem path to the asset file.
   --  @return Short hash prefix (first 8 characters of full hash).
   function File_Version (Path : String) return String;

   --  Generate a versioned URL for an asset file.
   --  @param Base_Url Base URL path (e.g., "/static/style.css").
   --  @param File_Path Filesystem path to the asset file.
   --  @return Versioned URL with hash query parameter (e.g., "/static/style.css?v=a1b2c3d4").
   function Versioned_Url
     (Base_Url  : String;
      File_Path : String) return String;

   --  Generate a versioned filename for an asset file.
   --  @param Filename Original filename (e.g., "style.css").
   --  @param File_Path Filesystem path to the asset file.
   --  @return Versioned filename (e.g., "style.a1b2c3d4.css").
   function Versioned_Filename
     (Filename  : String;
      File_Path : String) return String;

   --  Return the Cache-Control header value for immutable assets.
   --  @return Cache-Control header string for long-term caching.
   function Immutable_Cache_Control return String;

   --  Return the Cache-Control header value for versioned assets.
   --  @return Cache-Control header string for versioned assets.
   function Versioned_Cache_Control return String;

   --  Apply cache headers to a response for immutable assets.
   --  @param Response Response to modify.
   --  @return No return value.
   procedure Apply_Immutable_Cache_Headers
     (Response : in out Web.Response.Response_Type);

   --  Apply cache headers to a response for versioned assets.
   --  @param Response Response to modify.
   --  @param ETag ETag value for the asset.
   --  @return No return value.
   procedure Apply_Versioned_Cache_Headers
     (Response : in out Web.Response.Response_Type;
      ETag     : String);

   --  Serve a versioned static asset with proper cache headers.
   --  @param Url_Prefix URL prefix for static files.
   --  @param Directory Filesystem directory containing the asset.
   --  @param Path Request path.
   --  @param Asset_Path Filesystem path to the actual asset file.
   --  @return HTTP response with cache headers.
   function Serve_Versioned
     (Url_Prefix  : String;
      Directory   : String;
      Path        : String;
      Asset_Path  : String) return Web.Response.Response_Type;

end Web.Assets;
