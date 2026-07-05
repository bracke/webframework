with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Web.Html;

package Web.Patch is
   type Patch_Kind is
     (Replace_HTML_Kind,
      Set_Text_Kind,
      Set_Attribute_Kind,
      Remove_Attribute_Kind,
      Add_Class_Kind,
      Remove_Class_Kind,
      Set_Value_Kind);

   type Patch is record
      Patch_Type : Patch_Kind;
      Target_Id  : Ada.Strings.Unbounded.Unbounded_String;
      Name_Value : Ada.Strings.Unbounded.Unbounded_String;
      Data_Value : Ada.Strings.Unbounded.Unbounded_String;
      Force_Flag : Boolean := False;
   end record;

   package Patch_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Patch);

   type Patch_List is record
      Items : Patch_Vectors.Vector;
   end record;

   --  Create a replace_html patch.
   --  @param Target DOM id to update.
   --  @param HTML Trusted rendered HTML.
   --  @param Force Replace even when focus is inside the target.
   --  @return Patch value.
   function Replace_HTML
     (Target : String;
      HTML   : Web.Html.Trusted_HTML;
      Force  : Boolean := False) return Patch;

   --  Create a set_text patch.
   --  @param Target DOM id to update.
   --  @param Text Plain text value.
   --  @return Patch value.
   function Set_Text (Target : String; Text : String) return Patch;

   --  Create a set_attr patch.
   --  @param Target DOM id to update.
   --  @param Name Attribute name.
   --  @param Value Attribute value.
   --  @return Patch value.
   function Set_Attribute
     (Target : String;
      Name   : String;
      Value  : String) return Patch;

   --  Create a remove_attr patch.
   --  @param Target DOM id to update.
   --  @param Name Attribute name.
   --  @return Patch value.
   function Remove_Attribute (Target : String; Name : String) return Patch;

   --  Create an add_class patch.
   --  @param Target DOM id to update.
   --  @param Class_Name CSS class to add.
   --  @return Patch value.
   function Add_Class (Target : String; Class_Name : String) return Patch;

   --  Create a remove_class patch.
   --  @param Target DOM id to update.
   --  @param Class_Name CSS class to remove.
   --  @return Patch value.
   function Remove_Class (Target : String; Class_Name : String) return Patch;

   --  Create a set_value patch.
   --  @param Target DOM id to update.
   --  @param Value Form value.
   --  @return Patch value.
   function Set_Value (Target : String; Value : String) return Patch;

   --  Create a patch list containing one patch.
   --  @param Item Patch to add.
   --  @return Patch list.
   function Single (Item : Patch) return Patch_List;

   --  Append a patch to a patch list.
   --  @param List Patch list to update.
   --  @param Item Patch to append.
   --  @return No return value.
   procedure Append (List : in out Patch_List; Item : Patch);

   --  Return the patch kind.
   --  @param Item Patch value.
   --  @return Patch kind.
   function Kind (Item : Patch) return Patch_Kind;

   --  Return the patch target.
   --  @param Item Patch value.
   --  @return Target DOM id.
   function Target (Item : Patch) return String;

   --  Return the patch name field.
   --  @param Item Patch value.
   --  @return Attribute name or class.
   function Name (Item : Patch) return String;

   --  Return the patch value field.
   --  @param Item Patch value.
   --  @return Patch payload.
   function Value (Item : Patch) return String;

   --  Return whether force is enabled.
   --  @param Item Patch value.
   --  @return Force flag.
   function Force (Item : Patch) return Boolean;

end Web.Patch;
