with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package Web.Events is
   type Event_Kind is (Hello_Event, Click_Event, Submit_Event, Input_Event, Change_Event);

   Max_Element_Id_Length : constant Natural := 128;
   Max_Action_Length     : constant Natural := 128;
   Max_Field_Name_Length : constant Natural := 128;
   Max_Field_Value_Length : constant Natural := 8_192;
   Max_Field_Count       : constant Natural := 64;

   package Field_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

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

   --  Create a browser event from owned parsed storage.
   --  @param Kind Event kind.
   --  @param Element_Id Source element id storage.
   --  @param Action Handler action storage.
   --  @param Fields Parsed event fields.
   --  @return Event value.
   function Create
     (Kind       : Event_Kind;
      Element_Id : Ada.Strings.Unbounded.Unbounded_String;
      Action     : Ada.Strings.Unbounded.Unbounded_String;
      Fields     : Field_Maps.Map) return Event;

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

   --  Process the source element id without returning a copied string.
   --  @param Item Event value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Element_Id (Item : Event);

   --  Return the handler action.
   --  @param Item Event value.
   --  @return Action name.
   function Action (Item : Event) return String;

   --  Process the handler action without returning a copied string.
   --  @param Item Event value.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Action (Item : Event);

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

   --  Return a field value when present, otherwise return a default.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @param Default Field fallback value.
   --  @return Field value or Default.
   function Field_Or_Default
     (Item    : Event;
      Name    : String;
      Default : String) return String;

   --  Return a required field value.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return Field value.
   --  @exception Web.Errors.Protocol_Error when field is missing or empty.
   function Required_Field (Item : Event; Name : String) return String;

   --  Return a required non-empty field value.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return Field value.
   --  @exception Web.Errors.Protocol_Error when field is missing or blank.
   function Required_Non_Empty_Field (Item : Event; Name : String) return String;

   --  Return a checked numeric field with fallback.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @param Default Fallback value.
   --  @return Parsed integer, or Default when missing or invalid.
   function Integer_Field (Item : Event; Name : String; Default : Integer) return Integer;

   --  Return a checked boolean field with fallback.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @param Default Fallback value.
   --  @return Parsed boolean, or Default when missing or invalid.
   function Boolean_Field (Item : Event; Name : String; Default : Boolean) return Boolean;

   --  Check whether a field exists and is not blank.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return True when field exists and after trimming is non-empty.
   function Has_Non_Empty_Field (Item : Event; Name : String) return Boolean;

   --  Process a field value without returning a copied string.
   --  @param Item Event value.
   --  @param Name Field name.
   --  @return No return value.
   generic
      with procedure Process (Value : String);
   procedure With_Field (Item : Event; Name : String);

private
   type Event is record
      Event_Type : Event_Kind := Hello_Event;
      Element    : Ada.Strings.Unbounded.Unbounded_String;
      Act        : Ada.Strings.Unbounded.Unbounded_String;
      Fields     : Field_Maps.Map;
   end record;
end Web.Events;
