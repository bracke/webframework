with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Web.Html is
   use Ada.Strings.Unbounded;

   function Decimal_Entity (Ch : Character) return String is
   begin
      return "&#" & Ada.Strings.Fixed.Trim (Natural'Image (Character'Pos (Ch)), Ada.Strings.Both) & ";";
   end Decimal_Entity;

   function Is_Control_Character (Ch : Character) return Boolean is
      Position : constant Natural := Character'Pos (Ch);
   begin
      return Position < 32 or else Position = 127 or else Position in 128 .. 159;
   end Is_Control_Character;

   function Escape_Common (Text : String; Attribute_Mode : Boolean) return String is
      Result : Unbounded_String;
   begin
      for Ch of Text loop
         case Ch is
            when '&' =>
               Append (Result, "&amp;");
            when '<' =>
               Append (Result, "&lt;");
            when '>' =>
               Append (Result, "&gt;");
            when '"' =>
               Append (Result, "&quot;");
            when ''' =>
               if Attribute_Mode then
                  Append (Result, "&#39;");
               else
                  Append (Result, "'");
               end if;
            when others =>
               if Is_Control_Character (Ch) then
                  Append (Result, Decimal_Entity (Ch));
               else
                  Append (Result, Ch);
               end if;
         end case;
      end loop;
      return To_String (Result);
   end Escape_Common;

   function Escape_Text (Text : String) return String is
   begin
      return Escape_Common (Text, False);
   end Escape_Text;

   function Escape_Attribute (Value : String) return String is
   begin
      return Escape_Common (Value, True);
   end Escape_Attribute;

   function Trusted (HTML : String) return Trusted_HTML is
   begin
      return (Value => To_Unbounded_String (HTML));
   end Trusted;

   function To_String (HTML : Trusted_HTML) return String is
   begin
      return To_String (HTML.Value);
   end To_String;

   function Is_Name_Character (Ch : Character) return Boolean is
   begin
      return Ch in 'A' .. 'Z'
        or else Ch in 'a' .. 'z'
        or else Ch in '0' .. '9'
        or else Ch = '-'
        or else Ch = '_'
        or else Ch = ':'
        or else Ch = '.';
   end Is_Name_Character;

   function Is_Valid_Id (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;

      for Ch of Value loop
         if not Is_Name_Character (Ch) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Id;

   function Is_Valid_Class (Value : String) return Boolean is
   begin
      return Is_Valid_Id (Value) and then Value (Value'First) /= '.';
   end Is_Valid_Class;
end Web.Html;
