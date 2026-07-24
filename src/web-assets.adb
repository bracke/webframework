with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Web.Static;

package body Web.Assets is
   use Ada.Strings.Fixed;

   --  Simple hash computation using a basic algorithm
   function Compute_File_Hash (Path : String) return String is
      use type Ada.Streams.Stream_Element_Offset;
      use type Ada.Streams.Stream_IO.Count;

      File : Ada.Streams.Stream_IO.File_Type;
      Size : Ada.Streams.Stream_IO.Count;
      Hash_Value : Natural := 5381;  --  Simple hash seed
   begin
      --  Open file and get size
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (File);

      if Size = 0 then
         Ada.Streams.Stream_IO.Close (File);
         return "00000000";
      end if;

      --  Check file size limit
      if Size > Ada.Streams.Stream_IO.Count (10_000_000) then
         Ada.Streams.Stream_IO.Close (File);
         raise Constraint_Error with "asset file is too large for hashing";
      end if;

      declare
         Buffer : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Last /= Buffer'Last then
            raise Ada.Streams.Stream_IO.Use_Error;
         end if;

         --  Compute simple hash
         for Index_Value in Buffer'Range loop
            Hash_Value := (Hash_Value * 33 + Natural (Buffer (Index_Value))) mod 2_147_483_647;
         end loop;

         --  Convert to hex string
         return Trim (Natural'Image (Hash_Value), Ada.Strings.Both);

      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
            raise;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Compute_File_Hash;

   --  Compute full hash for a file
   function File_Hash (Path : String) return String is
   begin
      if not Ada.Directories.Exists (Path) then
         raise Constraint_Error with "asset file does not exist";
      end if;

      return Compute_File_Hash (Path);
   end File_Hash;

   --  Compute short version (first 8 chars of hash)
   function File_Version (Path : String) return String is
      Full_Hash : constant String := File_Hash (Path);
   begin
      if Full_Hash'Length >= 8 then
         return Full_Hash (Full_Hash'First .. Full_Hash'First + 7);
      else
         return Full_Hash;
      end if;
   end File_Version;

   --  Generate versioned URL with query parameter
   function Versioned_Url
     (Base_Url  : String;
      File_Path : String) return String
   is
      Version : constant String := File_Version (File_Path);
      Query_Index : Natural;
   begin
      if Base_Url'Length = 0 then
         return Base_Url;
      end if;

      --  Check if URL already has query parameters
      Query_Index := Index (Base_Url, "?");
      if Query_Index > 0 then
         return Base_Url & "&v=" & Version;
      else
         return Base_Url & "?v=" & Version;
      end if;
   end Versioned_Url;

   --  Generate versioned filename
   function Versioned_Filename
     (Filename  : String;
      File_Path : String) return String
   is
      Version : constant String := File_Version (File_Path);
      Dot_Index : constant Natural := Index (Filename, ".");
   begin
      if Dot_Index = 0 then
         --  No extension, append version at end
         return Filename & "." & Version;
      else
         --  Insert version before extension
         return Filename (Filename'First .. Dot_Index - 1) & "." & Version &
                Filename (Dot_Index .. Filename'Last);
      end if;
   end Versioned_Filename;

   --  Cache-Control for immutable assets (long-term caching)
   function Immutable_Cache_Control return String is
   begin
      return "public, max-age=31536000, immutable";
   end Immutable_Cache_Control;

   --  Cache-Control for versioned assets
   function Versioned_Cache_Control return String is
   begin
      return "public, max-age=31536000, must-revalidate";
   end Versioned_Cache_Control;

   --  Apply immutable cache headers
   procedure Apply_Immutable_Cache_Headers
     (Response : in out Web.Response.Response_Type)
   is
   begin
      Web.Response.Set_Header (Response, "Cache-Control", Immutable_Cache_Control);
      --  Also set for HTTP/1.0 compatibility
      Web.Response.Set_Header (Response, "Expires", "Thu, 31 Dec 2037 23:55:55 GMT");
   end Apply_Immutable_Cache_Headers;

   --  Apply versioned cache headers with ETag
   procedure Apply_Versioned_Cache_Headers
     (Response : in out Web.Response.Response_Type;
      ETag     : String)
   is
      DQ : constant Character := Character'Val (34); --  Double quote character
   begin
      Web.Response.Set_Header (Response, "Cache-Control", Versioned_Cache_Control);
      Web.Response.Set_Header (Response, "ETag", DQ & ETag & DQ);
      Web.Response.Set_Header (Response, "Expires", "Thu, 31 Dec 2037 23:55:55 GMT");
   end Apply_Versioned_Cache_Headers;

   --  Serve a versioned asset with proper cache headers
   function Serve_Versioned
     (Url_Prefix  : String;
      Directory   : String;
      Path        : String;
      Asset_Path  : String) return Web.Response.Response_Type
   is
      --  First, serve the file using the standard static server
      Response : Web.Response.Response_Type :=
        Web.Static.Serve (Url_Prefix, Directory, Path);

      --  Check if the response is successful
      Status : constant Positive := Web.Response.Status (Response);
   begin
      if Status = 200 then
         --  Get file size and hash for ETag
         declare
            File_Size : constant Natural :=
              Natural (Ada.Directories.Size (Asset_Path));
            Hash_Value : constant String := File_Hash (Asset_Path);

            --  Create ETag based on hash and file size
            ETag : constant String :=
              Hash_Value & "-" & Trim (Natural'Image (File_Size), Ada.Strings.Both);
         begin
            --  Apply cache headers
            Apply_Versioned_Cache_Headers (Response, ETag);

            --  Add Last-Modified header (simplified - use file size in ETag only)
            --  For now, skip Last-Modified to avoid calendar complexity
            null;
         end;
      end if;

      return Response;
   end Serve_Versioned;

end Web.Assets;
