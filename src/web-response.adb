with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Interfaces;
with Web.Errors;
with Zlib;

package body Web.Response is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Containers.Hash_Type;
   use type Interfaces.Unsigned_32;
   use type Zlib.Status_Code;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Max_Compression_Cache_Items : constant Natural := 64;
   Max_Compression_Cache_Body  : constant Natural := 65_536;
   Max_Compression_Cache_Key   : constant Natural := 2_048;
   Compression_Cache_Shard_Count : constant Positive := 8;
   Max_Compression_Cache_Items_Per_Shard : constant Natural :=
     Max_Compression_Cache_Items / Compression_Cache_Shard_Count;
   Fnv_Base : constant Interfaces.Unsigned_32 := 16#811C9DC5#;
   Fnv_Prime : constant Interfaces.Unsigned_32 := 16#01000193#;
   Alt_Prime : constant Interfaces.Unsigned_32 := 16#7F4A7C15#;

   type Compression_Cache_Entry is record
      Value : Unbounded_String;
   end record;

   package Compression_Cache_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => Compression_Cache_Entry,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   protected type Compression_Cache_Shard is
      procedure Lookup
        (Key   : String;
         Found : out Boolean;
         Value : out Unbounded_String);
      procedure Store
        (Key   : String;
         Value : String);
      procedure Store
        (Key   : String;
         Value : Unbounded_String);
   private
      Entries : Compression_Cache_Maps.Map;
      Eviction_Cursor : Compression_Cache_Maps.Cursor;
   end Compression_Cache_Shard;

   protected body Compression_Cache_Shard is
      procedure Evict_One is
      begin
         if Entries.Is_Empty then
            return;
         end if;

         if not Compression_Cache_Maps.Has_Element (Eviction_Cursor) then
            Eviction_Cursor := Entries.First;
         end if;

         declare
            Key : constant String := Compression_Cache_Maps.Key (Eviction_Cursor);
         begin
            Compression_Cache_Maps.Next (Eviction_Cursor);
            Entries.Delete (Key);
         end;
      end Evict_One;

      procedure Lookup
        (Key   : String;
         Found : out Boolean;
         Value : out Unbounded_String)
      is
         Cursor : Compression_Cache_Maps.Cursor := Entries.Find (Key);
      begin
         Found := Compression_Cache_Maps.Has_Element (Cursor);
         if Found then
            Value := Compression_Cache_Maps.Element (Cursor).Value;
         else
            Value := Null_Unbounded_String;
         end if;
      end Lookup;

      procedure Store
        (Key   : String;
         Value : Unbounded_String)
      is
         Cursor : Compression_Cache_Maps.Cursor;
      begin
         if Key'Length > Max_Compression_Cache_Body + 1
           or else Key'Length > Max_Compression_Cache_Key
         then
            return;
         end if;

         Cursor := Entries.Find (Key);
         if not Compression_Cache_Maps.Has_Element (Cursor) then
            if Entries.Length >= Ada.Containers.Count_Type (Max_Compression_Cache_Items_Per_Shard) then
               Evict_One;
            end if;
         end if;

         Entries.Include
           (Key,
            (Value => Value));
      end Store;

      procedure Store
        (Key   : String;
         Value : String)
      is
      begin
         Store (Key, To_Unbounded_String (Value));
      end Store;
   end Compression_Cache_Shard;

   type Compression_Cache_Shard_Array is
     array (Positive range <>) of Compression_Cache_Shard;

   Compression_Caches : Compression_Cache_Shard_Array (1 .. Compression_Cache_Shard_Count);

   function Compression_Cache_Index (Key : String) return Positive is
   begin
      return
        Positive
          (Natural
             (Ada.Strings.Hash (Key)
              mod Ada.Containers.Hash_Type (Compression_Cache_Shard_Count))
           + 1);
   end Compression_Cache_Index;

   function Header_Key (Name : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Name);
   end Header_Key;

   function Body_Fingerprint (Text : String) return String;

   function Is_Common_Header_Key (Key : String) return Boolean;

   function Fnv1a_Hash (Text : String) return Interfaces.Unsigned_32 is
      Value : Interfaces.Unsigned_32 := Fnv_Base;
   begin
      for Ch of Text loop
         Value := Value xor Interfaces.Unsigned_32 (Character'Pos (Ch));
         Value := Value * Fnv_Prime;
      end loop;

      return Value;
   end Fnv1a_Hash;

   function Alt_Hash (Text : String) return Interfaces.Unsigned_32 is
      Value : Interfaces.Unsigned_32 := 16#1234_5678#;
   begin
      for Ch of Text loop
         Value := Value * Interfaces.Unsigned_32'(33)
           + Interfaces.Unsigned_32 (Character'Pos (Ch))
           + Interfaces.Unsigned_32'(1);
         Value := (Value * Alt_Prime) + Interfaces.Unsigned_32'(1);
      end loop;

      return Value;
   end Alt_Hash;

   function Body_Fingerprint (Text : String) return String is
   begin
      return
        Trim (Interfaces.Unsigned_32'Image (Fnv1a_Hash (Text)), Ada.Strings.Both)
        & ":"
        & Trim (Interfaces.Unsigned_32'Image (Alt_Hash (Text)), Ada.Strings.Both)
        & ":"
        & Trim (Natural'Image (Text'Length), Ada.Strings.Both);
   end Body_Fingerprint;

   procedure Cache_Header
     (Response : in out Response_Type;
      Key      : String;
      Value    : String)
   is
      Text : constant Unbounded_String := To_Unbounded_String (Value);
   begin
      if Key = "content-type" then
         Response.Content_Type_Header := Text;
         Response.Has_Content_Type := True;
      elsif Key = "cache-control" then
         Response.Cache_Control_Header := Text;
         Response.Has_Cache_Control := True;
      elsif Key = "content-encoding" then
         Response.Content_Encoding_Header := Text;
         Response.Has_Content_Encoding := True;
      elsif Key = "vary" then
         Response.Vary_Header := Text;
         Response.Has_Vary := True;
      elsif Key = "connection" then
         Response.Connection_Header := Text;
         Response.Has_Connection := True;
      elsif Key = "set-cookie" then
         Response.Set_Cookie_Header := Text;
         Response.Has_Set_Cookie := True;
      end if;
   end Cache_Header;

   procedure Set_Known_Header
     (Response : in out Response_Type;
      Key      : String;
      Value    : String)
   is
   begin
      if not Is_Common_Header_Key (Key) then
         Response.Headers.Include (Key, Value);
      end if;
      Cache_Header (Response, Key, Value);
      Response.Has_Serialized := False;
      Response.Serialized_Value := Null_Unbounded_String;
   end Set_Known_Header;

   function Has_Cached_Header (Response : Response_Type; Key : String) return Boolean is
   begin
      if Key = "content-type" then
         return Response.Has_Content_Type;
      elsif Key = "cache-control" then
         return Response.Has_Cache_Control;
      elsif Key = "content-encoding" then
         return Response.Has_Content_Encoding;
      elsif Key = "vary" then
         return Response.Has_Vary;
      elsif Key = "connection" then
         return Response.Has_Connection;
      elsif Key = "set-cookie" then
         return Response.Has_Set_Cookie;
      end if;

      return Response.Headers.Contains (Key);
   end Has_Cached_Header;

   function Cached_Header (Response : Response_Type; Key : String) return String is
      Cursor : Header_Maps.Cursor;
   begin
      if Key = "content-type" then
         return To_String (Response.Content_Type_Header);
      elsif Key = "cache-control" then
         return To_String (Response.Cache_Control_Header);
      elsif Key = "content-encoding" then
         return To_String (Response.Content_Encoding_Header);
      elsif Key = "vary" then
         return To_String (Response.Vary_Header);
      elsif Key = "connection" then
         return To_String (Response.Connection_Header);
      elsif Key = "set-cookie" then
         return To_String (Response.Set_Cookie_Header);
      end if;

      Cursor := Response.Headers.Find (Key);
      if Header_Maps.Has_Element (Cursor) then
         return Header_Maps.Element (Cursor);
      end if;

      return "";
   end Cached_Header;

   function Is_Common_Header_Key (Key : String) return Boolean is
   begin
      return Key = "content-type"
        or else Key = "cache-control"
        or else Key = "content-encoding"
        or else Key = "vary"
        or else Key = "connection"
        or else Key = "set-cookie";
   end Is_Common_Header_Key;

   function Canonical_Header_Name (Key : String) return String is
   begin
      if Key = "cache-control" then
         return "Cache-Control";
      elsif Key = "connection" then
         return "Connection";
      elsif Key = "content-security-policy" then
         return "Content-Security-Policy";
      elsif Key = "content-encoding" then
         return "Content-Encoding";
      elsif Key = "content-type" then
         return "Content-Type";
      elsif Key = "location" then
         return "Location";
      elsif Key = "set-cookie" then
         return "Set-Cookie";
      elsif Key = "upgrade" then
         return "Upgrade";
      elsif Key = "vary" then
         return "Vary";
      else
         return Key;
      end if;
   end Canonical_Header_Name;

   function Is_Token_Character (Ch : Character) return Boolean is
   begin
      return (Ch in 'A' .. 'Z')
        or else (Ch in 'a' .. 'z')
        or else (Ch in '0' .. '9')
        or else Ch = '!'
        or else Ch = '#'
        or else Ch = '$'
        or else Ch = '%'
        or else Ch = '&'
        or else Ch = Character'Val (39)
        or else Ch = '*'
        or else Ch = '+'
        or else Ch = '-'
        or else Ch = '.'
        or else Ch = '^'
        or else Ch = '_'
        or else Ch = '`'
        or else Ch = '|'
        or else Ch = '~';
   end Is_Token_Character;

   function Is_Header_Name (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if not Is_Token_Character (Ch) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Header_Name;

   function Is_Header_Value (Value : String) return Boolean is
   begin
      for Ch of Value loop
         if Character'Pos (Ch) < 32
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Header_Value;

   function Is_Vary_Value (Value : String) return Boolean is
      Start_Pos : Natural := Value'First;
      Comma_Pos : Natural;
      Has_Token : Boolean := False;
      Has_Wildcard : Boolean := False;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Index (Value (Start_Pos .. Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
         begin
            if Item'Length = 0 then
               return False;
            end if;

            if Item = "*" then
               Has_Wildcard := True;
            elsif Is_Header_Name (Item) then
               Has_Token := True;
            else
               return False;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return not (Has_Wildcard and then Has_Token);
   end Is_Vary_Value;

   function Is_Token_List_Value (Value : String) return Boolean is
      Start_Pos : Natural := Value'First;
      Comma_Pos : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      loop
         if Start_Pos > Value'Last then
            return False;
         end if;

         Comma_Pos := Index (Value (Start_Pos .. Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
         begin
            if not Is_Header_Name (Item) then
               return False;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return True;
   end Is_Token_List_Value;

   function Is_Token_Value (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if not Is_Token_Character (Ch) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Token_Value;

   function Is_Quoted_Value (Value : String) return Boolean is
      Escaped : Boolean := False;
   begin
      if Value'Length < 2
        or else Value (Value'First) /= '"'
        or else Value (Value'Last) /= '"'
      then
         return False;
      end if;

      for Index_Value in Value'First + 1 .. Value'Last - 1 loop
         if Escaped then
            Escaped := False;
         elsif Value (Index_Value) = '\' then
            Escaped := True;
         elsif Value (Index_Value) = '"'
           or else Character'Pos (Value (Index_Value)) < 32
           or else Character'Pos (Value (Index_Value)) = 127
           or else Character'Pos (Value (Index_Value)) in 128 .. 159
         then
            return False;
         end if;
      end loop;

      return not Escaped;
   end Is_Quoted_Value;

   function Is_Content_Type_Value (Value : String) return Boolean is
      Start_Pos : Natural;
      Semi_Pos  : Natural;
      Slash_Pos : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      Semi_Pos := Index (Value, ";");
      declare
         Media_Range : constant String :=
           Trim
             ((if Semi_Pos = 0 then Value else Value (Value'First .. Semi_Pos - 1)),
              Ada.Strings.Both);
      begin
         Slash_Pos := Index (Media_Range, "/");
         if Slash_Pos = 0
           or else Slash_Pos = Media_Range'First
           or else Slash_Pos = Media_Range'Last
           or else not Is_Token_Value (Media_Range (Media_Range'First .. Slash_Pos - 1))
           or else not Is_Token_Value (Media_Range (Slash_Pos + 1 .. Media_Range'Last))
         then
            return False;
         end if;
      end;

      if Semi_Pos = 0 then
         return True;
      end if;

      Start_Pos := Semi_Pos + 1;
      while Start_Pos <= Value'Last loop
         Semi_Pos := Index (Value (Start_Pos .. Value'Last), ";");
         declare
            Last_Pos : constant Natural :=
              (if Semi_Pos = 0 then Value'Last else Semi_Pos - 1);
            Item     : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Equal_Pos : constant Natural := Index (Item, "=");
         begin
            if Equal_Pos = 0
              or else Equal_Pos = Item'First
              or else Equal_Pos = Item'Last
              or else not Is_Token_Value (Trim (Item (Item'First .. Equal_Pos - 1), Ada.Strings.Both))
            then
               return False;
            end if;

            declare
               Parameter_Value : constant String :=
                 Trim (Item (Equal_Pos + 1 .. Item'Last), Ada.Strings.Both);
            begin
               if not Is_Token_Value (Parameter_Value)
                 and then not Is_Quoted_Value (Parameter_Value)
               then
                  return False;
               end if;
            end;
         end;

         exit when Semi_Pos = 0;
         Start_Pos := Semi_Pos + 1;
      end loop;

      return True;
   end Is_Content_Type_Value;

   function Is_Cache_Control_Value (Value : String) return Boolean is
      Start_Pos : Natural := Value'First;
      Comma_Pos : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      loop
         if Start_Pos > Value'Last then
            return False;
         end if;

         Comma_Pos := Index (Value (Start_Pos .. Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Equal_Pos : constant Natural := Index (Item, "=");
         begin
            if Item'Length = 0 then
               return False;
            end if;

            if Equal_Pos = 0 then
               if not Is_Token_Value (Item) then
                  return False;
               end if;
            elsif Equal_Pos = Item'First or else Equal_Pos = Item'Last then
               return False;
            elsif not Is_Token_Value (Trim (Item (Item'First .. Equal_Pos - 1), Ada.Strings.Both)) then
               return False;
            else
               declare
                  Directive_Value : constant String :=
                    Trim (Item (Equal_Pos + 1 .. Item'Last), Ada.Strings.Both);
               begin
                  if not Is_Token_Value (Directive_Value)
                    and then not Is_Quoted_Value (Directive_Value)
                  then
                     return False;
                  end if;
               end;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return True;
   end Is_Cache_Control_Value;

   procedure Require_Header (Name : String; Value : String) is
   begin
      if not Is_Header_Name (Name) then
         raise Web.Errors.Security_Error with "invalid response header name";
      end if;

      if Header_Key (Name) = "content-length" then
         raise Web.Errors.Security_Error with "content-length is computed by response serialization";
      end if;

      if not Is_Header_Value (Value) then
         raise Web.Errors.Security_Error with "invalid response header value";
      end if;

      if Header_Key (Name) = "vary" and then not Is_Vary_Value (Value) then
         raise Web.Errors.Security_Error with "invalid vary header value";
      end if;

      if Header_Key (Name) = "content-type" and then not Is_Content_Type_Value (Value) then
         raise Web.Errors.Security_Error with "invalid content-type header value";
      end if;

      if Header_Key (Name) = "connection" and then not Is_Token_List_Value (Value) then
         raise Web.Errors.Security_Error with "invalid connection header value";
      end if;

      if Header_Key (Name) = "content-encoding" and then not Is_Token_Value (Trim (Value, Ada.Strings.Both)) then
         raise Web.Errors.Security_Error with "invalid content-encoding header value";
      end if;

      if Header_Key (Name) = "cache-control" and then not Is_Cache_Control_Value (Value) then
         raise Web.Errors.Security_Error with "invalid cache-control header value";
      end if;
   end Require_Header;

   procedure Require_Header_Name (Name : String) is
   begin
      if not Is_Header_Name (Name) then
         raise Web.Errors.Security_Error with "invalid response header name";
      end if;
   end Require_Header_Name;

   function Status_Text (Status_Code : Positive) return String is
   begin
      case Status_Code is
         when 200 =>
            return "OK";
         when 400 =>
            return "Bad Request";
         when 404 =>
            return "Not Found";
         when 406 =>
            return "Not Acceptable";
         when 500 =>
            return "Internal Server Error";
         when 101 =>
            return "Switching Protocols";
         when others =>
            return "OK";
      end case;
   end Status_Text;

   function To_Bytes (Value : String) return Zlib.Byte_Array is
   begin
      if Value'Length = 0 then
         return Zlib.Byte_Array'(1 .. 0 => 0);
      end if;

      declare
         Result : Zlib.Byte_Array (0 .. Value'Length - 1);
      begin
         for Offset in Result'Range loop
            Result (Offset) := Zlib.Byte (Character'Pos (Value (Value'First + Offset)));
         end loop;
         return Result;
      end;
   end To_Bytes;

   function To_String (Value : Zlib.Byte_Array) return String is
      Result : String (1 .. Value'Length);
   begin
      for Offset in Value'Range loop
         Result (Offset - Value'First + Result'First) := Character'Val (Value (Offset));
      end loop;
      return Result;
   end To_String;

   function To_Unbounded (Value : Zlib.Byte_Array) return Unbounded_String is
   begin
      return To_Unbounded_String (To_String (Value));
   end To_Unbounded;

   function Has_Vary_Token (Value : String; Token : String) return Boolean is
      Lower_Value : constant String := Ada.Characters.Handling.To_Lower (Value);
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Lower_Value'First;
      Comma_Pos   : Natural;
   begin
      if Lower_Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Index (Lower_Value (Start_Pos .. Lower_Value'Last), ",");
         declare
            Last_Pos : constant Natural :=
              (if Comma_Pos = 0 then Lower_Value'Last else Comma_Pos - 1);
            Item     : constant String := Trim (Lower_Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
         begin
            if Item = Lower_Token or else Item = "*" then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Has_Vary_Token;

   procedure Ensure_Vary (Response : in out Response_Type; Token : String) is
      Key : constant String := Header_Key ("Vary");
   begin
      if not Is_Header_Name (Token) then
         raise Web.Errors.Security_Error with "invalid vary token";
      end if;

      if Has_Cached_Header (Response, Key) then
         declare
            Existing : constant String := Cached_Header (Response, Key);
         begin
            if not Has_Vary_Token (Existing, Token) then
               Set_Header (Response, "Vary", Existing & ", " & Token);
            end if;
         end;
      else
         Set_Header (Response, "Vary", Token);
      end if;
   end Ensure_Vary;

   function Header_Value (Response : Response_Type; Name : String) return String is
      Key : constant String := Header_Key (Name);
   begin
      return Cached_Header (Response, Key);
   end Header_Value;

   function Starts_With (Value : String; Prefix : String) return Boolean is
   begin
      return Value'Length >= Prefix'Length
        and then Value (Value'First .. Value'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Starts_With_Case_Insensitive (Value : String; Prefix : String) return Boolean is
   begin
      if Value'Length < Prefix'Length then
         return False;
      end if;

      for Offset in 0 .. Prefix'Length - 1 loop
         if Ada.Characters.Handling.To_Lower (Value (Value'First + Offset))
           /= Ada.Characters.Handling.To_Lower (Prefix (Prefix'First + Offset))
         then
            return False;
         end if;
      end loop;

      return True;
   end Starts_With_Case_Insensitive;

   function Starts_With_Case_Insensitive
     (Value  : Unbounded_String;
      Prefix : String) return Boolean
   is
   begin
      if Length (Value) < Prefix'Length then
         return False;
      end if;

      for Offset in 0 .. Prefix'Length - 1 loop
         if Ada.Characters.Handling.To_Lower (Element (Value, Offset + 1))
           /= Ada.Characters.Handling.To_Lower (Prefix (Prefix'First + Offset))
         then
            return False;
         end if;
      end loop;

      return True;
   end Starts_With_Case_Insensitive;

   function Has_Header_Token (Value : String; Token : String) return Boolean is
      Lower_Value : constant String := Ada.Characters.Handling.To_Lower (Value);
      Lower_Token : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start_Pos   : Natural := Lower_Value'First;
      Comma_Pos   : Natural;
   begin
      if Lower_Value'Length = 0 then
         return False;
      end if;

      loop
         Comma_Pos := Index (Lower_Value (Start_Pos .. Lower_Value'Last), ",");
         declare
            Last_Pos      : constant Natural :=
              (if Comma_Pos = 0 then Lower_Value'Last else Comma_Pos - 1);
            Item          : constant String := Trim (Lower_Value (Start_Pos .. Last_Pos), Ada.Strings.Both);
            Parameter_Pos : constant Natural := Index (Item, ";");
            Name          : constant String :=
              (if Parameter_Pos = 0
               then Item
               else Trim (Item (Item'First .. Parameter_Pos - 1), Ada.Strings.Both));
         begin
            if Name = Lower_Token then
               return True;
            end if;
         end;

         exit when Comma_Pos = 0;
         Start_Pos := Comma_Pos + 1;
      end loop;

      return False;
   end Has_Header_Token;

   function Create
     (Status_Code  : Positive;
      Content      : String := "";
      Content_Type : String := "text/plain; charset=utf-8") return Response_Type
   is
      Response : Response_Type :=
        (Status_Code => Status_Code,
         Headers     => Header_Maps.Empty_Map,
         Body_Value  => To_Unbounded_String (Content),
         others      => <>);
   begin
      if Status_Code < 100 or else Status_Code > 599 then
         raise Web.Errors.Security_Error with "invalid response status code";
      end if;

      Set_Header (Response, "Content-Type", Content_Type);
      Set_Header (Response, "Connection", "close");
      return Response;
   end Create;

   function Create_File
     (Status_Code  : Positive;
      Path         : String;
      Size         : Natural;
      Content_Type : String := "application/octet-stream") return Response_Type
   is
      Response : Response_Type :=
        (Status_Code     => Status_Code,
         Headers         => Header_Maps.Empty_Map,
         Mode            => File_Entity,
         File_Path_Value => To_Unbounded_String (Path),
         File_Size_Value => Size,
         others          => <>);
   begin
      if Status_Code < 100 or else Status_Code > 599 then
         raise Web.Errors.Security_Error with "invalid response status code";
      end if;

      if Path'Length = 0 then
         raise Web.Errors.Security_Error with "empty file response path";
      end if;

      Set_Header (Response, "Content-Type", Content_Type);
      Set_Header (Response, "Connection", "close");
      return Response;
   end Create_File;

   function Html (Content : String) return Response_Type is
   begin
      return Create (200, Content, "text/html; charset=utf-8");
   end Html;

   function Text (Content : String) return Response_Type is
   begin
      return Create (200, Content, "text/plain; charset=utf-8");
   end Text;

   function Not_Found return Response_Type is
   begin
      return Create (404, "Not found", "text/plain; charset=utf-8");
   end Not_Found;

   function Bad_Request return Response_Type is
   begin
      return Create (400, "Bad request", "text/plain; charset=utf-8");
   end Bad_Request;

   function Not_Acceptable return Response_Type is
   begin
      return Create (406, "Not acceptable", "text/plain; charset=utf-8");
   end Not_Acceptable;

   function Internal_Server_Error return Response_Type is
   begin
      return Create (500, "Internal server error", "text/plain; charset=utf-8");
   end Internal_Server_Error;

   procedure Set_Header
     (Response : in out Response_Type;
      Name     : String;
      Value    : String)
   is
      Key : constant String := Header_Key (Name);
   begin
      Require_Header (Name, Value);
      if not Is_Common_Header_Key (Key) then
         Response.Headers.Include (Key, Value);
      end if;
      Cache_Header (Response, Key, Value);
      Response.Has_Serialized := False;
      Response.Serialized_Value := Null_Unbounded_String;
   end Set_Header;

   procedure Set_Cache_Key
     (Response : in out Response_Type;
      Key      : String)
   is
   begin
      if Key'Length = 0 or else Key'Length > Max_Compression_Cache_Key then
         raise Web.Errors.Security_Error with "invalid response cache key";
      end if;

      Response.Cache_Key_Value := To_Unbounded_String (Key);
      Response.Has_Cache_Key := True;
   end Set_Cache_Key;

   function Has_Header
     (Response : Response_Type;
      Name     : String) return Boolean
   is
   begin
      Require_Header_Name (Name);
      return Has_Cached_Header (Response, Header_Key (Name));
   end Has_Header;

   function Header
     (Response : Response_Type;
      Name     : String) return String
   is
   begin
      Require_Header_Name (Name);
      return Header_Value (Response, Name);
   end Header;

   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding) return Response_Type
   is
   begin
      return Compressed (Response, Encoding, Natural (Zlib.Default_Level));
   end Compressed;

   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding;
      Level    : Natural) return Response_Type
   is
      Status : Zlib.Status_Code;
      Prefix : constant String :=
        (if Encoding = GZip then "g" else "d") & Trim (Natural'Image (Level), Ada.Strings.Both);
      Level_Value : Zlib.Compression_Level;

      procedure Mark_Encoded (Result : in out Response_Type) is
      begin
         Result.Mode := String_Entity;
         Result.File_Path_Value := Null_Unbounded_String;
         Result.File_Size_Value := 0;
         Result.Has_Serialized := False;
         Result.Serialized_Value := Null_Unbounded_String;
         Set_Known_Header
           (Result,
            "content-encoding",
            (if Encoding = GZip then "gzip" else "deflate"));
         Ensure_Vary (Result, "Accept-Encoding");
      end Mark_Encoded;

   begin
      if Level > 9 then
         raise Web.Errors.Security_Error with "compression level must be in 0 .. 9";
      end if;
      Level_Value := Zlib.Compression_Level (Level);

      if Has_Cached_Header (Response, "content-encoding") then
         raise Web.Errors.Security_Error with "response is already encoded";
      end if;

      if not Is_Compressible (Response) then
         raise Web.Errors.Security_Error with "response is not compressible";
      end if;

      declare
         Body_Text : constant String := Content_Body (Response);
         Body_Cacheable : constant Boolean := Body_Text'Length <= Max_Compression_Cache_Body;
         Stable_Key : constant String :=
           (if Response.Has_Cache_Key
            then Prefix & ":key:" & To_String (Response.Cache_Key_Value)
            else "");
         Cacheable : constant Boolean := Response.Has_Cache_Key or else Body_Cacheable;
         Result    : Response_Type := Response;
      begin
         if Response.Has_Cache_Key then
            declare
               Found : Boolean;
               Value : Unbounded_String;
            begin
               Compression_Caches (Compression_Cache_Index (Stable_Key)).Lookup (Stable_Key, Found, Value);
               if Found then
                  Result.Body_Value := Value;
                  Mark_Encoded (Result);
                  return Result;
               end if;
            end;
         end if;

         if Body_Cacheable then
            declare
               Body_Key : constant String := Prefix & ":body:" & Body_Fingerprint (Body_Text);
               Found : Boolean;
               Value : Unbounded_String;
            begin
               Compression_Caches (Compression_Cache_Index (Body_Key)).Lookup (Body_Key, Found, Value);
               if Found then
                  Result.Body_Value := Value;
                  Mark_Encoded (Result);
                  if Response.Has_Cache_Key then
                     Compression_Caches (Compression_Cache_Index (Stable_Key)).Store (Stable_Key, Value);
                  end if;
                  return Result;
               end if;
            end;
         end if;

         case Encoding is
            when GZip =>
               declare
                  Packed : constant Zlib.Byte_Array :=
                    Zlib.GZip (To_Bytes (Body_Text), Level_Value, Status);
               begin
                  if Status /= Zlib.Ok then
                     raise Web.Errors.Security_Error with
                       "response compression failed: " & Zlib.Status_Image (Status);
                  end if;
                  Result.Body_Value := To_Unbounded (Packed);
               end;
            when Deflate =>
               declare
                  Packed : constant Zlib.Byte_Array :=
                    Zlib.Deflate (To_Bytes (Body_Text), Level_Value, Status);
               begin
                  if Status /= Zlib.Ok then
                     raise Web.Errors.Security_Error with
                       "response compression failed: " & Zlib.Status_Image (Status);
                  end if;
                  Result.Body_Value := To_Unbounded (Packed);
               end;
         end case;

         Mark_Encoded (Result);

         if Cacheable then
            if Response.Has_Cache_Key then
               Compression_Caches (Compression_Cache_Index (Stable_Key)).Store (Stable_Key, Result.Body_Value);
            end if;
            if Body_Cacheable then
               declare
                  Body_Key : constant String := Prefix & ":body:" & Body_Fingerprint (Body_Text);
               begin
                  Compression_Caches (Compression_Cache_Index (Body_Key)).Store (Body_Key, Result.Body_Value);
               end;
            end if;
         end if;
         return Result;
      end;
   end Compressed;

   function Is_Compressible (Response : Response_Type) return Boolean is
   begin
      if Response.Mode = File_Entity then
         return False;
      end if;

      if Has_Cached_Header (Response, "content-encoding") then
         return False;
      end if;

      if Response.Has_Cache_Control
        and then Has_Header_Token (To_String (Response.Cache_Control_Header), "no-transform")
      then
         return False;
      end if;

      return Starts_With_Case_Insensitive (Response.Content_Type_Header, "text/")
        or else Starts_With_Case_Insensitive (Response.Content_Type_Header, "application/javascript")
        or else Starts_With_Case_Insensitive (Response.Content_Type_Header, "application/json")
        or else Starts_With_Case_Insensitive (Response.Content_Type_Header, "application/xml")
        or else Starts_With_Case_Insensitive (Response.Content_Type_Header, "image/svg+xml");
   end Is_Compressible;

   function Status (Response : Response_Type) return Positive is
   begin
      return Response.Status_Code;
   end Status;

   function Content_Body (Response : Response_Type) return String is
   begin
      if Response.Mode = File_Entity then
         return "";
      end if;

      return To_String (Response.Body_Value);
   end Content_Body;

   function Body_Length (Response : Response_Type) return Natural is
   begin
      if Response.Mode = File_Entity then
         return Response.File_Size_Value;
      end if;

      return Natural (Length (Response.Body_Value));
   end Body_Length;

   function Is_File_Body (Response : Response_Type) return Boolean is
   begin
      return Response.Mode = File_Entity;
   end Is_File_Body;

   function File_Body_Path (Response : Response_Type) return String is
   begin
      if Response.Mode = File_Entity then
         return To_String (Response.File_Path_Value);
      end if;

      return "";
   end File_Body_Path;

   function Serialize (Response : Response_Type) return String is
      Status_Prefix    : constant String := "HTTP/1.1 ";
      Length_Prefix    : constant String := "Content-Length: ";
      Header_Separator : constant String := ": ";
      Status_Code_Text : constant String := Trim (Positive'Image (Response.Status_Code), Ada.Strings.Both);
      Body_Size        : constant Natural := Body_Length (Response);
      Body_Size_Text   : constant String := Trim (Natural'Image (Body_Size), Ada.Strings.Both);
      Total_Length     : Natural :=
        Status_Prefix'Length
        + Status_Code_Text'Length
        + 1
        + Status_Text (Response.Status_Code)'Length
        + CRLF'Length
        + Length_Prefix'Length
        + Body_Size_Text'Length
        + CRLF'Length
        + CRLF'Length
        + (if Response.Mode = String_Entity then Length (Response.Body_Value) else 0);

      procedure Add_Header_Length
        (Present : Boolean;
         Name    : String;
         Value   : Unbounded_String)
      is
      begin
         if Present then
            Total_Length :=
              Total_Length
              + Name'Length
              + Header_Separator'Length
              + Length (Value)
              + CRLF'Length;
         end if;
      end Add_Header_Length;
   begin
      if Response.Has_Serialized then
         return To_String (Response.Serialized_Value);
      end if;

      Add_Header_Length (Response.Has_Content_Type, "Content-Type", Response.Content_Type_Header);
      Add_Header_Length (Response.Has_Cache_Control, "Cache-Control", Response.Cache_Control_Header);
      Add_Header_Length
        (Response.Has_Content_Encoding,
         "Content-Encoding",
         Response.Content_Encoding_Header);
      Add_Header_Length (Response.Has_Vary, "Vary", Response.Vary_Header);
      Add_Header_Length (Response.Has_Connection, "Connection", Response.Connection_Header);
      Add_Header_Length (Response.Has_Set_Cookie, "Set-Cookie", Response.Set_Cookie_Header);

      for Cursor in Response.Headers.Iterate loop
         if Header_Maps.Key (Cursor) /= "content-length"
           and then not Is_Common_Header_Key (Header_Maps.Key (Cursor))
         then
            Total_Length :=
              Total_Length
              + Canonical_Header_Name (Header_Maps.Key (Cursor))'Length
              + Header_Separator'Length
              + Header_Maps.Element (Cursor)'Length
              + CRLF'Length;
         end if;
      end loop;

      declare
         Result : String (1 .. Total_Length);
         Cursor : Natural := Result'First;

         procedure Put (Value : String) is
         begin
            if Value'Length > 0 then
               Result (Cursor .. Cursor + Value'Length - 1) := Value;
               Cursor := Cursor + Value'Length;
            end if;
         end Put;

         procedure Put (Value : Unbounded_String) is
         begin
            for Index_Value in 1 .. Length (Value) loop
               Result (Cursor) := Element (Value, Index_Value);
               Cursor := Cursor + 1;
            end loop;
         end Put;

         procedure Put_Header
           (Present : Boolean;
            Name    : String;
            Value   : Unbounded_String)
         is
         begin
            if Present then
               Put (Name);
               Put (Header_Separator);
               Put (Value);
               Put (CRLF);
            end if;
         end Put_Header;
      begin
         Put (Status_Prefix);
         Put (Status_Code_Text);
         Put (" ");
         Put (Status_Text (Response.Status_Code));
         Put (CRLF);

         Put_Header (Response.Has_Content_Type, "Content-Type", Response.Content_Type_Header);
         Put_Header (Response.Has_Cache_Control, "Cache-Control", Response.Cache_Control_Header);
         Put_Header
           (Response.Has_Content_Encoding,
            "Content-Encoding",
            Response.Content_Encoding_Header);
         Put_Header (Response.Has_Vary, "Vary", Response.Vary_Header);
         Put_Header (Response.Has_Connection, "Connection", Response.Connection_Header);
         Put_Header (Response.Has_Set_Cookie, "Set-Cookie", Response.Set_Cookie_Header);

         for Header_Cursor in Response.Headers.Iterate loop
            if Header_Maps.Key (Header_Cursor) /= "content-length"
              and then not Is_Common_Header_Key (Header_Maps.Key (Header_Cursor))
            then
               Put (Canonical_Header_Name (Header_Maps.Key (Header_Cursor)));
               Put (Header_Separator);
               Put (Header_Maps.Element (Header_Cursor));
               Put (CRLF);
            end if;
         end loop;

         Put (Length_Prefix);
         Put (Body_Size_Text);
         Put (CRLF);
         Put (CRLF);
         if Response.Mode = String_Entity then
            Put (Response.Body_Value);
         end if;
         return Result;
      end;
   end Serialize;

   procedure Freeze_Serialized (Response : in out Response_Type) is
   begin
      Response.Serialized_Value := To_Unbounded_String (Serialize (Response));
      Response.Has_Serialized := True;
   end Freeze_Serialized;
end Web.Response;
