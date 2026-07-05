with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded;

package Web.Events is
   type Event_Kind is (Hello_Event, Click_Event, Submit_Event, Input_Event, Change_Event);

   Max_Element_Id_Length : constant Natural := 128;
   Max_Action_Length     : constant Natural := 128;
   Max_Field_Name_Length : constant Natural := 128;
   Max_Field_Value_Length : constant Natural := 8_192;
   Max_Field_Count       : constant Natural := 64;

   package Field_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => String);

   type Event is private;

   --  Create a browser event.
   --  @param Kind Event kind.
   --  @param Element_Id Source element id.
   --  @param Action Handler action.
   --  @return Event value.
   function Create
     (Kind       : Event_Kind;
      Element_Id : String := "";
      Action     : String := "") return Event;

   --  Add a form field to an event.
   --  @param Item Event to update.
   --  @param Name Field name.
   --  @param Value Field value.
   --  @return No return value.
   procedure Set_Field
     (Item  : in out Event;
      Name  : String;
      Value : String);

   --  Return the event kind.
   --  @param Item Event value.
   --  @return Event kind.
   function Kind (Item : Event) return Event_Kind;

   --  Return the source element id.
   --  @param Item Event value.
   --  @return Element id.
   function Element_Id (Item : Event) return String;

   --  Return the handler action.
   --  @param Item Event value.
   --  @return Action name.
   function Action (Item : Event) return String;

   --  Check whether a field exists.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return True when the field exists.
   function Has_Field (Item : Event; Name : String) return Boolean;

   --  Return a field value.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return Field value or an empty string.
   function Field (Item : Event; Name : String) return String;

private
   type Event is record
      Event_Type : Event_Kind := Hello_Event;
      Element    : Ada.Strings.Unbounded.Unbounded_String;
      Act        : Ada.Strings.Unbounded.Unbounded_String;
      Fields     : Field_Maps.Map;
   end record;
end Web.Events;
