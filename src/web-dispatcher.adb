with Ada.Exceptions;
with Web.Errors;
with Web.Logging;

package body Web.Dispatcher is
   package Handler_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type     => String,
      Element_Type => Handler_Access);

   Handlers : Handler_Maps.Map;

   procedure Register (Action : String; Handler : Handler_Access) is
   begin
      if Action'Length = 0 then
         raise Web.Errors.Security_Error with "dispatcher action is empty";
      end if;

      if Handler = null then
         raise Web.Errors.Security_Error with "dispatcher handler is null";
      end if;

      if Handlers.Contains (Action) then
         raise Web.Errors.Security_Error with "duplicate dispatcher action";
      end if;

      Handlers.Insert (Action, Handler);
   end Register;

   function Dispatch
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      Action : constant String := Web.Events.Action (Event);
   begin
      if Action'Length = 0 then
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
      end if;

      if not Handlers.Contains (Action) then
         Web.Logging.Warn ("unknown action: " & Action);
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
      end if;

      return Handlers.Element (Action) (State, Event);
   exception
      when Error : others =>
         Web.Logging.Error ("handler failed: " & Ada.Exceptions.Exception_Message (Error));
         return (Items => Web.Patch.Patch_Vectors.Empty_Vector);
   end Dispatch;
end Web.Dispatcher;
