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

   function Json_Escape (Value : String) return String is
      Result : Unbounded_String;
      Code   : Natural;
   begin
      for Ch of Value loop
         case Ch is
            when '"' =>
               Append (Result, "\""");
            when '\' =>
               Append (Result, "\\");
            when Character'Val (10) =>
               Append (Result, "\n");
            when Character'Val (13) =>
               Append (Result, "\r");
            when Character'Val (9) =>
               Append (Result, "\t");
            when others =>
               Code := Character'Pos (Ch);
               if Code < 32 then
                  Append (Result, "\u00");
                  Append (Result, Hex_Digit (Code / 16));
                  Append (Result, Hex_Digit (Code mod 16));
               else
                  Append (Result, Ch);
               end if;
         end case;
      end loop;
      return To_String (Result);
   end Json_Escape;

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

   function Parse_String (Message : String; Cursor : in out Natural) return String is
      Result : Unbounded_String;
      Code_Point : Natural;
   begin
      Skip_Spaces (Message, Cursor);
      Require (Cursor <= Message'Last and then Message (Cursor) = '"', "expected string");
      Cursor := Cursor + 1;

      while Cursor <= Message'Last loop
         case Message (Cursor) is
            when '"' =>
               Cursor := Cursor + 1;
               return To_String (Result);
            when '\' =>
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
            when Character'Val (0) .. Character'Val (31) =>
               raise Web.Errors.Protocol_Error with "control character in string";
            when others =>
               Append (Result, Message (Cursor));
         end case;
         Cursor := Cursor + 1;
      end loop;

      raise Web.Errors.Protocol_Error with "unterminated string";
   end Parse_String;

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

         declare
            Ignored_Key : constant String := Parse_String (Message, Cursor);
         begin
            null;
         end;
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
            declare
               Ignored : constant String := Parse_String (Message, Cursor);
            begin
               null;
            end;
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

   procedure Parse_Fields
     (Message : String;
      Cursor  : in out Natural;
      Fields  : in out Web.Events.Field_Maps.Map)
   is
      First : Boolean := True;
      Name  : Unbounded_String;
      Value : Unbounded_String;
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

         Name := To_Unbounded_String (Parse_String (Message, Cursor));
         Skip_Spaces (Message, Cursor);
         Require (Cursor <= Message'Last and then Message (Cursor) = ':', "expected fields colon");
         Cursor := Cursor + 1;
         Value := To_Unbounded_String (Parse_String (Message, Cursor));
         if Fields.Contains (To_String (Name)) then
            raise Web.Errors.Protocol_Error with "duplicate field";
         end if;

         if Fields.Length >= Ada.Containers.Count_Type (Web.Events.Max_Field_Count) then
            raise Web.Errors.Protocol_Error with "too many fields";
         end if;

         Fields.Include (To_String (Name), To_String (Value));
         Skip_Spaces (Message, Cursor);
         exit when Cursor <= Message'Last and then Message (Cursor) = '}';
      end loop;

      Require (Cursor <= Message'Last and then Message (Cursor) = '}', "unterminated fields");
      Cursor := Cursor + 1;
   end Parse_Fields;

   function Decode_Client_Message (Message : String) return Web.Events.Event is
      Cursor          : Natural := Message'First;
      First           : Boolean := True;
      Key             : Unbounded_String;
      Message_Type    : Unbounded_String;
      Element         : Unbounded_String;
      Action_Name     : Unbounded_String;
      Version_Value   : Natural := 0;
      Has_Type        : Boolean := False;
      Has_Version     : Boolean := False;
      Has_Id          : Boolean := False;
      Has_Action      : Boolean := False;
      Has_Fields      : Boolean := False;
      Fields          : Web.Events.Field_Maps.Map;
      Result          : Web.Events.Event;

      procedure Require_Action_Fields (Context : String) is
      begin
         if Length (Element) = 0 or else Length (Action_Name) = 0 then
            raise Web.Errors.Protocol_Error with "missing " & Context & " fields";
         end if;
      end Require_Action_Fields;

      procedure Copy_Fields is
      begin
         for Field_Cursor in Fields.Iterate loop
            Web.Events.Set_Field
              (Result,
               Web.Events.Field_Maps.Key (Field_Cursor),
               Web.Events.Field_Maps.Element (Field_Cursor));
         end loop;
      end Copy_Fields;
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

         Key := To_Unbounded_String (Parse_String (Message, Cursor));
         Skip_Spaces (Message, Cursor);
         Require (Cursor <= Message'Last and then Message (Cursor) = ':', "expected root colon");
         Cursor := Cursor + 1;

         if To_String (Key) = "type" then
            Require (not Has_Type, "duplicate message type");
            Message_Type := To_Unbounded_String (Parse_String (Message, Cursor));
            Has_Type := True;
         elsif To_String (Key) = "version" then
            Require (not Has_Version, "duplicate protocol version");
            Version_Value := Parse_Natural (Message, Cursor);
            Has_Version := True;
         elsif To_String (Key) = "id" then
            Require (not Has_Id, "duplicate element id");
            Element := To_Unbounded_String (Parse_String (Message, Cursor));
            Has_Id := True;
         elsif To_String (Key) = "action" then
            Require (not Has_Action, "duplicate action");
            Action_Name := To_Unbounded_String (Parse_String (Message, Cursor));
            Has_Action := True;
         elsif To_String (Key) = "fields" then
            Require (not Has_Fields, "duplicate fields");
            Parse_Fields (Message, Cursor, Fields);
            Has_Fields := True;
         else
            Skip_Value (Message, Cursor);
         end if;

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

      if To_String (Message_Type) = "hello" then
         return Web.Events.Create (Web.Events.Hello_Event);
      elsif To_String (Message_Type) = "click" then
         Require_Action_Fields ("click");
         return Web.Events.Create (Web.Events.Click_Event, To_String (Element), To_String (Action_Name));
      elsif To_String (Message_Type) = "submit" then
         Require_Action_Fields ("submit");
         Result := Web.Events.Create
           (Web.Events.Submit_Event, To_String (Element), To_String (Action_Name));
         Copy_Fields;
         return Result;
      elsif To_String (Message_Type) = "input" then
         Require_Action_Fields ("input");
         return Web.Events.Create (Web.Events.Input_Event, To_String (Element), To_String (Action_Name));
      elsif To_String (Message_Type) = "change" then
         Require_Action_Fields ("change");
         return Web.Events.Create (Web.Events.Change_Event, To_String (Element), To_String (Action_Name));
      end if;

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

   function Encode_Patches (Patches : Web.Patch.Patch_List) return String is
      Result : Unbounded_String := To_Unbounded_String ("{""type"":""patches"",""patches"":[");
      First  : Boolean := True;
   begin
      for Item of Patches.Items loop
         if not First then
            Append (Result, ",");
         end if;
         First := False;

         Append
           (Result,
            "{""op"":"""
            & Patch_Type_Name (Item)
            & """,""target"":"""
            & Json_Escape (Web.Patch.Target (Item))
            & """");

         if Web.Patch.Name (Item)'Length > 0 then
            Append (Result, ",""name"":""" & Json_Escape (Web.Patch.Name (Item)) & """");
         end if;

         if Web.Patch.Value (Item)'Length > 0 then
            Append (Result, ",""value"":""" & Json_Escape (Web.Patch.Value (Item)) & """");
         end if;

         if Web.Patch.Kind (Item) = Web.Patch.Replace_HTML_Kind then
            if Web.Patch.Force (Item) then
               Append (Result, ",""force"":true");
            else
               Append (Result, ",""force"":false");
            end if;
         end if;

         Append (Result, "}");
      end loop;

      Append (Result, "]}");
      return To_String (Result);
   end Encode_Patches;
end Web.Protocol;
