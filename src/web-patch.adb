with Ada.Strings.Unbounded;
with Web.Errors;

package body Web.Patch is
   use Ada.Strings.Unbounded;

   procedure Validate_Target (Target : String) is
   begin
      if not Web.Html.Is_Valid_Id (Target) then
         raise Web.Errors.Protocol_Error with "invalid patch target";
      end if;
   end Validate_Target;

   procedure Validate_Name (Name : String) is
   begin
      if not Web.Html.Is_Valid_Id (Name) then
         raise Web.Errors.Protocol_Error with "invalid patch name";
      end if;
   end Validate_Name;

   procedure Validate_Attribute_Name (Name : String) is
   begin
      if Name'Length = 0 then
         raise Web.Errors.Protocol_Error with "invalid attribute name";
      end if;

      for Ch of Name loop
         if Character'Pos (Ch) <= 32
           or else Character'Pos (Ch) = 127
           or else (Character'Pos (Ch) >= 128 and then Character'Pos (Ch) <= 159)
           or else Ch = '"'
           or else Ch = '''
           or else Ch = '<'
           or else Ch = '>'
           or else Ch = '/'
           or else Ch = '='
         then
            raise Web.Errors.Protocol_Error with "invalid attribute name";
         end if;
      end loop;
   end Validate_Attribute_Name;

   function Build
     (Patch_Type : Patch_Kind;
      Target     : String;
      Name       : String := "";
      Value      : String := "";
      Force      : Boolean := False) return Patch
   is
   begin
      Validate_Target (Target);
      if Name'Length > 0 then
         Validate_Name (Name);
      end if;

      return
        (Patch_Type => Patch_Type,
         Target_Id  => To_Unbounded_String (Target),
         Name_Value => To_Unbounded_String (Name),
         Data_Value => To_Unbounded_String (Value),
         Force_Flag => Force);
   end Build;

   procedure Validate_Patch (Item : Patch) is
   begin
      Validate_Target (Target (Item));

      case Kind (Item) is
         when Replace_HTML_Kind | Set_Text_Kind | Set_Value_Kind =>
            null;
         when Set_Attribute_Kind | Remove_Attribute_Kind =>
            Validate_Attribute_Name (Name (Item));
            Validate_Name (Name (Item));
         when Add_Class_Kind | Remove_Class_Kind =>
            if not Web.Html.Is_Valid_Class (Name (Item)) then
               raise Web.Errors.Protocol_Error with "invalid class";
            end if;
      end case;
   end Validate_Patch;

   function Replace_HTML
     (Target : String;
      HTML   : Web.Html.Trusted_HTML;
      Force  : Boolean := False) return Patch
   is
   begin
      return Build (Replace_HTML_Kind, Target, Value => Web.Html.To_String (HTML), Force => Force);
   end Replace_HTML;

   function Set_Text (Target : String; Text : String) return Patch is
   begin
      return Build (Set_Text_Kind, Target, Value => Text);
   end Set_Text;

   function Set_Attribute
     (Target : String;
      Name   : String;
      Value  : String) return Patch
   is
   begin
      Validate_Target (Target);
      Validate_Attribute_Name (Name);
      return Build (Set_Attribute_Kind, Target, Name, Value);
   end Set_Attribute;

   function Remove_Attribute (Target : String; Name : String) return Patch is
   begin
      Validate_Target (Target);
      Validate_Attribute_Name (Name);
      return Build (Remove_Attribute_Kind, Target, Name);
   end Remove_Attribute;

   function Add_Class (Target : String; Class_Name : String) return Patch is
   begin
      if not Web.Html.Is_Valid_Class (Class_Name) then
         raise Web.Errors.Protocol_Error with "invalid class";
      end if;
      return Build (Add_Class_Kind, Target, Class_Name);
   end Add_Class;

   function Remove_Class (Target : String; Class_Name : String) return Patch is
   begin
      if not Web.Html.Is_Valid_Class (Class_Name) then
         raise Web.Errors.Protocol_Error with "invalid class";
      end if;
      return Build (Remove_Class_Kind, Target, Class_Name);
   end Remove_Class;

   function Set_Value (Target : String; Value : String) return Patch is
   begin
      return Build (Set_Value_Kind, Target, Value => Value);
   end Set_Value;

   function Single (Item : Patch) return Patch_List is
      List : Patch_List;
   begin
      Validate_Patch (Item);
      List.Items.Append (Item);
      return List;
   end Single;

   procedure Append (List : in out Patch_List; Item : Patch) is
   begin
      Validate_Patch (Item);
      List.Items.Append (Item);
   end Append;

   function Kind (Item : Patch) return Patch_Kind is
   begin
      return Item.Patch_Type;
   end Kind;

   function Target (Item : Patch) return String is
   begin
      return To_String (Item.Target_Id);
   end Target;

   procedure With_Target (Item : Patch) is
   begin
      Process (To_String (Item.Target_Id));
   end With_Target;

   function Name (Item : Patch) return String is
   begin
      return To_String (Item.Name_Value);
   end Name;

   procedure With_Name (Item : Patch) is
   begin
      Process (To_String (Item.Name_Value));
   end With_Name;

   function Value (Item : Patch) return String is
   begin
      return To_String (Item.Data_Value);
   end Value;

   procedure With_Value (Item : Patch) is
   begin
      Process (To_String (Item.Data_Value));
   end With_Value;

   function Force (Item : Patch) return Boolean is
   begin
      return Item.Force_Flag;
   end Force;
end Web.Patch;
