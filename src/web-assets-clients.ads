--  Asset versioning client utilities.
--
--  This package provides a convenient API for applications to use
--  the Web.Assets versioning system for static files like CSS and JS.

package Web.Assets.Clients is

   --  Initialize version hashes for given asset directory.
   --  @param Directory Path to the directory containing static assets.
   procedure Initialize_Versions (Directory : String);

   --  Get the CSS URL with cache busting.
   --  @return Versioned URL for style.css, or "/static/style.css" if versioning fails.
   function Css_Url return String;

   --  Get the JavaScript URL with cache busting.
   --  @return Versioned URL for webframework.js, or "/static/webframework.js" if versioning fails.
   function Js_Url return String;

   --  Get the versioned URL for a static asset.
   --  @param Filename Asset filename (e.g., "style.css").
   --  @return Versioned URL with cache-busting query parameter, or original URL if versioning fails.
   function Versioned_Asset_Url (Filename : String) return String;

   --  Get the versioned filename for an asset.
   --  @param Filename Original filename.
   --  @return Versioned filename (e.g., "style.a1b2c3d4.css") or original filename if versioning fails.
   function Versioned_Asset_Filename (Filename : String) return String;

end Web.Assets.Clients;
