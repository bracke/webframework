with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Exceptions;
with Ada.Strings.Hash;
with Web.Errors;
with Web.Logging;
with Web.Html;

package body Web.Dispatcher is
   package Handler_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type     => String,
      Element_Type => Handler_Access,
      Hash         => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   Handlers : Handler_Maps.Map;

   procedure Register (Action : String; Handler : Handler_Access) is
      Position : Handler_Maps.Cursor;
      Inserted : Boolean;
   begin
      if Action'Length = 0
        or else Action'Length > Web.Events.Max_Action_Length
        or else not Web.Html.Is_Valid_Id (Action)
      then
         raise Web.Errors.Security_Error with "invalid dispatcher action";
      end if;

      if Handler = null then
         raise Web.Errors.Security_Error with "dispatcher handler is null";
      end if;

      Handler_Maps.Insert
        (Container => Handlers,
         Key       => Action,
         New_Item  => Handler,
         Position  => Position,
         Inserted  => Inserted);

      if not Inserted then
         raise Web.Errors.Security_Error with "duplicate dispatcher action";
      end if;
   end Register;

   function Dispatch
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      Action : constant String := Web.Events.Action (Event);
      Cursor : Handler_Maps.Cursor;
   begin
      if Action'Length = 0 then
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
      end if;

      Cursor := Handlers.Find (Action);
      if not Handler_Maps.Has_Element (Cursor) then
         Web.Logging.Warn ("unknown action: " & Action);
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
      end if;

      return Handler_Maps.Element (Cursor) (State, Event);
   exception
      when Error : others =>
         Web.Logging.Error ("handler failed: " & Ada.Exceptions.Exception_Message (Error));
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
   end Dispatch;
end Web.Dispatcher;
