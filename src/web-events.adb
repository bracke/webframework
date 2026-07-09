with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings;
with Ada.Strings.Unbounded;
with Web.Errors;
with Web.Html;

package body Web.Events is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Fixed;
   use type Ada.Containers.Count_Type;

   function Is_Action_Name (Value : String) return Boolean is
   begin
      return Web.Html.Is_Valid_Id (Value);
   end Is_Action_Name;

   function Is_Field_Name (Value : String) return Boolean is
   begin
      return Web.Html.Is_Valid_Id (Value);
   end Is_Field_Name;

   procedure Validate_Field_Name (Name : String) is
   begin
      if Name'Length = 0
        or else Name'Length > Max_Field_Name_Length
        or else not Is_Field_Name (Name)
      then
         raise Web.Errors.Protocol_Error with "invalid event field name";
      end if;
   end Validate_Field_Name;

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
      Validate_Field_Name (Name);

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
         Fields     => Field_Maps.Empty_Map,
         Ack_Id     => Null_Unbounded_String,
         Message_Id => Null_Unbounded_String);
   end Create;

   function Create
     (Kind       : Event_Kind;
      Element_Id : Unbounded_String;
      Action     : Unbounded_String;
      Fields     : Field_Maps.Map) return Event
   is
   begin
      Validate_Event (Kind, To_String (Element_Id), To_String (Action));
      if Fields.Length > Ada.Containers.Count_Type (Max_Field_Count) then
         raise Web.Errors.Protocol_Error with "too many event fields";
      end if;

      for Cursor in Fields.Iterate loop
         Validate_Field_Name (Field_Maps.Key (Cursor));
         if Field_Maps.Element (Cursor)'Length > Max_Field_Value_Length then
            raise Web.Errors.Protocol_Error with "event field value too large";
         end if;
      end loop;

      return
        (Event_Type => Kind,
         Element    => Element_Id,
         Act        => Action,
         Fields     => Fields,
         Ack_Id     => Null_Unbounded_String,
         Message_Id => Null_Unbounded_String);
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

   procedure With_Element_Id (Item : Event) is
   begin
      Process (To_String (Item.Element));
   end With_Element_Id;

   function Action (Item : Event) return String is
   begin
      return To_String (Item.Act);
   end Action;

   procedure With_Action (Item : Event) is
   begin
      Process (To_String (Item.Act));
   end With_Action;

   function Has_Field (Item : Event; Name : String) return Boolean is
   begin
      Validate_Field_Name (Name);
      return Item.Fields.Contains (Name);
   end Has_Field;

   function Field (Item : Event; Name : String) return String is
      Cursor : Field_Maps.Cursor;
   begin
      Validate_Field_Name (Name);

      Cursor := Item.Fields.Find (Name);
      if Field_Maps.Has_Element (Cursor) then
         return Field_Maps.Element (Cursor);
      end if;

      return "";
   end Field;

   function Field_Or_Default
     (Item    : Event;
      Name    : String;
      Default : String) return String
   is
      Value : constant String := Field (Item, Name);
   begin
      if Value'Length = 0 then
         return Default;
      end if;

      return Value;
   end Field_Or_Default;

   function Required_Field (Item : Event; Name : String) return String is
      Value : constant String := Field (Item, Name);
   begin
      if Value'Length = 0 then
         raise Web.Errors.Protocol_Error with "required field is missing: " & Name;
      end if;

      return Value;
   end Required_Field;

   function Required_Non_Empty_Field (Item : Event; Name : String) return String is
      Raw : constant String := Required_Field (Item, Name);
      Trimmed : constant String := Trim (Raw, Ada.Strings.Both);
   begin
      if Trimmed'Length = 0 then
         raise Web.Errors.Protocol_Error with "required field is blank: " & Name;
      end if;

      return Trimmed;
   end Required_Non_Empty_Field;

   function Integer_Field (Item : Event; Name : String; Default : Integer) return Integer is
      Raw : constant String := Field_Or_Default (Item, Name, "");
      Trimmed : constant String := Trim (Raw, Ada.Strings.Both);
   begin
      if Trimmed'Length = 0 then
         return Default;
      end if;

      return Integer'Value (Trimmed);
   exception
      when others =>
         return Default;
   end Integer_Field;

   function Boolean_Field (Item : Event; Name : String; Default : Boolean) return Boolean is
      Value : constant String :=
        Ada.Characters.Handling.To_Lower
          (Trim (Field_Or_Default (Item, Name, ""), Ada.Strings.Both));
   begin
      if Value = "1" or else Value = "true" or else Value = "yes" or else Value = "on" then
         return True;
      elsif Value = "0" or else Value = "false" or else Value = "no" or else Value = "off" then
         return False;
      end if;

      return Default;
   end Boolean_Field;

   function Has_Non_Empty_Field (Item : Event; Name : String) return Boolean is
      Value : constant String := Field (Item, Name);
   begin
      return Trim (Value, Ada.Strings.Both)'Length > 0;
   exception
      when others =>
         return False;
   end Has_Non_Empty_Field;

   procedure With_Field (Item : Event; Name : String) is
      Cursor : Field_Maps.Cursor;
   begin
      Validate_Field_Name (Name);

      Cursor := Item.Fields.Find (Name);
      if Field_Maps.Has_Element (Cursor) then
         Process (Field_Maps.Element (Cursor));
      else
         Process ("");
      end if;
   end With_Field;

   --  Check whether the event requires acknowledgment.
   function Has_Ack_Id (Item : Event) return Boolean is
   begin
      return Length (Item.Ack_Id) > 0;
   end Has_Ack_Id;

   --  Return the acknowledgment id.
   function Get_Ack_Id (Item : Event) return String is
   begin
      return To_String (Item.Ack_Id);
   end Get_Ack_Id;

   --  Return the message id.
   function Get_Message_Id (Item : Event) return String is
   begin
      return To_String (Item.Message_Id);
   end Get_Message_Id;

   --  Check whether the event has a priority field.
   function Has_Priority (Item : Event) return Boolean is
   begin
      return Has_Field (Item, "priority");
   end Has_Priority;

   --  Return the message priority.
   function Get_Priority (Item : Event) return String is
   begin
      return Field (Item, "priority");
   end Get_Priority;

   --  Set the acknowledgment id for an event.
   procedure Set_Ack_Id (Item : in out Event; Value : String) is
   begin
      Item.Ack_Id := To_Unbounded_String (Value);
   end Set_Ack_Id;

   --  Set the message id for an event.
   procedure Set_Message_Id (Item : in out Event; Value : String) is
   begin
      Item.Message_Id := To_Unbounded_String (Value);
   end Set_Message_Id;
end Web.Events;
