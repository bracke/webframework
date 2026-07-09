with Ada.Exceptions;
with Web.Logging;

with Ada.Calendar;

package body Web.Errors is
   use type Web.Config.Mode_Type;

   function To_Response
     (Occurrence : Ada.Exceptions.Exception_Occurrence;
      Mode       : Web.Config.Mode_Type) return Web.Response.Response_Type
   is
      Message : constant String := Ada.Exceptions.Exception_Message (Occurrence);
   begin
      Web.Logging.Error (Ada.Exceptions.Exception_Information (Occurrence));

      if Mode = Web.Config.Development and then Message'Length > 0 then
         return Web.Response.Create (500, Web.Response.Generate_Error_Page (500, Message), "text/html; charset=utf-8");
      end if;

      return Web.Response.Internal_Server_Error;
   end To_Response;
end Web.Errors;
