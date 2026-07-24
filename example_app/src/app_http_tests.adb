with Ada.Command_Line;
with App.Http_Support;

--  HTTP-level integration test: drives requests through Web.Server.Dispatch,
--  exercising the whole chain (global principal resolver -> route guard ->
--  bridge -> authorization -> handler) including identity-session validation
--  and the role-conditioned policy. The logic lives in App.Http_Support so its
--  handlers are library-level. Exit status is non-zero on any failure.
procedure App_HTTP_Tests is
   Failures : Natural;
begin
   App.Http_Support.Run (Failures);
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end App_HTTP_Tests;
