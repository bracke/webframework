with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Web.Errors;
with Zlib;

package body Web.Response is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Zlib.Status_Code;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Header_Key (Name : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Name);
   end Header_Key;

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
         if (Character'Pos (Ch) < 32 and then Ch /= Character'Val (9))
           or else Character'Pos (Ch) = 127
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Header_Value;

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
   end Require_Header;

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
      if Response.Headers.Contains (Key) then
         declare
            Existing : constant String := Response.Headers.Element (Key);
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
      if Response.Headers.Contains (Key) then
         return Response.Headers.Element (Key);
      end if;

      return "";
   end Header_Value;

   function Starts_With (Value : String; Prefix : String) return Boolean is
   begin
      return Value'Length >= Prefix'Length
        and then Value (Value'First .. Value'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

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
         Body_Value  => To_Unbounded_String (Content));
   begin
      Require_Header ("Content-Type", Content_Type);
      Response.Headers.Include (Header_Key ("Content-Type"), Content_Type);
      Response.Headers.Include (Header_Key ("Connection"), "close");
      return Response;
   end Create;

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
      Value    : String) is
   begin
      Require_Header (Name, Value);
      Response.Headers.Include (Header_Key (Name), Value);
   end Set_Header;

   function Has_Header
     (Response : Response_Type;
      Name     : String) return Boolean
   is
   begin
      return Response.Headers.Contains (Header_Key (Name));
   end Has_Header;

   function Header
     (Response : Response_Type;
      Name     : String) return String
   is
   begin
      return Header_Value (Response, Name);
   end Header;

   function Compressed
     (Response : Response_Type;
      Encoding : Compression_Encoding) return Response_Type
   is
      Result : Response_Type := Response;
      Status : Zlib.Status_Code;
   begin
      if Response.Headers.Contains ("content-encoding") then
         raise Web.Errors.Security_Error with "response is already encoded";
      end if;

      case Encoding is
         when GZip =>
            declare
               Packed : constant Zlib.Byte_Array :=
                 Zlib.GZip (To_Bytes (Content_Body (Response)), Zlib.Default_Level, Status);
            begin
               if Status /= Zlib.Ok then
                  raise Web.Errors.Security_Error with
                    "response compression failed: " & Zlib.Status_Image (Status);
               end if;
               Result.Body_Value := Ada.Strings.Unbounded.To_Unbounded_String (To_String (Packed));
            end;
            Set_Header (Result, "Content-Encoding", "gzip");
         when Deflate =>
            declare
               Packed : constant Zlib.Byte_Array :=
                 Zlib.Deflate (To_Bytes (Content_Body (Response)), Zlib.Default_Level, Status);
            begin
               if Status /= Zlib.Ok then
                  raise Web.Errors.Security_Error with
                    "response compression failed: " & Zlib.Status_Image (Status);
               end if;
               Result.Body_Value := Ada.Strings.Unbounded.To_Unbounded_String (To_String (Packed));
            end;
            Set_Header (Result, "Content-Encoding", "deflate");
      end case;

      Ensure_Vary (Result, "Accept-Encoding");
      return Result;
   end Compressed;

   function Is_Compressible (Response : Response_Type) return Boolean is
      Content_Type : constant String :=
        Ada.Characters.Handling.To_Lower (Header_Value (Response, "Content-Type"));
   begin
      if Response.Headers.Contains ("content-encoding") then
         return False;
      end if;

      if Has_Header_Token (Header_Value (Response, "Cache-Control"), "no-transform") then
         return False;
      end if;

      return Starts_With (Content_Type, "text/")
        or else Starts_With (Content_Type, "application/javascript")
        or else Starts_With (Content_Type, "application/json")
        or else Starts_With (Content_Type, "application/xml")
        or else Starts_With (Content_Type, "image/svg+xml");
   end Is_Compressible;

   function Status (Response : Response_Type) return Positive is
   begin
      return Response.Status_Code;
   end Status;

   function Content_Body (Response : Response_Type) return String is
   begin
      return To_String (Response.Body_Value);
   end Content_Body;

   function Serialize (Response : Response_Type) return String is
      Result      : Unbounded_String;
      Body_String : constant String := Content_Body (Response);
   begin
      Append
        (Result,
         "HTTP/1.1 "
         & Trim (Positive'Image (Response.Status_Code), Ada.Strings.Both)
         & " "
         & Status_Text (Response.Status_Code)
         & CRLF);

      for Cursor in Response.Headers.Iterate loop
         if Header_Maps.Key (Cursor) /= "content-length" then
            Append
              (Result,
               Canonical_Header_Name (Header_Maps.Key (Cursor))
               & ": "
               & Header_Maps.Element (Cursor)
               & CRLF);
         end if;
      end loop;

      Append
        (Result,
         "Content-Length: "
         & Trim (Natural'Image (Body_String'Length), Ada.Strings.Both)
         & CRLF
         & CRLF
         & Body_String);
      return To_String (Result);
   end Serialize;
end Web.Response;
