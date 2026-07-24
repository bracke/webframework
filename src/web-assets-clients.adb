--  Asset versioning client utilities for the web framework.
--
--  This package provides a convenient API for applications to use
--  the Web.Assets versioning system for static files like CSS and JS.

with Ada.Directories;
with Ada.Strings.Unbounded;

package body Web.Assets.Clients is
   use Ada.Strings.Unbounded;

   --  Internal state for asset directory and version hashes
   Assets_Directory_Path : Unbounded_String := Null_Unbounded_String;
   Css_Version_Value : Unbounded_String := Null_Unbounded_String;
   Js_Version_Value : Unbounded_String := Null_Unbounded_String;

   --  Initialize version hashes for given asset directory.
   --  @param Directory Path to the directory containing static assets.
   procedure Initialize_Versions (Directory : String) is
   begin
      Assets_Directory_Path := To_Unbounded_String (Directory);

      --  Compute CSS version
      declare
         Full_Path : constant String := Directory & "/style.css";
      begin
         if Ada.Directories.Exists (Full_Path) then
            begin
               Css_Version_Value := To_Unbounded_String (Web.Assets.File_Version (Full_Path));
            exception
               when others =>
                  Css_Version_Value := Null_Unbounded_String;
            end;
         end if;
      end;

      --  Compute JS version
      declare
         Full_Path : constant String := Directory & "/webframework.js";
      begin
         if Ada.Directories.Exists (Full_Path) then
            begin
               Js_Version_Value := To_Unbounded_String (Web.Assets.File_Version (Full_Path));
            exception
               when others =>
                  Js_Version_Value := Null_Unbounded_String;
            end;
         end if;
      end;
   end Initialize_Versions;

   --  Get the CSS URL with cache busting.
   --  @return Versioned URL for style.css, or "/static/style.css" if versioning fails.
   function Css_Url return String is
   begin
      return Versioned_Asset_Url ("style.css");
   end Css_Url;

   --  Get the JavaScript URL with cache busting.
   --  @return Versioned URL for webframework.js, or "/static/webframework.js" if versioning fails.
   function Js_Url return String is
   begin
      return Versioned_Asset_Url ("webframework.js");
   end Js_Url;

   --  Get the versioned URL for a static asset.
   --  @param Filename Asset filename (e.g., "style.css").
   --  @return Versioned URL with cache-busting query parameter, or original URL if versioning fails.
   function Versioned_Asset_Url (Filename : String) return String is
      Base_Url : constant String := "/static/" & Filename;
   begin
      --  For now, only handle CSS and JS files with caching
      if Filename = "style.css" then
         declare
            Version : constant String := To_String (Css_Version_Value);
         begin
            if Version'Length > 0 then
               return Base_Url & "?v=" & Version;
            end if;
         end;
      elsif Filename = "webframework.js" then
         declare
            Version : constant String := To_String (Js_Version_Value);
         begin
            if Version'Length > 0 then
               return Base_Url & "?v=" & Version;
            end if;
         end;
      end if;

      --  Fall back to original URL for other files or if versioning fails
      return Base_Url;
   end Versioned_Asset_Url;

   --  Get the versioned filename for an asset.
   --  @param Filename Original filename.
   --  @return Versioned filename (e.g., "style.a1b2c3d4.css") or original filename if versioning fails.
   function Versioned_Asset_Filename (Filename : String) return String is
      Full_Path : constant String := To_String (Assets_Directory_Path) & "/" & Filename;
   begin
      --  For now, only handle CSS and JS files with versioning
      if Filename = "style.css" then
         declare
            Version : constant String := To_String (Css_Version_Value);
         begin
            if Version'Length > 0 then
               return Web.Assets.Versioned_Filename (Filename, Full_Path);
            end if;
         end;
      elsif Filename = "webframework.js" then
         declare
            Version : constant String := To_String (Js_Version_Value);
         begin
            if Version'Length > 0 then
               return Web.Assets.Versioned_Filename (Filename, Full_Path);
            end if;
         end;
      end if;

      return Filename;
   end Versioned_Asset_Filename;

end Web.Assets.Clients;
