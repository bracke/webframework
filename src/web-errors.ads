with Ada.Exceptions;
with Web.Config;
with Web.Response;

package Web.Errors is
   Bad_Request_Error : exception;
   Not_Found_Error   : exception;
   Protocol_Error    : exception;
   Security_Error    : exception;

   --  Convert an exception into a framework HTTP response.
   --  @param Occurrence Exception occurrence.
   --  @param Mode Runtime mode.
   --  @return HTTP response.
   function To_Response
     (Occurrence : Ada.Exceptions.Exception_Occurrence;
      Mode       : Web.Config.Mode_Type) return Web.Response.Response_Type;
end Web.Errors;
