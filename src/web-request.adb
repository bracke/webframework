with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Web.Errors;
with Web.Security;

package body Web.Request is
   use Ada.Strings.Unbounded;

   function Header_Key (Name : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Name);
   end Header_Key;

   function Equals_Case_Insensitive
     (Left  : String;
      Right : String) return Boolean
   is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for Offset in 0 .. Left'Length - 1 loop
         if Ada.Characters.Handling.To_Lower (Left (Left'First + Offset))
           /= Ada.Characters.Handling.To_Lower (Right (Right'First + Offset))
         then
            return False;
         end if;
      end loop;

      return True;
   end Equals_Case_Insensitive;

   function Header_Kind_Of (Name : String) return Header_Kind is
   begin
      case Name'Length is
         when 4 =>
            if Equals_Case_Insensitive (Name, "host") then
               return Host_Header;
            end if;
         when 6 =>
            if Equals_Case_Insensitive (Name, "cookie") then
               return Cookie_Header;
            elsif Equals_Case_Insensitive (Name, "expect") then
               return Expect_Header;
            end if;
         when 7 =>
            if Equals_Case_Insensitive (Name, "upgrade") then
               return Upgrade_Header;
            end if;
         when 10 =>
            if Equals_Case_Insensitive (Name, "connection") then
               return Connection_Header;
            end if;
         when 12 =>
            if Equals_Case_Insensitive (Name, "content-type") then
               return Content_Type_Header;
            end if;
         when 14 =>
            if Equals_Case_Insensitive (Name, "content-length") then
               return Content_Length_Header;
            end if;
         when 15 =>
            if Equals_Case_Insensitive (Name, "accept-encoding") then
               return Accept_Encoding_Header;
            end if;
         when 16 =>
            if Equals_Case_Insensitive (Name, "transfer-encoding") then
               return Transfer_Encoding_Header;
            end if;
         when 17 =>
            if Equals_Case_Insensitive (Name, "content-encoding") then
               return Content_Encoding_Header;
            elsif Equals_Case_Insensitive (Name, "sec-websocket-key") then
               return Sec_WebSocket_Key_Header;
            end if;
         when 21 =>
            if Equals_Case_Insensitive (Name, "sec-websocket-version") then
               return Sec_WebSocket_Version_Header;
            end if;
         when others =>
            null;
      end case;

      return Unknown_Header;
   end Header_Kind_Of;

   procedure Cache_Header
     (Request : in out Request_Type;
      Kind    : Header_Kind;
      Value   : String)
   is
      Text : constant Unbounded_String := To_Unbounded_String (Value);
   begin
      case Kind is
      when Host_Header =>
         Request.Host_Header := Text;
         Request.Has_Host := True;
      when Cookie_Header =>
         Request.Cookie_Header := Text;
         Request.Has_Cookie := True;
      when Connection_Header =>
         Request.Connection_Header := Text;
         Request.Has_Connection := True;
      when Upgrade_Header =>
         Request.Upgrade_Header := Text;
         Request.Has_Upgrade := True;
      when Accept_Encoding_Header =>
         Request.Accept_Encoding_Header := Text;
         Request.Has_Accept_Encoding := True;
      when Content_Length_Header =>
         Request.Content_Length_Header := Text;
         Request.Has_Content_Length := True;
      when Content_Type_Header =>
         Request.Content_Type_Header := Text;
         Request.Has_Content_Type := True;
      when Transfer_Encoding_Header =>
         null;
      when Content_Encoding_Header =>
         null;
      when Expect_Header =>
         null;
      when Sec_WebSocket_Key_Header =>
         Request.Sec_WebSocket_Key_Header := Text;
         Request.Has_Sec_WebSocket_Key := True;
      when Sec_WebSocket_Version_Header =>
         Request.Sec_WebSocket_Version_Header := Text;
         Request.Has_Sec_WebSocket_Version := True;
      when Unknown_Header =>
         null;
      end case;
   end Cache_Header;

   function Is_Cached_Header_Name (Kind : Header_Kind) return Boolean is
   begin
      case Kind is
      when Host_Header =>
         return True;
      when Cookie_Header =>
         return True;
      when Connection_Header =>
         return True;
      when Upgrade_Header =>
         return True;
      when Accept_Encoding_Header =>
         return True;
      when Content_Length_Header =>
         return True;
      when Content_Type_Header =>
         return True;
      when Sec_WebSocket_Key_Header =>
         return True;
      when Sec_WebSocket_Version_Header =>
         return True;
      when Transfer_Encoding_Header =>
         return False;
      when Content_Encoding_Header =>
         return False;
      when Expect_Header =>
         return False;
      when Unknown_Header =>
         return False;
      end case;
   end Is_Cached_Header_Name;

   function Has_Cached_Header
     (Request : Request_Type;
      Kind    : Header_Kind;
      Found   : out Boolean) return Boolean
   is
   begin
      Found := True;
      case Kind is
      when Host_Header =>
         return Request.Has_Host;
      when Cookie_Header =>
         return Request.Has_Cookie;
      when Connection_Header =>
         return Request.Has_Connection;
      when Upgrade_Header =>
         return Request.Has_Upgrade;
      when Accept_Encoding_Header =>
         return Request.Has_Accept_Encoding;
      when Content_Length_Header =>
         return Request.Has_Content_Length;
      when Content_Type_Header =>
         return Request.Has_Content_Type;
      when Transfer_Encoding_Header =>
         return False;
      when Content_Encoding_Header =>
         return False;
      when Expect_Header =>
         return False;
      when Sec_WebSocket_Key_Header =>
         return Request.Has_Sec_WebSocket_Key;
      when Sec_WebSocket_Version_Header =>
         return Request.Has_Sec_WebSocket_Version;
      when Unknown_Header =>
         Found := False;
         return False;
      end case;
   end Has_Cached_Header;

   function Cached_Header
     (Request : Request_Type;
      Kind    : Header_Kind;
      Found   : out Boolean) return String
   is
   begin
      Found := True;
      case Kind is
      when Host_Header =>
         return To_String (Request.Host_Header);
      when Cookie_Header =>
         return To_String (Request.Cookie_Header);
      when Connection_Header =>
         return To_String (Request.Connection_Header);
      when Upgrade_Header =>
         return To_String (Request.Upgrade_Header);
      when Accept_Encoding_Header =>
         return To_String (Request.Accept_Encoding_Header);
      when Content_Length_Header =>
         return To_String (Request.Content_Length_Header);
      when Content_Type_Header =>
         return To_String (Request.Content_Type_Header);
      when Transfer_Encoding_Header =>
         Found := False;
         return "";
      when Content_Encoding_Header =>
         Found := False;
         return "";
      when Expect_Header =>
         Found := False;
         return "";
      when Sec_WebSocket_Key_Header =>
         return To_String (Request.Sec_WebSocket_Key_Header);
      when Sec_WebSocket_Version_Header =>
         return To_String (Request.Sec_WebSocket_Version_Header);
      when Unknown_Header =>
         Found := False;
         return "";
      end case;
   end Cached_Header;

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

   procedure Require_Header_Name (Name : String) is
   begin
      if not Is_Header_Name (Name) then
         raise Web.Errors.Security_Error with "invalid request header name";
      end if;
   end Require_Header_Name;

   procedure Require_Request_Parts
     (Method_Name : String;
      Path_Value  : String;
      Query_Value : String) is
   begin
      if not Is_Header_Name (Method_Name) then
         raise Web.Errors.Security_Error with "invalid request method";
      end if;

      if Path_Value'Length = 0
        or else Path_Value (Path_Value'First) /= '/'
        or else not Web.Security.Is_Safe_Path (Path_Value)
        or else not Web.Security.Is_Safe_Decoded_Path (Path_Value)
      then
         raise Web.Errors.Security_Error with "invalid request path";
      end if;

      for Ch of Query_Value loop
         if Character'Pos (Ch) < 32
           or else Character'Pos (Ch) = 127
           or else Character'Pos (Ch) in 128 .. 159
           or else Ch = '?'
           or else Ch = '#'
         then
            raise Web.Errors.Security_Error with "invalid request query";
         end if;
      end loop;
   end Require_Request_Parts;

   function Create
     (Method_Name : String;
      Path_Value  : String;
      Query_Value : String := "";
      Body_Value  : String := "") return Request_Type
   is
   begin
      Require_Request_Parts (Method_Name, Path_Value, Query_Value);
      return
        (Method_Value => To_Unbounded_String (Method_Name),
         Path_Value   => To_Unbounded_String (Path_Value),
         Query_Value  => To_Unbounded_String (Query_Value),
         Body_Value   => To_Unbounded_String (Body_Value),
         Headers      => Header_Maps.Empty_Map,
         others       => <>);
   end Create;

   procedure Set_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String)
   is
   begin
      Require_Header_Name (Name);

      if not Is_Header_Value (Value) then
         raise Web.Errors.Security_Error with "invalid request header value";
      end if;

      declare
         Kind : constant Header_Kind := Header_Kind_Of (Name);
      begin
         Cache_Header (Request, Kind, Value);
         if not Is_Cached_Header_Name (Kind) then
            Request.Headers.Include (Header_Key (Name), Value);
         end if;
      end;
   end Set_Header;

   function Add_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String) return Boolean
   is
      Kind   : constant Header_Kind := Header_Kind_Of (Name);
      Cached : Boolean;
   begin
      Require_Header_Name (Name);

      if not Is_Header_Value (Value) then
         raise Web.Errors.Security_Error with "invalid request header value";
      end if;

      declare
         Present : constant Boolean := Has_Cached_Header (Request, Kind, Cached);
      begin
         if Cached then
            if Present then
               return False;
            end if;

            Cache_Header (Request, Kind, Value);
            return True;
         end if;
      end;

      declare
         Key : constant String := Header_Key (Name);
      begin
         if Request.Headers.Contains (Key) then
            return False;
         end if;

         Request.Headers.Insert (Key, Value);
         return True;
      end;
   end Add_Header;

   function Add_Validated_Header
     (Request : in out Request_Type;
      Name    : String;
      Value   : String) return Boolean
   is
   begin
      return Add_Validated_Header (Request, Header_Kind_Of (Name), Name, Value);
   end Add_Validated_Header;

   function Add_Validated_Header
     (Request : in out Request_Type;
      Kind    : Header_Kind;
      Name    : String;
      Value   : String) return Boolean
   is
      Cached : Boolean;
   begin
      if Kind /= Unknown_Header then
         declare
            Present : constant Boolean := Has_Cached_Header (Request, Kind, Cached);
         begin
            if Cached then
               if Present then
                  return False;
               end if;

               Cache_Header (Request, Kind, Value);
               return True;
            end if;
         end;
      end if;

      declare
         Key : constant String := Header_Key (Name);
      begin
         if Request.Headers.Contains (Key) then
            return False;
         end if;

         Request.Headers.Insert (Key, Value);
         return True;
      end;
   end Add_Validated_Header;

   function Method (Request : Request_Type) return String is
   begin
      return To_String (Request.Method_Value);
   end Method;

   procedure With_Method (Request : Request_Type) is
   begin
      Process (To_String (Request.Method_Value));
   end With_Method;

   function Method_Is
     (Request     : Request_Type;
      Method_Name : String) return Boolean
   is
   begin
      return Request.Method_Value = Method_Name;
   end Method_Is;

   function Path (Request : Request_Type) return String is
   begin
      return To_String (Request.Path_Value);
   end Path;

   function Path_Is
     (Request    : Request_Type;
      Path_Value : String) return Boolean
   is
   begin
      return Request.Path_Value = Path_Value;
   end Path_Is;

   procedure With_Path (Request : Request_Type) is
   begin
      Process (To_String (Request.Path_Value));
   end With_Path;

   function Query_String (Request : Request_Type) return String is
   begin
      return To_String (Request.Query_Value);
   end Query_String;

   procedure With_Query_String (Request : Request_Type) is
   begin
      Process (To_String (Request.Query_Value));
   end With_Query_String;

   function Has_Header (Request : Request_Type; Name : String) return Boolean is
      Kind   : constant Header_Kind := Header_Kind_Of (Name);
      Cached : Boolean;
   begin
      Require_Header_Name (Name);
      declare
         Result : constant Boolean := Has_Cached_Header (Request, Kind, Cached);
      begin
         if Cached then
            return Result;
         end if;
      end;

      return Request.Headers.Contains (Header_Key (Name));
   end Has_Header;

   function Has_Header
     (Request : Request_Type;
      Kind    : Header_Kind) return Boolean
   is
      Found : Boolean;
   begin
      if not Is_Cached_Header_Name (Kind) then
         return False;
      end if;

      return Has_Cached_Header (Request, Kind, Found);
   end Has_Header;

   function Header (Request : Request_Type; Name : String) return String is
      Kind   : constant Header_Kind := Header_Kind_Of (Name);
      Cached : Boolean;
   begin
      Require_Header_Name (Name);
      declare
         Result : constant String := Cached_Header (Request, Kind, Cached);
      begin
         if Cached then
            return Result;
         end if;
      end;

      declare
         Key : constant String := Header_Key (Name);
      begin
         if Request.Headers.Contains (Key) then
            return Request.Headers.Element (Key);
         end if;
      end;

      return "";
   end Header;

   function Header
     (Request : Request_Type;
      Kind    : Header_Kind) return String
   is
      Found : Boolean;
   begin
      if not Is_Cached_Header_Name (Kind) then
         return "";
      end if;

      return Cached_Header (Request, Kind, Found);
   end Header;

   procedure With_Header
     (Request : Request_Type;
      Name    : String)
   is
   begin
      Process (Header (Request, Name));
   end With_Header;

   function Request_Body (Request : Request_Type) return String is
   begin
      return To_String (Request.Body_Value);
   end Request_Body;

   procedure With_Body (Request : Request_Type) is
   begin
      Process (To_String (Request.Body_Value));
   end With_Body;
end Web.Request;
