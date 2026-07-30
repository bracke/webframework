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

   function Demo_Page
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      pragma Unreferenced (Context);
   begin
      return Web.Response.Html
        ("<!doctype html>"
         & "<html><head><meta charset=""utf-8"">"
         & "<title>Live events (SSE)</title></head>"
         & "<body><h1>Server-Sent Events</h1>"
         & "<p>Live one-way stream from <code>/events</code>:</p>"
         & "<ul id=""sse-log""></ul>"
         & "<p><a href=""/"">&larr; home</a></p>"
         & "<script src=""/static/sse-demo.js""></script>"
         & "</body></html>");
   end Demo_Page;

end App.Server_Events;
