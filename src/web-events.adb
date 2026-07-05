with Ada.Containers;
with Ada.Strings.Unbounded;
with Web.Errors;
with Web.Html;

package body Web.Events is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Is_Action_Name (Value : String) return Boolean is
   begin
      return Web.Html.Is_Valid_Id (Value);
   end Is_Action_Name;

   function Is_Field_Name (Value : String) return Boolean is
   begin
      return Web.Html.Is_Valid_Id (Value);
   end Is_Field_Name;

   procedure Validate_Event
     (Kind       : Event_Kind;
      Element_Id : String;
      Action     : String) is
   begin
      if Kind /= Hello_Event then
         if Element_Id'Length = 0
           or else Element_Id'Length > Max_Element_Id_Length
           or else not Web.Html.Is_Valid_Id (Element_Id)
         then
            raise Web.Errors.Protocol_Error with "invalid event element id";
         end if;

         if Action'Length = 0
           or else Action'Length > Max_Action_Length
           or else not Is_Action_Name (Action)
         then
            raise Web.Errors.Protocol_Error with "invalid event action";
         end if;
      elsif Element_Id'Length > 0 or else Action'Length > 0 then
         raise Web.Errors.Protocol_Error with "hello event must not include action fields";
      end if;
   end Validate_Event;

   procedure Validate_Field (Item : Event; Name : String; Value : String) is
   begin
      if Name'Length = 0
        or else Name'Length > Max_Field_Name_Length
        or else not Is_Field_Name (Name)
      then
         raise Web.Errors.Protocol_Error with "invalid event field name";
      end if;

      if Value'Length > Max_Field_Value_Length then
         raise Web.Errors.Protocol_Error with "event field value too large";
      end if;

      if not Item.Fields.Contains (Name)
        and then Item.Fields.Length >= Ada.Containers.Count_Type (Max_Field_Count)
      then
         raise Web.Errors.Protocol_Error with "too many event fields";
      end if;
   end Validate_Field;

   function Create
     (Kind       : Event_Kind;
      Element_Id : String := "";
      Action     : String := "") return Event
   is
   begin
      Validate_Event (Kind, Element_Id, Action);
      return
        (Event_Type => Kind,
         Element    => To_Unbounded_String (Element_Id),
         Act        => To_Unbounded_String (Action),
         Fields     => Field_Maps.Empty_Map);
   end Create;

   procedure Set_Field
     (Item  : in out Event;
      Name  : String;
      Value : String) is
   begin
      Validate_Field (Item, Name, Value);
      Item.Fields.Include (Name, Value);
   end Set_Field;

   function Kind (Item : Event) return Event_Kind is
   begin
      return Item.Event_Type;
   end Kind;

   function Element_Id (Item : Event) return String is
   begin
      return To_String (Item.Element);
   end Element_Id;

   function Action (Item : Event) return String is
   begin
      return To_String (Item.Act);
   end Action;

   function Has_Field (Item : Event; Name : String) return Boolean is
   begin
      return Item.Fields.Contains (Name);
   end Has_Field;

   function Field (Item : Event; Name : String) return String is
   begin
      if Item.Fields.Contains (Name) then
         return Item.Fields.Element (Name);
      end if;

      return "";
   end Field;
end Web.Events;
