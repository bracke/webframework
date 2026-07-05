with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Web.Security;

package body Web.Static is
   use Ada.Strings.Fixed;
   use type Ada.Directories.File_Kind;

   function Ends_With (Value : String; Suffix : String) return Boolean is
   begin
      return Value'Length >= Suffix'Length
        and then Value (Value'Last - Suffix'Length + 1 .. Value'Last) = Suffix;
   end Ends_With;

   function Content_Type (Path : String) return String is
   begin
      if Ends_With (Path, ".html") then
         return "text/html; charset=utf-8";
      elsif Ends_With (Path, ".css") then
         return "text/css; charset=utf-8";
      elsif Ends_With (Path, ".js") then
         return "application/javascript; charset=utf-8";
      elsif Ends_With (Path, ".png") then
         return "image/png";
      elsif Ends_With (Path, ".jpg") or else Ends_With (Path, ".jpeg") then
         return "image/jpeg";
      elsif Ends_With (Path, ".svg") then
         return "image/svg+xml";
      elsif Ends_With (Path, ".ico") then
         return "image/x-icon";
      elsif Ends_With (Path, ".woff2") then
         return "font/woff2";
      end if;

      return "application/octet-stream";
   end Content_Type;

   function Read_File (Path : String) return String is
      use type Ada.Streams.Stream_Element_Offset;
      use type Ada.Streams.Stream_IO.Count;

      File : Ada.Streams.Stream_IO.File_Type;
      Size : Ada.Streams.Stream_IO.Count;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (File);

      if Size = 0 then
         Ada.Streams.Stream_IO.Close (File);
         return "";
      end if;

      declare
         Buffer : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last   : Ada.Streams.Stream_Element_Offset;
         Result : String (1 .. Natural (Size));
      begin
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Last /= Buffer'Last then
            raise Ada.Streams.Stream_IO.Use_Error;
         end if;

         for Index_Value in Result'Range loop
            Result (Index_Value) :=
              Character'Val
                (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index_Value - 1)));
         end loop;

         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_File;

   function Serve
     (Url_Prefix : String;
      Directory  : String;
      Path       : String) return Web.Response.Response_Type
   is
   begin
      if Index (Path, Url_Prefix) /= Path'First then
         return Web.Response.Not_Found;
      end if;

      if Path'Length = Url_Prefix'Length then
         return Web.Response.Bad_Request;
      end if;

      if Path'Length > Url_Prefix'Length
        and then Path (Path'First + Url_Prefix'Length) /= '/'
      then
         return Web.Response.Not_Found;
      end if;

      declare
         Relative  : constant String := Path (Path'First + Url_Prefix'Length .. Path'Last);
         File_Path : constant String := Directory & "/" & Relative;
      begin
         if Relative'Length = 0 or else not Web.Security.Is_Safe_Path (Relative) then
            return Web.Response.Bad_Request;
         end if;

         if not Ada.Directories.Exists (File_Path) then
            return Web.Response.Not_Found;
         end if;

         if Ada.Directories.Kind (File_Path) /= Ada.Directories.Ordinary_File then
            return Web.Response.Not_Found;
         end if;

         return Web.Response.Create (200, Read_File (File_Path), Content_Type (File_Path));
      end;
   exception
      when others =>
         return Web.Response.Internal_Server_Error;
   end Serve;
end Web.Static;
