with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Web.Errors;

package body Web.Protocol is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Web.Patch.Patch_Kind;

   function Hex_Digit (Value : Natural) return Character is
      Hex_Characters : constant String := "0123456789ABCDEF";
   begin
      return Hex_Characters (Hex_Characters'First + Value);
   end Hex_Digit;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Web.Errors.Protocol_Error with Message;
      end if;
   end Require;

   procedure Skip_Spaces (Message : String; Cursor : in out Natural) is
   begin
      while Cursor <= Message'Last
        and then Message (Cursor) in ' ' | Character'Val (9) | Character'Val (10) | Character'Val (13)
      loop
         Cursor := Cursor + 1;
      end loop;
   end Skip_Spaces;

   function Hex_Value (Ch : Character) return Natural is
   begin
      case Ch is
         when '0' .. '9' =>
            return Character'Pos (Ch) - Character'Pos ('0');
         when 'a' .. 'f' =>
            return Character'Pos (Ch) - Character'Pos ('a') + 10;
         when 'A' .. 'F' =>
            return Character'Pos (Ch) - Character'Pos ('A') + 10;
         when others =>
            raise Web.Errors.Protocol_Error with "invalid unicode escape";
      end case;
   end Hex_Value;

   procedure Append_UTF8 (Result : in out Unbounded_String; Code_Point : Natural) is
   begin
      if Code_Point in 16#D800# .. 16#DFFF# then
         raise Web.Errors.Protocol_Error with "unicode surrogate escape is not supported";
      end if;

      if Code_Point <= 16#7F# then
         Append (Result, Character'Val (Code_Point));
      elsif Code_Point <= 16#7FF# then
         Append (Result, Character'Val (16#C0# + Code_Point / 64));
         Append (Result, Character'Val (16#80# + Code_Point mod 64));
      elsif Code_Point <= 16#FFFF# then
         Append (Result, Character'Val (16#E0# + Code_Point / 4096));
         Append (Result, Character'Val (16#80# + (Code_Point / 64) mod 64));
         Append (Result, Character'Val (16#80# + Code_Point mod 64));
      else
         raise Web.Errors.Protocol_Error with "unicode escape out of range";
      end if;
   end Append_UTF8;

   function Parse_String_Unbounded
     (Message : String;
      Cursor  : in out Natural) return Unbounded_String
   is
      Start  : Natural;
      Result : Unbounded_String;
      Code_Point : Natural;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '"', "expected string");
      Cursor := Cursor + 1;
      Start := Cursor;

      while Cursor <= Message'Last loop
         case Message (Cursor) is
            when '"' =>
               if Length (Result) = 0 then
                  declare
                     Text : constant String := Message (Start .. Cursor - 1);
                  begin
                     if Text'Length > Web.Events.Max_Field_Value_Length then
                        raise Web.Errors.Protocol_Error with "json string too large";
                     end if;

                     Cursor := Cursor + 1;
                     return To_Unbounded_String (Text);
                  end;
               end if;

               if Start < Cursor then
                  Append (Result, Message (Start .. Cursor - 1));
               end if;

               Cursor := Cursor + 1;
               return Result;
            when '\' =>
               if Start < Cursor then
                  Append (Result, Message (Start .. Cursor - 1));
               end if;
               Cursor := Cursor + 1;
               Require (Cursor <= Message'Last, "unterminated string escape");
               case Message (Cursor) is
                  when '"' =>
                     Append (Result, '"');
                  when '\' =>
                     Append (Result, '\');
                  when '/' =>
                     Append (Result, '/');
                  when 'b' =>
                     Append (Result, Character'Val (8));
                  when 'f' =>
                     Append (Result, Character'Val (12));
                  when 'n' =>
                     Append (Result, Character'Val (10));
                  when 'r' =>
                     Append (Result, Character'Val (13));
                  when 't' =>
                     Append (Result, Character'Val (9));
                  when 'u' =>
                     Require (Cursor + 4 <= Message'Last, "short unicode escape");
                     Code_Point :=
                       Hex_Value (Message (Cursor + 1)) * 4096
                       + Hex_Value (Message (Cursor + 2)) * 256
                       + Hex_Value (Message (Cursor + 3)) * 16
                       + Hex_Value (Message (Cursor + 4));
                     Append_UTF8 (Result, Code_Point);
                     Cursor := Cursor + 4;
                  when others =>
                     raise Web.Errors.Protocol_Error with "invalid string escape";
               end case;
               Start := Cursor + 1;
            when Character'Val (0) .. Character'Val (31) =>
               raise Web.Errors.Protocol_Error with "control character in string";
            when others =>
               null;
         end case;

         if Cursor - Start + Length (Result) > Web.Events.Max_Field_Value_Length then
            raise Web.Errors.Protocol_Error with "json string too large";
         end if;

         Cursor := Cursor + 1;
      end loop;

      raise Web.Errors.Protocol_Error with "unterminated string";
   end Parse_String_Unbounded;

   function Parse_String (Message : String; Cursor : in out Natural) return String is
   begin
      return To_String (Parse_String_Unbounded (Message, Cursor));
   end Parse_String;

   procedure Skip_String (Message : String; Cursor : in out Natural) is
      Code_Point : Natural;
      Count      : Natural := 0;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '"', "expected string");
      Cursor := Cursor + 1;

      while Cursor <= Message'Last loop
         case Message (Cursor) is
            when '"' =>
               Cursor := Cursor + 1;
               return;
            when '\' =>
               Cursor := Cursor + 1;
               Require (Cursor <= Message'Last, "unterminated string escape");
               case Message (Cursor) is
                  when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
                     Count := Count + 1;
                     null;
                  when 'u' =>
                     Require (Cursor + 4 <= Message'Last, "short unicode escape");
                     Code_Point :=
                       Hex_Value (Message (Cursor + 1)) * 4096
                       + Hex_Value (Message (Cursor + 2)) * 256
                       + Hex_Value (Message (Cursor + 3)) * 16
                       + Hex_Value (Message (Cursor + 4));
                     if Code_Point in 16#D800# .. 16#DFFF# then
                        raise Web.Errors.Protocol_Error with "unicode surrogate escape is not supported";
                     end if;
                     if Code_Point <= 16#7F# then
                        Count := Count + 1;
                     elsif Code_Point <= 16#7FF# then
                        Count := Count + 2;
                     else
                        Count := Count + 3;
                     end if;
                     Cursor := Cursor + 4;
                  when others =>
                     raise Web.Errors.Protocol_Error with "invalid string escape";
               end case;
            when Character'Val (0) .. Character'Val (31) =>
               raise Web.Errors.Protocol_Error with "control character in string";
            when others =>
               Count := Count + 1;
         end case;

         if Count > Web.Events.Max_Field_Value_Length then
            raise Web.Errors.Protocol_Error with "json string too large";
         end if;

         Cursor := Cursor + 1;
      end loop;

      raise Web.Errors.Protocol_Error with "unterminated string";
   end Skip_String;

   function Parse_Natural (Message : String; Cursor : in out Natural) return Natural is
      Start : Natural;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) in '0' .. '9', "expected number");
      Start := Cursor;
      while Cursor <= Message'Last and then Message (Cursor) in '0' .. '9' loop
         Cursor := Cursor + 1;
      end loop;

      if Cursor - Start > 1 and then Message (Start) = '0' then
         raise Web.Errors.Protocol_Error with "invalid number";
      end if;

      return Natural'Value (Message (Start .. Cursor - 1));
   exception
      when Constraint_Error =>
         raise Web.Errors.Protocol_Error with "invalid number";
   end Parse_Natural;

   procedure Skip_Value (Message : String; Cursor : in out Natural);

   procedure Skip_Literal (Message : String; Cursor : in out Natural; Literal : String) is
   begin
      Require
        (Cursor + Literal'Length - 1 <= Message'Last
         and then Message (Cursor .. Cursor + Literal'Length - 1) = Literal,
         "invalid literal");
      Cursor := Cursor + Literal'Length;
   end Skip_Literal;

   procedure Skip_Array (Message : String; Cursor : in out Natural) is
      First : Boolean := True;
   begin
      Require (Cursor <= Message'Last and then Message (Cursor) = '[', "expected array");
      Cursor := Cursor + 1;
      Skip_Spaces (Message, Cursor);
      if Cursor <= Message'Last and then Message (Cursor) = ']' then
         Cursor := Cursor + 1;
         return;
      end if;

      loop
         if First then
            First := False;
         else
            Require (Cursor <= Message'Last and then Message (Cursor) = ',', "expected comma");
            Cursor := Cursor + 1;
         end if;

         Skip_Value (Message, Cursor);
         Skip_Spaces (Message, Cursor);
         exit when Cursor <= Message'Last and then Message (Cursor) = ']';
      end loop;

      Require (Cursor <= Message'Last and then Message (Cursor) = ']', "unterminated array");
      Cursor := Cursor + 1;
   end Skip_Array;

   procedure Skip_Object (Message : String; Cursor : in out Natural) is
      First : Boolean := True;
   begin
      Require (Cursor <= Message'Last and then Message (Cursor) = '{', "expected object");
      Cursor := Cursor + 1;
      Skip_Spaces (Message, Cursor);
      if Cursor <= Message'Last and then Message (Cursor) = '}' then
         Cursor := Cursor + 1;
         return;
      end if;

      loop
         if First then
            First := False;
         else
            Require (Cursor <= Message'Last and then Message (Cursor) = ',', "expected comma");
            Cursor := Cursor + 1;
         end if;

         Skip_String (Message, Cursor);
         Skip_Spaces (Message, Cursor);
         Require (Cursor <= Message'Last and then Message (Cursor) = ':', "expected colon");
         Cursor := Cursor + 1;
         Skip_Value (Message, Cursor);
         Skip_Spaces (Message, Cursor);
         exit when Cursor <= Message'Last and then Message (Cursor) = '}';
      end loop;

      Require (Cursor <= Message'Last and then Message (Cursor) = '}', "unterminated object");
      Cursor := Cursor + 1;
   end Skip_Object;

   procedure Skip_Value (Message : String; Cursor : in out Natural) is
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last, "expected value");
      case Message (Cursor) is
         when '"' =>
            Skip_String (Message, Cursor);
         when '{' =>
            Skip_Object (Message, Cursor);
         when '[' =>
            Skip_Array (Message, Cursor);
         when 't' =>
            Skip_Literal (Message, Cursor, "true");
         when 'f' =>
            Skip_Literal (Message, Cursor, "false");
         when 'n' =>
            Skip_Literal (Message, Cursor, "null");
         when '-' | '0' .. '9' =>
            if Message (Cursor) = '-' then
               Cursor := Cursor + 1;
            end if;
            declare
               Ignored : constant Natural := Parse_Natural (Message, Cursor);
            begin
               null;
            end;
         when others =>
            raise Web.Errors.Protocol_Error with "invalid value";
      end case;
   end Skip_Value;

   type Root_Key_Kind is (Type_Key, Version_Key, Id_Key, Action_Key, Fields_Key, Unknown_Key);
   type Client_Message_Kind is
     (Hello_Message, Click_Message, Submit_Message, Input_Message, Change_Message, Unknown_Message);

   function Root_Key_From_Text (Text : String) return Root_Key_Kind is
   begin
      if Text = "type" then
         return Type_Key;
      elsif Text = "version" then
         return Version_Key;
      elsif Text = "id" then
         return Id_Key;
      elsif Text = "action" then
         return Action_Key;
      elsif Text = "fields" then
         return Fields_Key;
      end if;

      return Unknown_Key;
   end Root_Key_From_Text;

   function Message_Kind_From_Text (Text : String) return Client_Message_Kind is
   begin
      if Text = "hello" then
         return Hello_Message;
      elsif Text = "click" then
         return Click_Message;
      elsif Text = "submit" then
         return Submit_Message;
      elsif Text = "input" then
         return Input_Message;
      elsif Text = "change" then
         return Change_Message;
      end if;

      return Unknown_Message;
   end Message_Kind_From_Text;

   function Match_Message_Kind
     (Message : String;
      Start   : Natural;
      Length  : Natural) return Client_Message_Kind
   is
   begin
      if Length = 5 then
         if Message (Start) = 'h'
           and then Message (Start + 1) = 'e'
           and then Message (Start + 2) = 'l'
           and then Message (Start + 3) = 'l'
           and then Message (Start + 4) = 'o'
         then
            return Hello_Message;
         elsif Message (Start) = 'c'
           and then Message (Start + 1) = 'l'
           and then Message (Start + 2) = 'i'
           and then Message (Start + 3) = 'c'
           and then Message (Start + 4) = 'k'
         then
            return Click_Message;
         elsif Message (Start) = 'i'
           and then Message (Start + 1) = 'n'
           and then Message (Start + 2) = 'p'
           and then Message (Start + 3) = 'u'
           and then Message (Start + 4) = 't'
         then
            return Input_Message;
         end if;
      elsif Length = 6 then
         if Message (Start) = 's'
           and then Message (Start + 1) = 'u'
           and then Message (Start + 2) = 'b'
           and then Message (Start + 3) = 'm'
           and then Message (Start + 4) = 'i'
           and then Message (Start + 5) = 't'
         then
            return Submit_Message;
         elsif Message (Start) = 'c'
           and then Message (Start + 1) = 'h'
           and then Message (Start + 2) = 'a'
           and then Message (Start + 3) = 'n'
           and then Message (Start + 4) = 'g'
           and then Message (Start + 5) = 'e'
         then
            return Change_Message;
         end if;
      end if;

      return Unknown_Message;
   end Match_Message_Kind;

   function Match_Root_Key
     (Message : String;
      Start   : Natural;
      Length  : Natural) return Root_Key_Kind
   is
   begin
      if Length = 4 then
         if Message (Start) = 't'
           and then Message (Start + 1) = 'y'
           and then Message (Start + 2) = 'p'
           and then Message (Start + 3) = 'e'
         then
            return Type_Key;
         end if;
      elsif Length = 7 then
         if Message (Start) = 'v'
           and then Message (Start + 1) = 'e'
           and then Message (Start + 2) = 'r'
           and then Message (Start + 3) = 's'
           and then Message (Start + 4) = 'i'
           and then Message (Start + 5) = 'o'
           and then Message (Start + 6) = 'n'
         then
            return Version_Key;
         end if;
      elsif Length = 2 then
         if Message (Start) = 'i' and then Message (Start + 1) = 'd' then
            return Id_Key;
         end if;
      elsif Length = 6 then
         if Message (Start) = 'a'
           and then Message (Start + 1) = 'c'
           and then Message (Start + 2) = 't'
           and then Message (Start + 3) = 'i'
           and then Message (Start + 4) = 'o'
           and then Message (Start + 5) = 'n'
         then
            return Action_Key;
         elsif Message (Start) = 'f'
           and then Message (Start + 1) = 'i'
           and then Message (Start + 2) = 'e'
           and then Message (Start + 3) = 'l'
           and then Message (Start + 4) = 'd'
           and then Message (Start + 5) = 's'
         then
            return Fields_Key;
         end if;
      end if;

      return Unknown_Key;
   end Match_Root_Key;

   function Parse_Message_Kind
     (Message : String;
      Cursor  : in out Natural) return Client_Message_Kind
   is
      Start  : Natural;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '"', "expected string");
      Cursor := Cursor + 1;
      Start := Cursor;

      while Cursor <= Message'Last loop
         case Message (Cursor) is
            when '"' =>
               declare
                  Token : constant Client_Message_Kind :=
                    Match_Message_Kind (Message, Start, Cursor - Start);
               begin
                  Cursor := Cursor + 1;
                  return Token;
               end;
            when '\' =>
               Cursor := Start - 1;
               return Message_Kind_From_Text (Parse_String (Message, Cursor));
            when Character'Val (0) .. Character'Val (31) =>
               raise Web.Errors.Protocol_Error with "control character in string";
            when others =>
               null;
         end case;

         if Cursor - Start > Web.Events.Max_Field_Value_Length then
            raise Web.Errors.Protocol_Error with "json string too large";
         end if;

         Cursor := Cursor + 1;
      end loop;

      raise Web.Errors.Protocol_Error with "unterminated string";
   end Parse_Message_Kind;

   function Parse_Root_Key
     (Message : String;
      Cursor  : in out Natural) return Root_Key_Kind
   is
      Start  : Natural;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '"', "expected string");
      Cursor := Cursor + 1;
      Start := Cursor;

      while Cursor <= Message'Last loop
         case Message (Cursor) is
            when '"' =>
               declare
                  Token : constant Root_Key_Kind :=
                    Match_Root_Key (Message, Start, Cursor - Start);
               begin
                  Cursor := Cursor + 1;
                  return Token;
               end;
            when '\' =>
               Cursor := Start - 1;
               return Root_Key_From_Text (Parse_String (Message, Cursor));
            when Character'Val (0) .. Character'Val (31) =>
               raise Web.Errors.Protocol_Error with "control character in string";
            when others =>
               null;
         end case;

         if Cursor - Start > Web.Events.Max_Field_Name_Length then
            raise Web.Errors.Protocol_Error with "json string too large";
         end if;

         Cursor := Cursor + 1;
      end loop;

      raise Web.Errors.Protocol_Error with "unterminated string";
   end Parse_Root_Key;

   procedure Parse_Fields
     (Message : String;
      Cursor  : in out Natural;
      Fields  : in out Web.Events.Field_Maps.Map)
   is
      First : Boolean := True;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '{', "fields must be object");
      Cursor := Cursor + 1;
      Skip_Spaces (Message, Cursor);

      if Cursor <= Message'Last and then Message (Cursor) = '}' then
         Cursor := Cursor + 1;
         return;
      end if;

      loop
         if First then
            First := False;
         else
            Require (Cursor <= Message'Last and then Message (Cursor) = ',', "expected fields comma");
            Cursor := Cursor + 1;
         end if;

         declare
            Name_Text : constant String := Parse_String (Message, Cursor);
         begin
            Skip_Spaces (Message, Cursor);
            Require (Cursor <= Message'Last and then Message (Cursor) = ':', "expected fields colon");
            Cursor := Cursor + 1;

            if Fields.Length >= Ada.Containers.Count_Type (Web.Events.Max_Field_Count) then
               raise Web.Errors.Protocol_Error with "too many fields";
            end if;

            declare
               Value_Text : constant String := Parse_String (Message, Cursor);
               Position   : Web.Events.Field_Maps.Cursor;
               Inserted   : Boolean;
            begin
               Web.Events.Field_Maps.Insert
                 (Container => Fields,
                  Key       => Name_Text,
                  New_Item  => Value_Text,
                  Position  => Position,
                  Inserted  => Inserted);
               if not Inserted then
                  raise Web.Errors.Protocol_Error with "duplicate field";
               end if;
            end;
         end;
         Skip_Spaces (Message, Cursor);
         exit when Cursor <= Message'Last and then Message (Cursor) = '}';
      end loop;

      Require (Cursor <= Message'Last and then Message (Cursor) = '}', "unterminated fields");
      Cursor := Cursor + 1;
   end Parse_Fields;

   function Decode_Client_Message (Message : String) return Web.Events.Event is
      Cursor          : Natural := Message'First;
      First           : Boolean := True;
      Message_Type    : Client_Message_Kind := Unknown_Message;
      Element         : Unbounded_String;
      Action_Name     : Unbounded_String;
      Version_Value   : Natural := 0;
      Has_Type        : Boolean := False;
      Has_Version     : Boolean := False;
      Has_Id          : Boolean := False;
      Has_Action      : Boolean := False;
      Has_Fields      : Boolean := False;
      Fields          : Web.Events.Field_Maps.Map;

      procedure Require_Action_Fields (Context : String) is
      begin
         if Length (Element) = 0 or else Length (Action_Name) = 0 then
            raise Web.Errors.Protocol_Error with "missing " & Context & " fields";
         end if;
      end Require_Action_Fields;

   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '{', "message must be object");
      Cursor := Cursor + 1;
      Skip_Spaces (Message, Cursor);

      if Cursor <= Message'Last and then Message (Cursor) = '}' then
         raise Web.Errors.Protocol_Error with "empty message";
      end if;

      loop
         if First then
            First := False;
         else
            Require (Cursor <= Message'Last and then Message (Cursor) = ',', "expected root comma");
            Cursor := Cursor + 1;
         end if;

         declare
            Key_Value : constant Root_Key_Kind := Parse_Root_Key (Message, Cursor);
         begin
            Skip_Spaces (Message, Cursor);
            Require (Cursor <= Message'Last and then Message (Cursor) = ':', "expected root colon");
            Cursor := Cursor + 1;

            if Key_Value = Type_Key then
               Require (not Has_Type, "duplicate message type");
               Message_Type := Parse_Message_Kind (Message, Cursor);
               Has_Type := True;
            elsif Key_Value = Version_Key then
               Require (not Has_Version, "duplicate protocol version");
               Version_Value := Parse_Natural (Message, Cursor);
               Has_Version := True;
            elsif Key_Value = Id_Key then
               Require (not Has_Id, "duplicate element id");
               Element := Parse_String_Unbounded (Message, Cursor);
               Has_Id := True;
            elsif Key_Value = Action_Key then
               Require (not Has_Action, "duplicate action");
               Action_Name := Parse_String_Unbounded (Message, Cursor);
               Has_Action := True;
            elsif Key_Value = Fields_Key then
               Require (not Has_Fields, "duplicate fields");
               Parse_Fields (Message, Cursor, Fields);
               Has_Fields := True;
            else
               Skip_Value (Message, Cursor);
            end if;
         end;

         Skip_Spaces (Message, Cursor);
         exit when Cursor <= Message'Last and then Message (Cursor) = '}';
      end loop;

      Require (Cursor <= Message'Last and then Message (Cursor) = '}', "unterminated message");
      Cursor := Cursor + 1;
      Skip_Spaces (Message, Cursor);
      Require (Cursor > Message'Last, "trailing data after message");

      if not Has_Type then
         raise Web.Errors.Protocol_Error with "missing message type";
      end if;

      if not Has_Version or else Version_Value /= Protocol_Version then
         raise Web.Errors.Protocol_Error with "unsupported protocol version";
      end if;

      case Message_Type is
         when Hello_Message =>
            return
              Web.Events.Create
                (Web.Events.Hello_Event,
                 Null_Unbounded_String,
                 Null_Unbounded_String,
                 Web.Events.Field_Maps.Empty_Map);
         when Click_Message =>
            Require_Action_Fields ("click");
            return
              Web.Events.Create
                (Web.Events.Click_Event,
                 Element,
                 Action_Name,
                 Web.Events.Field_Maps.Empty_Map);
         when Submit_Message =>
            Require_Action_Fields ("submit");
            return Web.Events.Create (Web.Events.Submit_Event, Element, Action_Name, Fields);
         when Input_Message =>
            Require_Action_Fields ("input");
            return
              Web.Events.Create
                (Web.Events.Input_Event,
                 Element,
                 Action_Name,
                 Web.Events.Field_Maps.Empty_Map);
         when Change_Message =>
            Require_Action_Fields ("change");
            return
              Web.Events.Create
                (Web.Events.Change_Event,
                 Element,
                 Action_Name,
                 Web.Events.Field_Maps.Empty_Map);
         when Unknown_Message =>
            null;
      end case;

      raise Web.Errors.Protocol_Error with "unknown message type";
   end Decode_Client_Message;

   function Patch_Type_Name (Item : Web.Patch.Patch) return String is
   begin
      case Web.Patch.Kind (Item) is
         when Web.Patch.Replace_HTML_Kind =>
            return "replace_html";
         when Web.Patch.Set_Text_Kind =>
            return "set_text";
         when Web.Patch.Set_Attribute_Kind =>
            return "set_attr";
         when Web.Patch.Remove_Attribute_Kind =>
            return "remove_attr";
         when Web.Patch.Add_Class_Kind =>
            return "add_class";
         when Web.Patch.Remove_Class_Kind =>
            return "remove_class";
         when Web.Patch.Set_Value_Kind =>
            return "set_value";
      end case;
   end Patch_Type_Name;

   function Is_Name_Character (Value : Character) return Boolean is
   begin
      return Value in 'A' .. 'Z'
        or else Value in 'a' .. 'z'
        or else Value in '0' .. '9'
        or else Value = '-'
        or else Value = '_'
        or else Value = ':'
        or else Value = '.';
   end Is_Name_Character;

   function Is_Valid_Id (Value : Unbounded_String) return Boolean is
   begin
      if Length (Value) = 0 then
         return False;
      end if;

      for Index_Value in 1 .. Length (Value) loop
         if not Is_Name_Character (Element (Value, Index_Value)) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Id;

   function Escaped_Length_And_Id_Validity
     (Value : Unbounded_String;
      Valid : out Boolean) return Natural
   is
      Code   : Natural;
      Result : Natural := 0;
      Ch     : Character;
   begin
      Valid := Length (Value) > 0;

      for Index_Value in 1 .. Length (Value) loop
         Ch := Element (Value, Index_Value);
         if not Is_Name_Character (Ch) then
            Valid := False;
         end if;

         Code := Character'Pos (Ch);
         case Ch is
            when '"' | '\' | Character'Val (10) | Character'Val (13) | Character'Val (9) =>
               Result := Result + 2;
            when others =>
               if Code < 32 or else Code = 127 or else Code in 128 .. 159 then
                  Result := Result + 6;
               else
                  Result := Result + 1;
               end if;
         end case;
      end loop;

      return Result;
   end Escaped_Length_And_Id_Validity;

   function Escaped_Length (Value : Unbounded_String) return Natural is
      Code   : Natural;
      Result : Natural := 0;
   begin
      for Index_Value in 1 .. Length (Value) loop
         declare
            Ch : constant Character := Element (Value, Index_Value);
         begin
            Code := Character'Pos (Ch);
            case Ch is
               when '"' | '\' | Character'Val (10) | Character'Val (13) | Character'Val (9) =>
                  Result := Result + 2;
               when others =>
                  if Code < 32 or else Code = 127 or else Code in 128 .. 159 then
                     Result := Result + 6;
                  else
                     Result := Result + 1;
                  end if;
            end case;
         end;
      end loop;

      return Result;
   end Escaped_Length;

   function Is_Valid_Attribute_Name (Value : Unbounded_String) return Boolean is
      Ch : Character;
   begin
      if Length (Value) = 0 then
         return False;
      end if;

      for Index_Value in 1 .. Length (Value) loop
         Ch := Element (Value, Index_Value);
         if Character'Pos (Ch) <= 32
           or else Character'Pos (Ch) = 127
           or else Character'Pos (Ch) in 128 .. 159
           or else Ch = '"'
           or else Ch = '''
           or else Ch = '<'
           or else Ch = '>'
           or else Ch = '/'
           or else Ch = '='
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Attribute_Name;

   function Patch_Type_Name_Length (Item : Web.Patch.Patch) return Natural is
   begin
      case Web.Patch.Kind (Item) is
         when Web.Patch.Replace_HTML_Kind =>
            return 12;
         when Web.Patch.Set_Text_Kind =>
            return 8;
         when Web.Patch.Set_Attribute_Kind =>
            return 8;
         when Web.Patch.Remove_Attribute_Kind =>
            return 11;
         when Web.Patch.Add_Class_Kind =>
            return 9;
         when Web.Patch.Remove_Class_Kind =>
            return 12;
         when Web.Patch.Set_Value_Kind =>
            return 9;
      end case;
   end Patch_Type_Name_Length;

   function Validated_Patch_Length (Item : Web.Patch.Patch) return Natural is
      Kind_Value : constant Web.Patch.Patch_Kind := Web.Patch.Kind (Item);
      Target_Valid : Boolean;
      Name_Valid   : Boolean;
      Target_Escaped_Length : constant Natural :=
        Escaped_Length_And_Id_Validity (Item.Target_Id, Target_Valid);
      Name_Escaped_Length : Natural := 0;
      Result : Natural :=
        8 + Patch_Type_Name_Length (Item)
        + 6 + 6 + Target_Escaped_Length
        + 1;
   begin
      if not Target_Valid then
         raise Web.Errors.Protocol_Error with "invalid patch target";
      end if;

      if Length (Item.Name_Value) > 0 then
         Name_Escaped_Length := Escaped_Length_And_Id_Validity (Item.Name_Value, Name_Valid);
      else
         Name_Valid := False;
      end if;

      case Kind_Value is
         when Web.Patch.Replace_HTML_Kind | Web.Patch.Set_Text_Kind | Web.Patch.Set_Value_Kind =>
            null;
         when Web.Patch.Set_Attribute_Kind | Web.Patch.Remove_Attribute_Kind =>
            if not Name_Valid or else not Is_Valid_Attribute_Name (Item.Name_Value) then
               raise Web.Errors.Protocol_Error with "invalid patch name";
            end if;
         when Web.Patch.Add_Class_Kind =>
            if not Name_Valid or else Element (Item.Name_Value, 1) = '.' then
               raise Web.Errors.Protocol_Error with "invalid class";
            end if;
         when Web.Patch.Remove_Class_Kind =>
            if not Name_Valid or else Element (Item.Name_Value, 1) = '.' then
               raise Web.Errors.Protocol_Error with "invalid class";
            end if;
      end case;

      if Length (Item.Name_Value) > 0 then
         Result := Result + 6 + 4 + Name_Escaped_Length;
      end if;

      if Length (Item.Data_Value) > 0 then
         Result := Result + 6 + 5 + Escaped_Length (Item.Data_Value);
      end if;

      if Kind_Value = Web.Patch.Replace_HTML_Kind then
         Result := Result + (if Web.Patch.Force (Item) then 13 else 14);
      end if;

      return Result;
   end Validated_Patch_Length;

   function Encode_Patches (Patches : Web.Patch.Patch_List) return String is
      Prefix : constant String := "{""type"":""patches"",""patches"":[";
      Suffix : constant String := "]}";

      Total_Length : Natural := Prefix'Length + Suffix'Length;
      First        : Boolean := True;
   begin
      for Item of Patches.Items loop
         if not First then
            Total_Length := Total_Length + 1;
         end if;
         First := False;
         Total_Length := Total_Length + Validated_Patch_Length (Item);
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

         procedure Put (Value : Character) is
         begin
            Result (Cursor) := Value;
            Cursor := Cursor + 1;
         end Put;

         procedure Put_Escaped (Value : Unbounded_String) is
            Code : Natural;
         begin
            for Index_Value in 1 .. Length (Value) loop
               declare
                  Ch : constant Character := Element (Value, Index_Value);
               begin
                  case Ch is
                     when '"' =>
                        Put ("\""");
                     when '\' =>
                        Put ("\\");
                     when Character'Val (10) =>
                        Put ("\n");
                     when Character'Val (13) =>
                        Put ("\r");
                     when Character'Val (9) =>
                        Put ("\t");
                     when others =>
                        Code := Character'Pos (Ch);
                        if Code < 32 or else Code = 127 or else Code in 128 .. 159 then
                           Put ("\u00");
                           Put (Hex_Digit (Code / 16));
                           Put (Hex_Digit (Code mod 16));
                        else
                           Put (Ch);
                        end if;
                  end case;
               end;
            end loop;
         end Put_Escaped;

         procedure Put_String_Member (Name : String; Value : Unbounded_String) is
         begin
            Put (",""");
            Put (Name);
            Put (""":""");
            Put_Escaped (Value);
            Put ("""");
         end Put_String_Member;

         procedure Put_Patch (Item : Web.Patch.Patch) is
            Kind_Value : constant Web.Patch.Patch_Kind := Web.Patch.Kind (Item);
         begin
            Put ("{""op"":""");
            Put (Patch_Type_Name (Item));
            Put ("""");
            Put_String_Member ("target", Item.Target_Id);

            if Length (Item.Name_Value) > 0 then
               Put_String_Member ("name", Item.Name_Value);
            end if;

            if Length (Item.Data_Value) > 0 then
               Put_String_Member ("value", Item.Data_Value);
            end if;

            if Kind_Value = Web.Patch.Replace_HTML_Kind then
               Put ((if Web.Patch.Force (Item) then ",""force"":true" else ",""force"":false"));
            end if;

            Put ("}");
         end Put_Patch;
      begin
         Put (Prefix);
         First := True;
         for Item of Patches.Items loop
            if not First then
               Put (",");
            end if;
            First := False;
            Put_Patch (Item);
         end loop;
         Put (Suffix);
         return Result;
      end;
   end Encode_Patches;
end Web.Protocol;
