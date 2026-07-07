with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Web.Errors;
with Web.Security;

package body Web.Static is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Ada.Containers.Count_Type;
   use type Ada.Containers.Hash_Type;
   use type Ada.Directories.File_Size;
   use type Ada.Directories.File_Kind;

   Max_Cached_Static_File : constant Natural := 65_536;
   Max_Static_Cache_Items : constant Natural := 64;
   Static_Cache_Shard_Count : constant Positive := 8;
   Max_Static_Cache_Items_Per_Shard : constant Natural :=
     Max_Static_Cache_Items / Static_Cache_Shard_Count;
   Static_Revalidate_Interval : constant Duration := 0.25;

   type Cache_Entry is record
      Path         : Unbounded_String;
      Response     : Web.Response.Response_Type;
      Size         : Natural := 0;
      Modified     : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Checked_At   : Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
      Last_Used    : Natural := 0;
   end record;

   package Cache_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => Cache_Entry,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   protected type Static_Cache_Shard is
      procedure Lookup
        (Path         : String;
         Size         : Natural;
         Modified     : Ada.Calendar.Time;
         Found        : out Boolean;
         Response     : out Web.Response.Response_Type);
      procedure Lookup_Fresh
        (Path         : String;
         Now          : Ada.Calendar.Time;
         Found        : out Boolean;
         Response     : out Web.Response.Response_Type);
      procedure Store
        (Path         : String;
         Size         : Natural;
         Modified     : Ada.Calendar.Time;
         Content      : String;
         Response     : Web.Response.Response_Type);
   private
      Entries : Cache_Maps.Map;
      Clock   : Natural := 0;
      Eviction_Cursor : Cache_Maps.Cursor;
   end Static_Cache_Shard;

   protected body Static_Cache_Shard is
      procedure Touch_Next is
      begin
         if Clock = Natural'Last then
            Clock := 1;
         else
            Clock := Clock + 1;
         end if;
      end Touch_Next;

      procedure Evict_One is
      begin
         if Entries.Is_Empty then
            return;
         end if;

         if not Cache_Maps.Has_Element (Eviction_Cursor) then
            Eviction_Cursor := Entries.First;
         end if;

         declare
            Key : constant String := Cache_Maps.Key (Eviction_Cursor);
         begin
            Cache_Maps.Next (Eviction_Cursor);
            Entries.Delete (Key);
         end;
      end Evict_One;

      procedure Lookup
        (Path         : String;
         Size         : Natural;
         Modified     : Ada.Calendar.Time;
         Found        : out Boolean;
         Response     : out Web.Response.Response_Type)
      is
         Cursor : Cache_Maps.Cursor := Entries.Find (Path);
   begin
      Found := False;
      if Cache_Maps.Has_Element (Cursor) then
         declare
            Item : Cache_Entry := Cache_Maps.Element (Cursor);
         begin
            if Item.Size = Size and then Item.Modified = Modified then
               Touch_Next;
               Item.Last_Used := Clock;
               Item.Checked_At := Ada.Calendar.Clock;
               Entries.Replace_Element (Cursor, Item);
               Found := True;
               Response := Item.Response;
               return;
            end if;

            Entries.Delete (Cursor);
         end;
      end if;

         Response := Web.Response.Internal_Server_Error;
   end Lookup;

      procedure Lookup_Fresh
        (Path         : String;
         Now          : Ada.Calendar.Time;
         Found        : out Boolean;
         Response     : out Web.Response.Response_Type)
      is
         Cursor : Cache_Maps.Cursor := Entries.Find (Path);
      begin
         Found := False;
         if Cache_Maps.Has_Element (Cursor) then
            declare
               Item : Cache_Entry := Cache_Maps.Element (Cursor);
            begin
               if Now - Item.Checked_At <= Static_Revalidate_Interval then
                  Touch_Next;
                  Item.Last_Used := Clock;
                  Entries.Replace_Element (Cursor, Item);
                  Found := True;
                  Response := Item.Response;
                  return;
               end if;
            end;
         end if;

         Response := Web.Response.Internal_Server_Error;
      end Lookup_Fresh;

      procedure Store
        (Path         : String;
         Size         : Natural;
         Modified     : Ada.Calendar.Time;
         Content      : String;
         Response     : Web.Response.Response_Type)
      is
         Cursor : Cache_Maps.Cursor;
      begin
         if Content'Length > Max_Cached_Static_File then
            return;
         end if;

         Cursor := Entries.Find (Path);
         if not Cache_Maps.Has_Element (Cursor) then
            if Entries.Length >= Ada.Containers.Count_Type (Max_Static_Cache_Items_Per_Shard) then
               Evict_One;
            end if;
         end if;

         Touch_Next;
         Entries.Include
            (Path,
             (Path         => To_Unbounded_String (Path),
              Response     => Response,
              Size         => Size,
              Modified     => Modified,
              Checked_At   => Ada.Calendar.Clock,
              Last_Used    => Clock));
      end Store;
   end Static_Cache_Shard;

   type Static_Cache_Shard_Array is array (Positive range <>) of Static_Cache_Shard;

   Static_Caches : Static_Cache_Shard_Array (1 .. Static_Cache_Shard_Count);

   function Static_Cache_Index (Path : String) return Positive is
   begin
      return
        Positive
          (Natural
             (Ada.Strings.Hash (Path)
              mod Ada.Containers.Hash_Type (Static_Cache_Shard_Count))
           + 1);
   end Static_Cache_Index;

   function Ends_With (Value : String; Suffix : String) return Boolean is
   begin
      return Value'Length >= Suffix'Length
        and then Value (Value'Last - Suffix'Length + 1 .. Value'Last) = Suffix;
   end Ends_With;

   function Content_Type (Path : String) return String is
      Normalized_Path : constant String := Ada.Characters.Handling.To_Lower (Path);
   begin
      if Ends_With (Normalized_Path, ".html") then
         return "text/html; charset=utf-8";
      elsif Ends_With (Normalized_Path, ".css") then
         return "text/css; charset=utf-8";
      elsif Ends_With (Normalized_Path, ".js") then
         return "application/javascript; charset=utf-8";
      elsif Ends_With (Normalized_Path, ".png") then
         return "image/png";
      elsif
         Ends_With (Normalized_Path, ".jpg")
         or else Ends_With (Normalized_Path, ".jpeg")
      then
         return "image/jpeg";
      elsif Ends_With (Normalized_Path, ".svg") then
         return "image/svg+xml";
      elsif Ends_With (Normalized_Path, ".ico") then
         return "image/x-icon";
      elsif Ends_With (Normalized_Path, ".woff2") then
         return "font/woff2";
      end if;

      return "application/octet-stream";
   end Content_Type;

   function Is_Valid_Url_Prefix (Url_Prefix : String) return Boolean is
   begin
      return Url_Prefix'Length > 0
        and then Url_Prefix (Url_Prefix'First) = '/'
        and then Index (Url_Prefix, "?") = 0
        and then Index (Url_Prefix, "#") = 0
        and then Web.Security.Is_Safe_Path (Url_Prefix)
        and then Web.Security.Is_Safe_Decoded_Path (Url_Prefix);
   end Is_Valid_Url_Prefix;

   function Is_Valid_Directory (Directory : String) return Boolean is
   begin
      return Directory'Length > 0
        and then Web.Security.Is_Safe_Path (Directory)
        and then Web.Security.Is_Safe_Decoded_Path (Directory);
   end Is_Valid_Directory;

   function Static_Cache_Key
     (Path     : String;
      Size     : Natural;
      Modified : Ada.Calendar.Time) return String
   is
      Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1901, 1, 1);
   begin
      return
        Path
        & ":"
        & Trim (Natural'Image (Size), Ada.Strings.Both)
        & ":"
        & Trim (Duration'Image (Modified - Epoch), Ada.Strings.Both);
   end Static_Cache_Key;

   function Read_File (Path : String) return String is
      use type Ada.Streams.Stream_Element_Offset;
      use type Ada.Streams.Stream_IO.Count;

      File : Ada.Streams.Stream_IO.File_Type;
      Size : Ada.Streams.Stream_IO.Count;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (File);

      if Size > Ada.Streams.Stream_IO.Count (Web.Security.Max_Request_Size) then
         raise Web.Errors.Security_Error with "static file is too large";
      end if;

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
      if not Is_Valid_Url_Prefix (Url_Prefix)
        or else not Is_Valid_Directory (Directory)
      then
         return Web.Response.Bad_Request;
      end if;

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
         Relative  : constant String := Path (Path'First + Url_Prefix'Length + 1 .. Path'Last);
         File_Path : constant String := Directory & "/" & Relative;
         Cache_Id  : constant Positive := Static_Cache_Index (File_Path);
         Now       : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      begin
         if Relative'Length = 0
            or else not Web.Security.Is_Safe_Path (Relative)
            or else not Web.Security.Is_Safe_Decoded_Path (Relative)
          then
            return Web.Response.Bad_Request;
         end if;

         declare
            Cached_Response : Web.Response.Response_Type;
            Found          : Boolean;
         begin
            Static_Caches (Cache_Id).Lookup_Fresh
              (File_Path,
               Now,
               Found,
               Cached_Response);
            if Found then
               return Cached_Response;
            end if;
         end;

         if not Ada.Directories.Exists (File_Path) then
            return Web.Response.Not_Found;
         end if;

         if Ada.Directories.Kind (File_Path) /= Ada.Directories.Ordinary_File then
            return Web.Response.Not_Found;
         end if;

         declare
            Cached_Response : Web.Response.Response_Type;
            Raw_Size       : constant Ada.Directories.File_Size := Ada.Directories.Size (File_Path);
            Modified       : constant Ada.Calendar.Time := Ada.Directories.Modification_Time (File_Path);
            Found          : Boolean;
         begin
            if Raw_Size > Ada.Directories.File_Size (Web.Security.Max_Request_Size) then
               raise Web.Errors.Security_Error with "static file is too large";
            end if;

            Static_Caches (Cache_Id).Lookup
              (File_Path,
               Natural (Raw_Size),
               Modified,
               Found,
               Cached_Response);

            if Found then
               return Cached_Response;
            end if;

            if Raw_Size > Ada.Directories.File_Size (Max_Cached_Static_File) then
               declare
                  Type_Value : constant String := Content_Type (File_Path);
                  Response : Web.Response.Response_Type :=
                    Web.Response.Create_File
                      (200,
                       File_Path,
                       Natural (Raw_Size),
                       Type_Value);
               begin
                  Web.Response.Set_Cache_Key
                    (Response,
                     Static_Cache_Key (File_Path, Natural (Raw_Size), Modified));
                Web.Response.Freeze_Serialized (Response);
                  return Response;
               end;
            end if;

            declare
               Content : constant String := Read_File (File_Path);
               Type_Value : constant String := Content_Type (File_Path);
               Response : Web.Response.Response_Type :=
                 Web.Response.Create (200, Content, Type_Value);
            begin
               Web.Response.Set_Cache_Key
                 (Response,
                  Static_Cache_Key (File_Path, Natural (Raw_Size), Modified));
               Web.Response.Freeze_Serialized (Response);
               Static_Caches (Cache_Id).Store
                 (File_Path,
                  Natural (Raw_Size),
                  Modified,
                  Content,
                  Response);
               return Response;
            end;
         end;
      end;
   exception
      when Web.Errors.Security_Error =>
         return Web.Response.Bad_Request;
      when others =>
         return Web.Response.Internal_Server_Error;
   end Serve;
end Web.Static;
