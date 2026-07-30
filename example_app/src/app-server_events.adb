with Ada.Strings.Fixed;
with Web.SSE;

package body App.Server_Events is

   procedure Clock_Stream
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type)
   is
      pragma Unreferenced (Request);
      Ok : Boolean := True;
   begin
      for I in 1 .. 6 loop
         declare
            N : constant String :=
              Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both);
         begin
            Web.SSE.Send_Event
              (Conn, "Server tick " & N & " of 6",
               Event => "tick", Id => N, Ok => Ok);
            exit when not Ok;
            delay 0.5;
         end;
      end loop;
      if Ok then
         Web.SSE.Send_Event (Conn, "stream complete", Event => "end", Ok => Ok);
      end if;
   end Clock_Stream;

end App.Server_Events;
